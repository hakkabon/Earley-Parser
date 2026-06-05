//
//  GeneralizedParser.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2023/08/11.
//  Copyright © 2023 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

/// The outcome of a parse attempt.
public struct ParseResult {
    public let isSuccessful: Bool
    public let bsr: Set<BinarySubtreeRepresentation>
    public let sppfGraph: SPPFGraph?

    /// Returns `true` if any non-terminal or intermediate SPPF node has more than one
    /// packed-node child, indicating that the grammar is locally ambiguous on this input.
    ///
    /// A packed node having two children is a normal binary split, not an ambiguity.
    /// Only `.symbol` and `.intermediate` nodes with multiple children signal ambiguity.
    public var hasAmbiguity: Bool {
        guard let graph = sppfGraph else { return false }
        return graph.getAllNodes().contains { node in
            switch node {
            case .symbol, .intermediate:
                return graph.getChildren(of: node).count > 1
            default:
                return false
            }
        }
    }
}

/// A parser that recognises general (including ambiguous) context-free grammars and can
/// produce every derivation of an input string as a structured parse forest.
public protocol GeneralizedParser {

    /// Run the recogniser/parser on `string` and return the raw `ParseResult`.
    ///
    /// The result exposes the BSR set and the SPPF graph from which individual syntax
    /// trees can be extracted.  Use `allSyntaxTrees(for:)` if you want ready-made trees.
    ///
    /// - Parameter string: Input string to parse.
    /// - Returns: A `ParseResult` describing success, the BSR set, and the SPPF graph.
    /// - Throws: A `SyntaxError` if the string is not in the recognised language.
    func parse(_ string: String) throws -> ParseResult

    /// Returns **all** parse trees for `string`.
    ///
    /// For unambiguous grammars this returns exactly one tree.  For ambiguous grammars it
    /// returns one tree per distinct derivation.  Duplicates are removed before returning.
    ///
    /// - Parameter string: Input string to parse.
    /// - Returns: All syntax trees explaining how `string` was derived from the grammar.
    /// - Throws: A `SyntaxError` if the string is not in the recognised language.
    func allSyntaxTrees(for string: String) throws -> [ParseTree]
}
