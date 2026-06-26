//
//  CSTEnumeration.swift
//  Earley-Parser
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/03.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Tokenizer

extension EarleyParser {

    // MARK: - Public entry points (called from EarleyParserParse.swift)

    /// Recursively extract all derivations for `node` from the SPPF graph.
    ///
    /// Returns an array of alternatives, where each alternative is a flat list of
    /// `ParseTree` children that should be placed under the parent non-terminal.
    ///
    /// - Parameters:
    ///   - node:   The SPPF graph node to expand.
    ///   - sppf:   The shared-packed-parse-forest graph.
    ///   - tokens: Tokenised input (used to map token indices → `String.Index` ranges).
    ///   - string: The original input string.
    ///   - memo:   Memoisation table keyed by `GraphNode`.  An entry maps a node to
    ///             the list-of-alternatives already computed for it.  A sentinel value
    ///             of `nil` indicates the node is currently being expanded (cycle guard).
    func extractNodeAlternatives(
        node: SPPFNode,
        sppf: SPPFGraph,
        tokens: [Token],
        string: String,
        memo: inout [SPPFNode: [[ParseTree]]?]
    ) -> [[ParseTree]] {

        // --- Cycle guard / memoisation ---
        if let cached = memo[node] {
            // Either a completed memo hit (`[[ParseTree]]`) or a cycle sentinel (`nil`).
            return cached ?? []          // nil (cycle) → return empty
        }
        // Mark as "in progress" to break cycles.
        memo[node] = .some(nil)         // Optional<[[ParseTree]]>.some(.none) == cycle sentinel

        let result = _expandNode(node: node, sppf: sppf, tokens: tokens, string: string, memo: &memo)

        memo[node] = .some(result)      // store the real result
        return result
    }

    // MARK: - Internal expansion helpers

    private func _expandNode(
        node: SPPFNode,
        sppf: SPPFGraph,
        tokens: [Token],
        string: String,
        memo: inout [SPPFNode: [[ParseTree]]?]
    ) -> [[ParseTree]] {

        switch node {

        // ── Leaf: terminal token ───────────────────────────────────────────────
        case let .leaf(_, leftExtent, rightExtent):
            let range = charRange(left: leftExtent, right: rightExtent,
                                  tokens: tokens, string: string)
            return [[.leaf(range)]]

        // ── Symbol: non-terminal ───────────────────────────────────────────────
        case let .symbol(label, _, _):
            let nonTerminal = NonTerminal(name: label)
            let children = sppf.getChildren(of: node)
            var alternatives: [[ParseTree]] = []

            for child in children {
                guard case .packed = child else { continue }
                let packedAlts = extractNodeAlternatives(
                    node: child, sppf: sppf, tokens: tokens, string: string, memo: &memo)
                for alt in packedAlts {
                    alternatives.append([.node(nonTerminal, children: alt)])
                }
            }
            if alternatives.isEmpty {
                // Epsilon derivation for a nullable non-terminal.
                alternatives = [[.node(nonTerminal, children: [])]]
            }
            return alternatives

        // ── Intermediate: partial production prefix ───────────────────────────
        case .intermediate:
            let children = sppf.getChildren(of: node)
            var alternatives: [[ParseTree]] = []
            for child in children {
                guard case .packed = child else { continue }
                let packedAlts = extractNodeAlternatives(
                    node: child, sppf: sppf, tokens: tokens, string: string, memo: &memo)
                alternatives.append(contentsOf: packedAlts)
            }
            return alternatives

        // ── Packed: one specific production application ────────────────────────
        case let .packed(label, leftExtent, rightExtent, pivot):
            return _expandPackedNode(
                label: label,
                leftExtent: leftExtent, rightExtent: rightExtent, pivot: pivot,
                node: node, sppf: sppf, tokens: tokens, string: string, memo: &memo)
        }
    }

    private func _expandPackedNode(
        label: NodeLabel,
        leftExtent: Int,
        rightExtent: Int,
        pivot: Int,
        node: SPPFNode,
        sppf: SPPFGraph,
        tokens: [Token],
        string: String,
        memo: inout [SPPFNode: [[ParseTree]]?]
    ) -> [[ParseTree]] {

        let children = sppf.getChildren(of: node)
        let alpha = Array(label.symbols.prefix(label.position))

        var leftChild: SPPFNode? = nil
        var rightChild: SPPFNode? = nil

        // Identify left / right children by their extents and symbol type.
        for child in children {
            let (cLeft, cRight) = childExtents(child)
            if cLeft == pivot && cRight == rightExtent {
                if let lastSymbol = alpha.last, matchSymbol(lastSymbol, node: child) {
                    rightChild = child
                }
            } else if cLeft == leftExtent && cRight == pivot {
                if alpha.count == 2 {
                    if let firstSymbol = alpha.first, matchSymbol(firstSymbol, node: child) {
                        leftChild = child
                    }
                } else if alpha.count > 2 {
                    if case .intermediate = child {
                        leftChild = child
                    }
                }
            }
        }

        // Fallback: match purely by extent when symbol-type matching was inconclusive.
        if leftChild == nil && rightChild == nil {
            for child in children {
                let (cLeft, cRight) = childExtents(child)
                if cLeft == pivot && cRight == rightExtent {
                    rightChild = child
                } else if cLeft == leftExtent && cRight == pivot {
                    leftChild = child
                }
            }
        }

        let leftAlts: [[ParseTree]]
        if let left = leftChild {
            leftAlts = extractNodeAlternatives(
                node: left, sppf: sppf, tokens: tokens, string: string, memo: &memo)
        } else {
            leftAlts = [[]]
        }

        let rightAlts: [[ParseTree]]
        if let right = rightChild {
            rightAlts = extractNodeAlternatives(
                node: right, sppf: sppf, tokens: tokens, string: string, memo: &memo)
        } else {
            rightAlts = [[]]
        }

        // Cartesian product of left × right alternatives.
        var alternatives: [[ParseTree]] = []
        for lAlt in leftAlts {
            for rAlt in rightAlts {
                alternatives.append(lAlt + rAlt)
            }
        }
        return alternatives
    }

    // MARK: - Small helpers

    func childExtents(_ node: SPPFNode) -> (Int, Int) {
        switch node {
        case let .leaf(_, l, r):         return (l, r)
        case let .symbol(_, l, r):       return (l, r)
        case let .intermediate(_, l, r): return (l, r)
        case let .packed(_, l, r, _):    return (l, r)
        }
    }

    private func matchSymbol(_ symbol: Symbol, node: SPPFNode) -> Bool {
        switch (symbol, node) {
        case (.terminal(let t),    .leaf(let label, _, _)):   return t.description == label
        case (.nonTerminal(let nt),.symbol(let label, _, _)): return nt.name == label
        case (.metaSymbol(let m),  .leaf(let label, _, _)):   return m.description == label
        default: return false
        }
    }

    func charRange(left: Int, right: Int, tokens: [Token], string: String) -> Range<String.Index> {
        if left == right {
            if left < tokens.count {
                let idx = tokens[left].range.lowerBound
                return idx..<idx
            } else {
                return string.endIndex..<string.endIndex
            }
        } else {
            let start = tokens[left].range.lowerBound
            let end   = tokens[right - 1].range.upperBound
            return start..<end
        }
    }

    func deduplicateParseTrees(_ trees: [ParseTree]) -> [ParseTree] {
        var uniqueTrees: [ParseTree] = []
        for tree in trees where !uniqueTrees.contains(tree) {
            uniqueTrees.append(tree)
        }
        return uniqueTrees
    }
}
