//
//  TreeBuilder.swift
//  Earley-Parser
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/26.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Lexer

extension EarleyParser: DeterministicParser {

    public func syntaxTree(for string: String) throws -> ParseTree {
        // Built once and reused both for the parse itself and for the token
        // ranges tree-building needs below — avoids scanning `string` twice.
        let stream = TokenizerStream(source: string, symbols: Set(symbols), keywords: [])
        let result = try parse(stream: stream)
        guard result.isSuccessful, let sppf = result.sppfGraph else {
            throw SyntaxError(range: string.startIndex..<string.endIndex, in: string, reason: .unmatchedPattern)
        }

        let ranges = try stream.terminals().map(\.range)
        Thread.current.threadDictionary["EarleyParserRanges"] = ranges
        Thread.current.threadDictionary["EarleyParserString"] = string
        defer {
            Thread.current.threadDictionary.removeObject(forKey: "EarleyParserRanges")
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
        let stream = TokenizerStream(source: string, symbols: Set(symbols), keywords: [])
        let result = try parse(stream: stream)
        guard result.isSuccessful, let sppf = result.sppfGraph else {
            throw SyntaxError(range: string.startIndex..<string.endIndex, in: string, reason: .unmatchedPattern)
        }

        let ranges = try stream.terminals().map(\.range)
        Thread.current.threadDictionary["EarleyParserRanges"] = ranges
        Thread.current.threadDictionary["EarleyParserString"] = string
        defer {
            Thread.current.threadDictionary.removeObject(forKey: "EarleyParserRanges")
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
        guard let ranges = Thread.current.threadDictionary["EarleyParserRanges"] as? [Range<String.Index>],
              let string = Thread.current.threadDictionary["EarleyParserString"] as? String else {
            return []
        }

        let n = ranges.count
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
                ranges: ranges, string: string, memo: &memo)
            for alt in alts {
                if let first = alt.first {
                    allTrees.append(first)
                }
            }
        }
        return deduplicateParseTrees(allTrees)
    }
}
