//
//  EarleyParserParse.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2024/02/18.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Tokenizer
import OSLog

let symbols = [
    "//", "/*", "*\\", ":", ":=", "::=", ",", "->", ".", "\"", "<=", ">=", "==", "!=", "!",
    ">", "{", "[", "<", "(", "!", "*", "|", "+", "-", "/", "'", "}", "]", ")", ";", "?", "#"
]
//let keywords: [String] = []

extension EarleyParser: DeterministicParser {
    
    public func syntaxTree(for string: String) throws -> ParseTree {
        let result = try parse(string)
        guard result.isSuccessful, let sppf = result.sppfGraph else {
            throw SyntaxError(range: string.startIndex..<string.endIndex, in: string, reason: .unmatchedPattern)
        }
        
        let inputTokens = Tokenizer(string, symbols: Set(symbols), keywords: Set([])).tokenize()
        Thread.current.threadDictionary["EarleyParserTokens"] = inputTokens
        Thread.current.threadDictionary["EarleyParserString"] = string
        defer {
            Thread.current.threadDictionary.removeObject(forKey: "EarleyParserTokens")
            Thread.current.threadDictionary.removeObject(forKey: "EarleyParserString")
        }
        
        let tree = buildParseTree(bsr: result.bsr, sppf: sppf)
        if case .empty = tree {
            throw SyntaxError(range: string.startIndex..<string.endIndex, in: string, reason: .unmatchedPattern)
        }
        return tree
    }
}

extension EarleyParser {
     
    public func allSyntaxTrees(for string: String) throws -> [ParseTree] {
        let result = try parse(string)
        guard result.isSuccessful, let sppf = result.sppfGraph else {
            throw SyntaxError(range: string.startIndex..<string.endIndex, in: string, reason: .unmatchedPattern)
        }
        
        let inputTokens = Tokenizer(string, symbols: Set(symbols), keywords: Set([])).tokenize()
        Thread.current.threadDictionary["EarleyParserTokens"] = inputTokens
        Thread.current.threadDictionary["EarleyParserString"] = string
        defer {
            Thread.current.threadDictionary.removeObject(forKey: "EarleyParserTokens")
            Thread.current.threadDictionary.removeObject(forKey: "EarleyParserString")
        }
        
        let trees = buildAllParseTrees(sppf: sppf)
        if trees.isEmpty {
            throw SyntaxError(range: string.startIndex..<string.endIndex, in: string, reason: .unmatchedPattern)
        }
        return trees
    }

    // MARK: - SyntaxTree construction helpers

    private func buildParseTree(bsr: Set<BinarySubtreeRepresentation>, sppf: SPPFGraph) -> ParseTree {
        return buildAllParseTrees(sppf: sppf).first ?? .empty
    }

    private func buildAllParseTrees(sppf: SPPFGraph) -> [ParseTree] {
        guard let tokens = Thread.current.threadDictionary["EarleyParserTokens"] as? [Token],
              let string = Thread.current.threadDictionary["EarleyParserString"] as? String else {
            return []
        }

        let n = tokens.count
        let startSymbol = grammar.start.name

        let rootNodes = sppf.getAllNodes().filter { node in
            if case let .symbol(label, leftExtent, rightExtent) = node {
                return label == startSymbol && leftExtent == 0 && rightExtent == n
            }
            return false
        }

        var allTrees: [ParseTree] = []
        for rootNode in rootNodes {
            // Fresh memo table per root: avoids cross-root contamination while still
            // sharing memoised sub-results within a single root's sub-forest.
            var memo: [GraphNode: [[ParseTree]]?] = [:]
            let alts = extractNodeAlternatives(
                node: rootNode, sppf: sppf,
                tokens: tokens, string: string, memo: &memo)
            for alt in alts {
                if let first = alt.first {
                    allTrees.append(first)
                }
            }
        }
        return deduplicateParseTrees(allTrees)
    }
}

extension EarleyParser: GeneralizedParser {

