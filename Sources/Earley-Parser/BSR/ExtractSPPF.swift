//
//  ExtractSPPF.swift
//  Earley-Parser
//
//  Created by Ulf Akerstedt-Inoue on 2025/08/23.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Tokenizer
import OSLog

///  Revised to correctly implement the SPPF extraction algorithm from:
///  E. Scott, A. Johnstone, L. van Binsbergen, "Derivation representation using binary subtree sets",
///  Science of Computer Programming 175 (2019) 63–84, §3.2.
///
/// The BSR tuple encodes a derivation step for item `X ::= α·β` spanning `(leftExtent, rightExtent)`
/// with pivot `pivot` (the boundary between α and the last symbol of α).
///
/// Rules (from Scott et al. §3.1):
///   - If β = ε  (item is complete):  add pnode (X ::= αβ, i, k, j)
///   - If |α| > 1 (intermediate):     add snode (α, i, k, j)
///   - If |α| = 1 (single-symbol α):  add pnode (X ::= αβ, i, k, j)
///   - If |α| = 0 (dot at start):     nothing to record

extension EarleyParser {

    /// Build an SPPF graph from the BSR set ϒ.
    ///
    /// Algorithm (Scott et al. §3.2):
    ///   1. Create root node (S, 0, n).
    ///   2. While G has an extendable leaf node w = (μ, i, j):
    ///      - If μ is a non-terminal X: expand using all (X ::= γ, i, k, j) ∈ ϒ.
    ///      - If μ is an intermediate label X ::= α·δ: expand using BSR snodes for α.
    func extractSPPF(tokens: [Token], bsr: Set<BSR>) -> SPPFGraph {
        let graph = SPPFGraph()
        let startSymbol = grammar.start.name
        let n = tokens.count

        // Look for completed start productions spanning the full input.
        let startBSRs = bsr.filter { entry in
            if case let .pnode(node) = entry.node {
                return node.goal.name == startSymbol
                    && entry.leftExtent == 0
                    && entry.rightExtent == n
            }
            return false
        }

        guard !startBSRs.isEmpty else {
            Logger.sppf.trace("extractSPPF: no completed start BSR entries found")
            return graph
        }

        // Create the root symbol node (S, 0, n).
        let rootNode = SPPFNode.symbol(label: startSymbol, leftExtent: 0, rightExtent: n)
        graph.add(rootNode)
        Logger.sppf.trace("root node: (\(startSymbol), 0, \(n))")

        // Iteratively expand extendable nodes until none remain.
        // An extendable node is a symbol or intermediate node with no children yet.
        var iterations = 0
        let maxIterations = bsr.count * 4 + 10  // safety bound
        var expandedNodes = Set<SPPFNode>()

        while iterations < maxIterations {
            let extendableNodes = graph.getExtendableNodes().filter { !expandedNodes.contains($0) }
            if extendableNodes.isEmpty {
                break
            }
            iterations += 1

            for node in extendableNodes {
                expandedNodes.insert(node)
                switch node {
                case .leaf:
                    break  // leaves are never extendable
                case .symbol(let label, let leftExtent, let rightExtent):
                    Logger.sppf.trace("> expanding symbol node: \(node)")
                    expandSymbolNode(label: label, leftExtent: leftExtent, rightExtent: rightExtent,
                                     node: node, in: graph, bsr: bsr)
                case .intermediate(let label, let leftExtent, let rightExtent):
                    Logger.sppf.trace("> expanding intermediate node: \(node)")
                    expandIntermediateNode(label: label, leftExtent: leftExtent, rightExtent: rightExtent,
                                          node: node, in: graph, bsr: bsr)
                case .packed:
                    break  // packed nodes are never extendable
                }
            }
        }

        if iterations >= maxIterations {
            Logger.sppf.trace("extractSPPF: reached iteration limit — possible cycle in BSR")
        }

        graph.cleanup()
        return graph
    }

    // MARK: - Expand a symbol node (μ = non-terminal X)

    /// Expand a symbol node (X, i, j) by finding all completed BSR pnodes for X spanning (i, j).
    ///
    /// For each (X ::= γ, i, k, j) ∈ ϒ, call mkPN(X ::= γ·, i, k, j, G).
    private func expandSymbolNode(label: String, leftExtent: Int, rightExtent: Int,
                                   node: SPPFNode, in graph: SPPFGraph,
                                   bsr: Set<BSR>) {
        // Find all (X ::= γ, i, k, j) ∈ ϒ — must match label AND extents.
        let relevantEntries = bsr.filter { entry in
            guard case let .pnode(pn) = entry.node else { return false }
            return pn.goal.name == label
                && entry.leftExtent == leftExtent
                && entry.rightExtent == rightExtent
        }

        for entry in relevantEntries {
            guard case let .pnode(prodNode) = entry.node else { continue }
            makePackedNode(
                label: NodeLabel(goal: prodNode.goal, symbols: prodNode.symbols, position: prodNode.symbols.count),
                leftExtent: entry.leftExtent,   // i
                pivot: entry.pivot,             // k
                rightExtent: entry.rightExtent, // j
                parent: node,
                in: graph,
                bsr: bsr
            )
        }
    }

    // MARK: - Expand an intermediate node (μ = X ::= α·δ)

