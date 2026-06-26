//
//  TreeBuilder.swift
//  Earley-Parser
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/26.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Tokenizer

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

    private func buildParseTree(bsr: Set<BSR>, sppf: SPPFGraph) -> ParseTree {
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
            var memo: [SPPFNode: [[ParseTree]]?] = [:]
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
