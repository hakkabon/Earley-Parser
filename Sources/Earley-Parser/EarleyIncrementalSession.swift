import Foundation
import Grammar
import IncrementalParsing
import Lexer
import Parser

/// One live, package-owned Earley document. The session retains completed
/// chart columns and the BSR contribution produced by each column. An edit
/// reuses the exact prefix whose stable token identities and terminals still
/// agree, invalidates the dependent native facts, and resumes scanner,
/// predictor, and completer execution at the first changed token.
public final class EarleyIncrementalSession: @unchecked Sendable {
    private struct Token {
        let terminal: Terminal
        let identity: EarleyTokenIdentity
    }

    private let parser: EarleyParser
    private let lock = NSLock()
    private let chart = EarleyIncrementalChart<ParseStateItem>()
    private var tokens: [Token] = []
    private var states: [Set<ParseStateItem>] = []
    private var bsrByColumn: [Set<BSR<NodeLabel>>] = []
    private var nextTokenIdentity: UInt64 = 0
    private var hasBaseline = false

    public init(parser: EarleyParser) {
        self.parser = parser
    }

    public convenience init(grammar: Grammar) {
        self.init(parser: EarleyParser(grammar: grammar))
    }

    public func parse(_ source: String) throws -> EarleyIncrementalParseResult {
        try parse(stream: TokenizerStream(
            source: source, symbols: Set(symbols), keywords: []))
    }

    public func parse<S: TokenStream>(
        stream: S,
        tokenIdentities suppliedIdentities: [EarleyTokenIdentity]? = nil
    ) throws -> EarleyIncrementalParseResult {
        lock.lock()
        defer { lock.unlock() }

        var terminals: [Terminal] = []
        var ranges: [Range<String.Index>] = []
        terminals.reserveCapacity(stream.count)
        ranges.reserveCapacity(stream.count)
        for index in 0..<stream.count {
            let (terminal, range) = try stream.terminal(at: index)
            terminals.append(terminal)
            ranges.append(range)
        }
        if let suppliedIdentities {
            guard suppliedIdentities.count == terminals.count else {
                throw EarleyIncrementalSessionError.tokenIdentityCountMismatch(
                    expected: terminals.count,
                    actual: suppliedIdentities.count)
            }
            guard Set(suppliedIdentities).count == suppliedIdentities.count else {
                throw EarleyIncrementalSessionError.duplicateTokenIdentity
            }
        }

        let nextTokens = makeTokens(
            terminals: terminals, suppliedIdentities: suppliedIdentities)
        let reusablePrefix = hasBaseline ? commonPrefix(tokens, nextTokens) : 0
        let previousTokenCount = tokens.count
        let previousColumnCount = states.count
        let previousFactCount = chart.count
        let invalidation: EarleyChartInvalidation

        if !hasBaseline {
            _ = chart.bind(to: parser.incrementalArtifactIdentity)
            invalidation = .init(removed: [], retained: [])
        } else {
            let changed = Set(tokens.dropFirst(reusablePrefix).map(\.identity))
            invalidation = chart.invalidate(tokens: changed)
        }

        let productions = Dictionary(
            grouping: parser.grammar.productions, by: \Production.goal)
        var nextStates: [Set<ParseStateItem>]
        var nextBSRByColumn: [Set<BSR<NodeLabel>>]
        if hasBaseline, reusablePrefix < states.count {
            nextStates = Array(states.prefix(reusablePrefix + 1))
            nextBSRByColumn = Array(bsrByColumn.prefix(reusablePrefix + 1))
        } else {
            let initialItems = Set(productions[parser.grammar.start, default: []].map {
                ParseStateItem(
                    production: $0, productionPosition: 0,
                    startTokenIndex: 0)
            })
            let (initialState, initialBSR) = parser.processState(
                productions: productions, allStates: [],
                knownItems: initialItems, newItems: initialItems,
                currentIndex: 0)
            nextStates = [initialState]
            nextBSRByColumn = [initialBSR]
        }

        recordColumn(
            index: reusablePrefix == 0 && !hasBaseline ? 0 : reusablePrefix,
            state: nextStates[reusablePrefix], tokens: nextTokens)

        for index in reusablePrefix..<nextTokens.count {
            let previous = nextStates[index]
            let (scanned, scanBSR) = parser.scan(
                state: previous, token: nextTokens[index].terminal,
                currentIndex: index)
            guard !scanned.isEmpty else {
                discardBaseline()
                throw parser.errorHandling(
                    lastState: previous, productions: productions,
                    input: stream.source, index: ranges[index].lowerBound)
            }
            let (state, stateBSR) = parser.processState(
                productions: productions, allStates: nextStates,
                knownItems: scanned, newItems: scanned,
                currentIndex: index + 1)
            nextStates.append(state)
            nextBSRByColumn.append(scanBSR.union(stateBSR))
            recordColumn(index: index + 1, state: state, tokens: nextTokens)
        }

        let bsr = nextBSRByColumn.reduce(into: Set<BSR<NodeLabel>>()) {
            $0.formUnion($1)
        }
        let successful = nextStates[nextTokens.count].contains {
            $0.production.goal == parser.grammar.start
                && $0.isCompleted
                && $0.startTokenIndex == 0
        }
        let result = ParseResult(
            isSuccessful: successful,
            bsr: bsr,
            sppfGraph: successful
                ? parser.extractSPPF(tokenCount: nextTokens.count, bsr: bsr)
                : nil)

        tokens = nextTokens
        states = nextStates
        bsrByColumn = nextBSRByColumn
        let wasIncremental = hasBaseline
        hasBaseline = true

        let reusedColumns = wasIncremental ? reusablePrefix + 1 : 0
        let rebuiltColumns = nextStates.count - reusedColumns
        let rebuiltFacts = max(0, chart.count - invalidation.retained.count)
        let evidence = IncrementalExecutionEvidence(
            strategy: wasIncremental ? .incremental : .full,
            measurements: [
                .init(
                    dimension: .chartColumns,
                    reused: reusedColumns,
                    rebuilt: rebuiltColumns,
                    removed: max(0, previousColumnCount - reusedColumns),
                    strategy: "live-earley-prefix-resumption"),
                .init(
                    dimension: .chartFacts,
                    reused: invalidation.retained.count,
                    rebuilt: rebuiltFacts,
                    removed: invalidation.removed.count,
                    strategy: "dependency-indexed-invalidation"),
                .init(
                    dimension: .tokens,
                    reused: reusablePrefix,
                    rebuilt: nextTokens.count - reusablePrefix,
                    removed: max(0, previousTokenCount - reusablePrefix),
                    strategy: "stable-token-prefix"),
            ])
        assert(previousFactCount >= invalidation.removed.count)
        return .init(
            result: result,
            reusedChartColumnCount: reusedColumns,
            rebuiltChartColumnCount: rebuiltColumns,
            evidence: evidence)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        discardBaseline()
    }