    public func parse(_ string: String) throws -> ParseResult {
        
        let nonTerminalProductions = Dictionary(grouping: grammar.productions, by: {$0.goal})

        // The start state contains all productions which can be reached directly from the starting non terminal
        let (initState, bsr) = nonTerminalProductions[grammar.start, default: []].map({ (production) -> ParseStateItem in
            ParseStateItem(production: production, productionPosition: 0, startTokenIndex: 0)
        }).collect(Set.init).collect { initState in
            processState(productions: nonTerminalProductions, allStates: [], knownItems: initState, newItems: initState, currentIndex: 0)
        }

        // Tokenize once and reuse throughout the parse.
        let inputTokens = Tokenizer(string, symbols: Set(symbols), keywords: Set([])).tokenize()
        var tokenization: [[(terminal: Terminal, range: Range<String.Index>)]] = []
        tokenization.reserveCapacity(inputTokens.count)

        Logger.earley.trace("(Grammar)\n\(grammar.wsn)")
        Logger.earley.trace("nullable non-terminals: \(grammar.nullableNonTerminals)")
        Logger.earley.trace("generated non-terminals: \(grammar.generatedNonTerminals)")
        Logger.earley.trace("input tokens: \(inputTokens)")
        Logger.earley.trace("earley items set [0]: \(initState)")

        var stateCollection: [Set<ParseStateItem>] = [initState]
        stateCollection.reserveCapacity(inputTokens.count + 1)

        var bsrSet = Set<BinarySubtreeRepresentation>(bsr)

        var currentIndex: String.Index = string.startIndex

        for (n, inputToken) in inputTokens.enumerated() {
            let lastState = stateCollection.last!

            // Collect all terminals which could occur at the current location according to the grammar
            // From `lastState` (last parse state), collect all `ParseStateItems` which have a terminal symbol
            // as their next symbol by peeking at the lookahead of the earley item.
            let newItems: (setItems: Set<ParseStateItem>, terminal: Terminal, range: Range<String.Index>, bsr: Set<BinarySubtreeRepresentation>)? = {
                let (terminal, range) = switch inputToken.type {
                case .symbol(let token):
                    (Terminal(string: token), inputToken.range)
                case .literal(let token):
                    (Terminal(string: token), inputToken.range)
                case .identifier(let token):
                    (Terminal(string: token), inputToken.range)
                case .number(let token):
                    switch token {
                    case .decimal(let value), .binary(let value), .octal(let value), .hexadecimal(let value):
                        (Terminal(string: "\(value)"), inputToken.range)
                    }
                default:
                    fatalError("symbol \(inputToken) not recognized")
                }
                let (items, bsr) = scan(state: lastState, token: terminal, currentIndex: n)
                return (setItems: items, terminal: terminal, range: range, bsr: bsr)
            }()
            
            // Report a syntax error if no new Earley items could be found.
            guard let newItems = newItems, !newItems.setItems.isEmpty else {
                throw errorHandling(lastState: lastState, productions: nonTerminalProductions, input: string, index: currentIndex)
            }

            let newItemSet = newItems.setItems
            tokenization.append([(terminal: newItems.terminal, range: newItems.range)])
            Logger.earley.trace("input[\(n)] \(inputToken) -> earley items(\(n+1)): \(newItemSet)\n")
            bsrSet.formUnion(newItems.bsr)

            // Pass the correct current index (n+1 = the index of the new state being built).
            let (state, stateBsr) = processState(productions: nonTerminalProductions, allStates: stateCollection, knownItems: newItemSet, newItems: newItemSet, currentIndex: n + 1)
            stateCollection.append(state)
            currentIndex = newItems.range.upperBound
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
        let isSuccessful = stateCollection[tokenization.count].contains { item in
            item.production.goal == grammar.start &&
            item.isCompleted &&
            item.startTokenIndex == 0
        }
        
        Logger.earley.trace("completed earley items: \(parseStates)")
        Logger.earley.trace("tokenization: \(tokenization)")
        Logger.earley.trace("tokenization length: \(tokenization.count)")
        Logger.earley.trace("parse result isSuccessful: \(isSuccessful)")
        Logger.earley.trace("parse successful: \(isSuccessful ? "YES" : "NO")")
        
        // Build the SPPF from the BSR set (reuse already-tokenized tokens).
        return ParseResult(
            isSuccessful: isSuccessful,
            bsr: bsrSet,
            sppfGraph: isSuccessful ? extractSPPF(tokens: inputTokens, bsr: bsrSet) : nil
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
