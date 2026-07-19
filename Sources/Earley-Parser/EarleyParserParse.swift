//
//  EarleyParserParse.swift
//  Earley-Parser
//
//  Created by Ulf Akerstedt-Inoue on 2024/02/18.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Lexer
import OSLog
import Parser

let symbols = [
    "//", "/*", "*\\", ":", ":=", "::=", ",", "->", ".", "\"", "<=", ">=", "==", "!=", "!",
    ">", "{", "[", "<", "(", "!", "*", "|", "+", "-", "/", "'", "}", "]", ")", ";", "?", "#"
]
//let keywords: [String] = []

extension EarleyParser: GeneralizedParser {

    public typealias Label = NodeLabel

    /// Parses `string` by scanning it with GrammarTokenizer's general-purpose
    /// `Tokenizer` (configured with this module's fixed `symbols` list) and
    /// delegating to `parse(stream:)`.
    ///
    /// This preserves the exact tokenization this method always used; it is
    /// now a thin convenience over the stream-based entry point rather than
    /// its own separate implementation.
    public func parse(_ string: String) throws -> ParseResult<NodeLabel> {
        try parse(stream: TokenizerStream(source: string, symbols: Set(symbols), keywords: []))
    }

    /// Parses any `TokenStream` — the DFA-driven `LexerTokenStream` (built
    /// via a `LexerBuilder` bootstrapped from a `GrammarVocabulary`) and the
    /// hand-written `TokenizerStream` are both accepted interchangeably, as
    /// is any other conformance.
    ///
    /// - Parameter stream: A positioned sequence of tokens, each resolvable
    ///   to a `Terminal` and a source `Range<String.Index>`.
    /// - Returns: A `ParseResult` describing success, the BSR set, and the SPPF graph.
    /// - Throws: A `SyntaxError` if the input is not in the recognised language,
    ///   or whatever error `stream.terminal(at:)` throws for a lexical failure.
    public func parse<S: TokenStream>(stream: S) throws -> ParseResult<NodeLabel> {

        let nonTerminalProductions = Dictionary(grouping: grammar.productions, by: {$0.goal})

        // The start state contains all productions which can be reached directly from the starting non terminal
        let (initState, bsr) = nonTerminalProductions[grammar.start, default: []].map({ (production) -> ParseStateItem in
            ParseStateItem(production: production, productionPosition: 0, startTokenIndex: 0)
        }).collect(Set.init).collect { initState in
            processState(productions: nonTerminalProductions, allStates: [], knownItems: initState, newItems: initState, currentIndex: 0)
        }

        // Ranges collected as we scan — reused for SPPF/CST extraction below,
        // so the stream only needs to be walked once.
        var tokenRanges: [Range<String.Index>] = []
        tokenRanges.reserveCapacity(stream.count)

        Logger.earley.trace("(Grammar)\n\(grammar.wsn)")
        Logger.earley.trace("nullable non-terminals: \(grammar.nullableNonTerminals)")
        Logger.earley.trace("generated non-terminals: \(grammar.generatedNonTerminals)")
        Logger.earley.trace("earley items set [0]: \(initState)")

        var stateCollection: [Set<ParseStateItem>] = [initState]
        stateCollection.reserveCapacity(stream.count + 1)

        var bsrSet = Set<BSR<NodeLabel>>(bsr)

        var currentIndex: String.Index = stream.source.startIndex

        for n in 0..<stream.count {
            let lastState = stateCollection.last!

            // Collect all terminals which could occur at the current location according to the grammar
            // From `lastState` (last parse state), collect all `ParseStateItems` which have a terminal symbol
            // as their next symbol by peeking at the lookahead of the earley item.
            let (terminal, range) = try stream.terminal(at: n)
            let (newItemSet, scanBsr) = scan(state: lastState, token: terminal, currentIndex: n)

            // Report a syntax error if no new Earley items could be found.
            guard !newItemSet.isEmpty else {
                throw errorHandling(lastState: lastState, productions: nonTerminalProductions, input: stream.source, index: currentIndex)
            }

            tokenRanges.append(range)
            Logger.earley.trace("input[\(n)] -> earley items(\(n+1)): \(newItemSet)\n")
            bsrSet.formUnion(scanBsr)

            // Pass the correct current index (n+1 = the index of the new state being built).
            let (state, stateBsr) = processState(productions: nonTerminalProductions, allStates: stateCollection, knownItems: newItemSet, newItems: newItemSet, currentIndex: n + 1)
            stateCollection.append(state)
            currentIndex = range.upperBound
            bsrSet.formUnion(stateBsr)

            Logger.earley.trace("earley items set [\(n+1)]: \(stateCollection[n+1])")
        }

        // When building the parse tree we only need the completed Earley items.
        // Collect all successfully parsed Earley items (completed items).
        let parseStates = stateCollection.enumerated().reduce(Array<Set<CompletedItem>>(repeating: [], count: stateCollection.count)) { (parseStates, element) in
            let (index, state) = element
            let completed = state.filter { $0.isCompleted }
            return completed.reduce(into: parseStates) { (parseStates, item) in
                parseStates[item.startTokenIndex].insert(CompletedItem(production: item.production, completedIndex: index))
            }
        }

        // Check success: the final state must contain a completed item for a production
        // whose goal matches the start symbol spanning the entire input (startTokenIndex == 0).
        let isSuccessful = stateCollection[tokenRanges.count].contains { item in
            item.production.goal == grammar.start &&
            item.isCompleted &&
            item.startTokenIndex == 0
        }

        Logger.earley.trace("completed earley items: \(parseStates)")
        Logger.earley.trace("tokenization length: \(tokenRanges.count)")
        Logger.earley.trace("parse result isSuccessful: \(isSuccessful)")
        Logger.earley.trace("parse successful: \(isSuccessful ? "YES" : "NO")")

        // Build the SPPF from the BSR set (reuse the ranges collected above).
        return ParseResult(
            isSuccessful: isSuccessful,
            bsr: bsrSet,
            sppfGraph: isSuccessful ? extractSPPF(tokenCount: tokenRanges.count, bsr: bsrSet) : nil
        )
    }

    func errorHandling(lastState: Set<ParseStateItem>, productions: [NonTerminal:[Production]],
        input string: String, index: String.Index) -> SyntaxError {

        // Find non terminals which are expected at the current location
        let context: [NonTerminal] = lastState.compactMap { item -> NonTerminal? in
            switch item.nextSymbol {
            case .none:
                return nil
            case .some(.terminal):
                return nil
            case .some(.metaSymbol):
                return nil
            case .some(.nonTerminal(let nonTerminal)):
                return nonTerminal
            }
        }.filter { nonTerminal in
            productions[nonTerminal, default: []].contains(where: { production -> Bool in
                // `production.rule.first` is `nil` for an epsilon production (`rule == []`),
                // so it correctly never matches here — an ε-alternative doesn't itself
                // "start with a terminal" for the purposes of an "expected token" message.
                if case .some(.terminal(_)) = production.rule.first {
                    return true
                } else {
                    return false
                }
            })
        }

        return SyntaxError(
            range: index ..< string.index(after: index),
            in: string,
            reason: context.isEmpty ? .unexpectedToken : .unmatchedPattern,
            context: context
        )
    }
}
