import Foundation
import Grammar
import Lexer
import Parser

/// A generalized parse together with portable recovery evidence.
public struct EarleyRecoveryResult {
    public let status: ParseStatus
    public let parseResult: ParseResult<NodeLabel>?
    public let diagnostics: [ParseDiagnostic]
    public let recoveryEdits: [RecoveryEdit]
    public let exploredStates: Int
    public let reachedSearchLimit: Bool

    public init(
        status: ParseStatus,
        parseResult: ParseResult<NodeLabel>?,
        diagnostics: [ParseDiagnostic],
        recoveryEdits: [RecoveryEdit],
        exploredStates: Int,
        reachedSearchLimit: Bool
    ) {
        self.status = status
        self.parseResult = parseResult
        self.diagnostics = diagnostics
        self.recoveryEdits = recoveryEdits
        self.exploredStates = exploredStates
        self.reachedSearchLimit = reachedSearchLimit
    }
}

private struct RecoveryTokenStream: TokenStream {
    let source: String
    let entries: [(terminal: Terminal, range: Range<String.Index>)]

    var count: Int { entries.count }

    func terminal(at position: Int) -> (terminal: Terminal, range: Range<String.Index>) {
        entries[position]
    }
}

public extension EarleyParser {
    /// Convenience recovery entry point using Earley's established tokenizer.
    func parseRecovering(
        _ string: String,
        insertionCandidates: [Terminal]? = nil,
        policy: GeneralizedRecoveryPolicy = .init()
    ) throws -> EarleyRecoveryResult {
        try parseRecovering(
            stream: TokenizerStream(source: string, symbols: Set(symbols), keywords: []),
            insertionCandidates: insertionCandidates,
            policy: policy
        )
    }

    /// Parses a token stream and, on failure, performs a bounded minimum-edit
    /// search using the same Earley recognizer. The successful retry therefore
    /// retains the engine's BSR and SPPF rather than manufacturing a fallback
    /// tree outside the parser.
    func parseRecovering<S: TokenStream>(
        stream: S,
        insertionCandidates: [Terminal]? = nil,
        policy: GeneralizedRecoveryPolicy = .init()
    ) throws -> EarleyRecoveryResult {
        let entries = try stream.terminals()
        let original = entries.map(\.terminal)

        if let accepted = try? parse(stream: stream), accepted.isSuccessful {
            return .init(
                status: .accepted, parseResult: accepted, diagnostics: [],
                recoveryEdits: [], exploredStates: 1, reachedSearchLimit: false
            )
        }

        let candidates = insertionCandidates ?? grammar.terminals
            .filter { !$0.isEmpty }
            .sorted { $0.description < $1.description }
        let search = GeneralizedRecoverySearch<Terminal>()
        let repair = search.recover(
            original, insertionCandidates: candidates, policy: policy
        ) { terminals in
            let retry = RecoveryTokenStream(
                source: stream.source,
                entries: terminals.map { ($0, stream.source.endIndex..<stream.source.endIndex) }
            )
            return (try? parse(stream: retry).isSuccessful) == true
        }

        guard repair.repairedInput != nil else {
            let diagnostic = ParseDiagnostic(
                reason: .noViableAlternative,
                message: repair.reachedSearchLimit
                    ? "Generalized recovery exhausted its search budget."
                    : "No repair was found within the configured edit cost.",
                tokenIndex: original.count,
                source: stream.source
            )
            return .init(
                status: .rejected, parseResult: nil, diagnostics: [diagnostic],
                recoveryEdits: [], exploredStates: repair.exploredStates,
                reachedSearchLimit: repair.reachedSearchLimit
            )
        }

        var repairedEntries = entries
        var diagnostics: [ParseDiagnostic] = []
        var portableEdits: [RecoveryEdit] = []
        for edit in repair.edits {
            switch edit {
            case .insert(let terminal, let position):
                let boundary = position < repairedEntries.count
                    ? repairedEntries[position].range.lowerBound
                    : stream.source.endIndex
                repairedEntries.insert((terminal, boundary..<boundary), at: position)
                diagnostics.append(ParseDiagnostic(
                    severity: .warning,
                    reason: .missingToken,
                    message: "Inserted missing \(terminal.description).",
                    range: boundary..<boundary,
                    expected: [terminal],
                    tokenIndex: position,
                    source: stream.source
                ))
            case .delete(let terminal, let position):
                let removed = repairedEntries.remove(at: position)
                diagnostics.append(ParseDiagnostic(
                    severity: .warning,
                    reason: .extraToken,
                    message: "Deleted unexpected \(terminal.description).",
                    range: removed.range,
                    found: terminal,
                    tokenIndex: position,
                    source: stream.source
                ))
            }
            portableEdits.append(edit.parserRecoveryEdit)
        }

        let recoveredStream = RecoveryTokenStream(source: stream.source, entries: repairedEntries)
        let recovered = try parse(stream: recoveredStream)
        return .init(
            status: .recovered, parseResult: recovered, diagnostics: diagnostics,
            recoveryEdits: portableEdits, exploredStates: repair.exploredStates,
            reachedSearchLimit: false
        )
    }
}
