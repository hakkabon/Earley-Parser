//
//  TreeBuilder.swift
//  Earley-Parser
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/26.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Lexer
import Parser

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
        let tree = sppf.buildParseTree(startSymbol: grammar.start.name, ranges: ranges, string: string)
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
        let trees = sppf.buildAllParseTrees(startSymbol: grammar.start.name, ranges: ranges, string: string)
        if trees.isEmpty {
            throw SyntaxError(range: string.startIndex..<string.endIndex, in: string, reason: .unmatchedPattern)
        }
        return trees
    }
}