    /// Expand an intermediate node (X ::= α·δ, i, j).
    ///
    /// Per Scott et al.:
    ///   - If |α| = 1: call mkPN(X ::= α·δ, i, i, j, G)  [pivot = leftExtent]
    ///   - If |α| > 1: for each (α, i, k, j) ∈ ϒ, call mkPN(X ::= α·δ, i, k, j, G)
    private func expandIntermediateNode(label: NodeLabel, leftExtent: Int, rightExtent: Int,
                                         node: SPPFNode, in graph: SPPFGraph,
                                         bsr: Set<BSR>) {
        let alpha = Array(label.symbols.prefix(label.position))

        if alpha.count == 1 {
            // Single symbol before the dot: pivot = leftExtent (the symbol spans i..j directly).
            makePackedNode(
                label: label,
                leftExtent: leftExtent,     // i
                pivot: leftExtent,          // i  (single symbol, no split needed)
                rightExtent: rightExtent,   // j
                parent: node,
                in: graph,
                bsr: bsr
            )
        } else {
            // Multiple symbols before the dot: look up the pivot from BSR snodes.
            // Find all (α, i, k, j) ∈ ϒ — must match alpha AND extents.
            let relevantEntries = bsr.filter { entry in
                guard case let .snode(sn) = entry.node else { return false }
                return sn.symbols == alpha
                    && entry.leftExtent == leftExtent
                    && entry.rightExtent == rightExtent
            }

            for entry in relevantEntries {
                makePackedNode(
                    label: label,
                    leftExtent: entry.leftExtent,   // i
                    pivot: entry.pivot,             // k  (from BSR snode)
                    rightExtent: entry.rightExtent, // j
                    parent: node,
                    in: graph,
                    bsr: bsr
                )
            }
        }
    }

    // MARK: - Make a packed node

    /// Create a packed node for (X ::= α·δ, i, k, j) and attach it to `parent`.
    ///
    /// The packed node encodes the split: left child covers (i, k), right child covers (k, j).
    ///
    /// Structure (Scott et al. §3.2, mkPN):
    ///   - Create packed node p = (X ::= α·δ, k).
    ///   - Connect parent → p.
    ///   - Right child: the last symbol of α, spanning (k, j).
    ///   - Left child (if |α| ≥ 2):
    ///       - If |α| = 2: symbol/leaf node for α[0], spanning (i, k).
    ///       - If |α| > 2: intermediate node (X ::= β·xδ, i, k), where α = βx.
    ///   - If α = ε: epsilon leaf node.
    private func makePackedNode(label: NodeLabel, leftExtent: Int, pivot: Int, rightExtent: Int,
                                 parent: SPPFNode, in graph: SPPFGraph,
                                 bsr: Set<BSR>) {
        let packedNode = SPPFNode.packed(label: label, leftExtent: leftExtent, rightExtent: rightExtent, pivot: pivot)

        // Connect parent → packed node (idempotent — addEdge checks for duplicates).
        graph.addEdge(from: parent, to: packedNode)
        Logger.sppf.trace("    \(parent) -> \(packedNode)")

        let alpha = Array(label.symbols.prefix(label.position))

        // α = ε: epsilon production — attach a single epsilon leaf.
        if alpha.isEmpty {
            let epsNode = SPPFNode.leaf(label: MetaTerminal.eps.rawValue,
                                         leftExtent: leftExtent, rightExtent: rightExtent)
            graph.addEdge(from: packedNode, to: epsNode)
            Logger.sppf.trace("    \(packedNode) -> \(epsNode) [ε]")
            return
        }

        // Right child: last symbol of α, spanning (pivot, rightExtent).
        // (This is the symbol that was most recently recognised.)
        let rightChild = createNodeForSymbol(alpha.last!, leftExtent: pivot, rightExtent: rightExtent)
        graph.addEdge(from: packedNode, to: rightChild)
        Logger.sppf.trace("    \(packedNode) -> \(rightChild) [right]")

        // Left child: everything before the last symbol of α, spanning (leftExtent, pivot).
        if alpha.count == 1 {
            // Only one symbol in α — no left child needed; the right child IS the only child.
            // (Nothing to add.)
        } else if alpha.count == 2 {
            // Exactly two symbols: left child is a simple symbol/leaf node for α[0].
            let leftChild = createNodeForSymbol(alpha.first!, leftExtent: leftExtent, rightExtent: pivot)
            graph.addEdge(from: packedNode, to: leftChild)
            Logger.sppf.trace("    \(packedNode) -> \(leftChild) [left, |α|=2]")
        } else {
            // More than two symbols: left child is an intermediate node (X ::= β·xδ, i, k)
            // where α = βx (β = alpha[0..<count-1], x = alpha.last).
            let intermediateLabel = NodeLabel(
                goal: label.goal,
                symbols: label.symbols,
                position: label.position - 1   // dot moves one step left: α·δ → β·xδ
            )
            let leftChild = SPPFNode.intermediate(
                label: intermediateLabel,
                leftExtent: leftExtent,
                rightExtent: pivot
            )
            graph.addEdge(from: packedNode, to: leftChild)
            Logger.sppf.trace("    \(packedNode) -> \(leftChild) [left, intermediate]")
        }
    }

    // MARK: - Helper

    private func createNodeForSymbol(_ symbol: Symbol, leftExtent: Int, rightExtent: Int) -> SPPFNode {
        switch symbol {
        case .terminal(let t):
            return SPPFNode.leaf(label: t.description, leftExtent: leftExtent, rightExtent: rightExtent)
        case .nonTerminal(let nt):
            return SPPFNode.symbol(label: nt.name, leftExtent: leftExtent, rightExtent: rightExtent)
        case .metaSymbol(let meta):
            return SPPFNode.leaf(label: meta.description, leftExtent: leftExtent, rightExtent: rightExtent)
        }
    }
}