    private func discardBaseline() {
        tokens = []
        states = []
        bsrByColumn = []
        chart.reset()
        nextTokenIdentity = 0
        hasBaseline = false
    }

    private func makeTokens(
        terminals: [Terminal],
        suppliedIdentities: [EarleyTokenIdentity]?
    ) -> [Token] {
        if let suppliedIdentities {
            return zip(terminals, suppliedIdentities).map {
                Token(terminal: $0, identity: $1)
            }
        }
        let prefix = commonTerminalPrefix(terminals)
        let suffix = commonTerminalSuffix(terminals, excludingPrefix: prefix)
        var result: [Token] = []
        result.reserveCapacity(terminals.count)
        for index in terminals.indices {
            let identity: EarleyTokenIdentity
            if index < prefix {
                identity = tokens[index].identity
            } else if index >= terminals.count - suffix {
                let oldIndex = tokens.count - (terminals.count - index)
                identity = tokens[oldIndex].identity
            } else {
                identity = .init("earley-token-\(nextTokenIdentity)")
                nextTokenIdentity += 1
            }
            result.append(.init(terminal: terminals[index], identity: identity))
        }
        return result
    }

    private func commonPrefix(_ old: [Token], _ new: [Token]) -> Int {
        zip(old, new).prefix {
            $0.identity == $1.identity && $0.terminal == $1.terminal
        }.count
    }

    private func commonTerminalPrefix(_ new: [Terminal]) -> Int {
        zip(tokens.map(\.terminal), new).prefix { $0 == $1 }.count
    }

    private func commonTerminalSuffix(
        _ new: [Terminal], excludingPrefix prefix: Int
    ) -> Int {
        let maximum = min(tokens.count, new.count) - prefix
        return zip(tokens.map(\.terminal).reversed(), new.reversed())
            .prefix(maximum).prefix { $0 == $1 }.count
    }

    private func recordColumn(
        index: Int,
        state: Set<ParseStateItem>,
        tokens: [Token]
    ) {
        let dependencies = Set(tokens.prefix(index).map(\.identity))
        for item in state {
            let id = EarleyChartFactID([
                String(index), GrammarProductionID(item.production).rawValue,
                String(item.productionPosition), String(item.startTokenIndex),
            ].joined(separator: "|"))
            chart.record(.init(
                id: id, value: item,
                tokenDependencies: dependencies,
                productionDependencies: [GrammarProductionID(item.production)]))
        }
    }
}

public struct EarleyIncrementalParseResult {
    public let result: ParseResult<NodeLabel>
    public let reusedChartColumnCount: Int
    public let rebuiltChartColumnCount: Int
    public let evidence: IncrementalExecutionEvidence
}

public enum EarleyIncrementalSessionError: Error, Hashable, Sendable {
    case tokenIdentityCountMismatch(expected: Int, actual: Int)
    case duplicateTokenIdentity
}
