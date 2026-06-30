//
//  ParseTreeExtraction.swift
//  Earley-Parser
//
//  Created by Ulf Akerstedt-Inoue on 2025/08/23.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import OSLog

extension EarleyParser {

    public func extractParseTreesFromGraph(_ graph: SPPFGraph, extent: (left: Int, right: Int)) -> [EarleyParseTree] {

        // Find root nodes (start symbol nodes spanning full input)
        let rootNodes = graph.getAllNodes().filter { node in
            switch node {
            case let .symbol(label, leftExtent, rightExtent):
                // Check if this is actually a completed parse
                return grammar.start.name == label && leftExtent == extent.left && rightExtent == extent.right
            default:
                return false
            }
        }
        
        var allTrees: [EarleyParseTree] = []
        var processedRoots: Set<String> = []
        
        for rootNode in rootNodes {
            let rootKey = "\(rootNode)"
            if processedRoots.contains(rootKey) { continue }
            processedRoots.insert(rootKey)
            
            var visited = Set<SPPFNode>()
            let trees = extractTreesFromNode(rootNode, in: graph, visited: &visited)
            allTrees.append(contentsOf: trees)
        }
        
        // Deduplicate equivalent trees
        return deduplicateTrees(allTrees)
    }

    private func extractTreesFromNode(_ node: SPPFNode, in graph: SPPFGraph, visited: inout Set<SPPFNode>) -> [EarleyParseTree] {
        if visited.contains(node) {
            return [EarleyParseTree(symbol: "<CYCLE>")]
        }
        
        visited.insert(node)
        defer { visited.remove(node) } // Remove after processing to allow different paths
        
        switch node {
        case let .leaf(label, _, _):
            return [EarleyParseTree(symbol: label)]
            
        case let .symbol(label, _, _):
            let children = graph.getChildren(of: node)
            
            if children.isEmpty {
                // Terminal symbol or empty non-terminal
                return [EarleyParseTree(symbol: label)]
            }
            
            // For symbol nodes, each packed child represents an alternative derivation
            var alternativeTrees: [EarleyParseTree] = []
            
            for child in children {
                if case .packed = child {
                    let packedTrees = extractTreesFromPackedNode(child, in: graph, visited: &visited)
                    for tree in packedTrees {
                        // Create parse tree with symbol as root and packed tree's structure
                        let parseTree = EarleyParseTree(
                            symbol: label,
                            children: tree.children, // Use the children from packed node
                            production: tree.production
                        )
                        alternativeTrees.append(parseTree)
                    }
                }
            }
            
            return alternativeTrees.isEmpty ? [EarleyParseTree(symbol: label)] : alternativeTrees
            
        case let .intermediate(label, _, _):
            // Intermediate nodes should be treated like symbols
            let children = graph.getChildren(of: node)
            if children.isEmpty {
                return [EarleyParseTree(symbol: label.goal.name)]
            }
            
            var alternativeTrees: [EarleyParseTree] = []
            for child in children {
                let childTrees = extractTreesFromNode(child, in: graph, visited: &visited)
                alternativeTrees.append(contentsOf: childTrees)
            }
            return alternativeTrees
            
        case .packed(_, _, _, _):
            return extractTreesFromPackedNode(node, in: graph, visited: &visited)
        }
    }
    
    private func extractTreesFromPackedNode(_ node: SPPFNode, in graph: SPPFGraph, visited: inout Set<SPPFNode>) -> [EarleyParseTree] {
        guard case let .packed(label, _, _, _) = node else {
            return []
        }
        
        // Extract production information from label
        let production = Production(goal: label.goal, rule: label.symbols) // Simplified
        
        let children = graph.getChildren(of: node).sorted()
        
        if children.isEmpty {
            // Empty production (epsilon): production.rule == [] after Grammar normalization.
            // No children to recurse into; emit a leaf node for the goal symbol.
            return [EarleyParseTree(symbol: production.goal.name, production: production)]
        }
        
        // Get trees for each child
        var childTreeLists: [[EarleyParseTree]] = []
        for child in children {
            let childTrees = extractTreesFromNode(child, in: graph, visited: &visited)
            childTreeLists.append(childTrees)
        }
        
        // Generate cartesian product of child combinations
        let combinations = cartesianProduct(of: childTreeLists)
        
        return combinations.map { childCombination in
            EarleyParseTree(
                symbol: production.goal.name,
                children: childCombination,
                production: production
            )
        }
    }
    
    // Helper function to generate cartesian product
    private func cartesianProduct(of arrays: [[EarleyParseTree]]) -> [[EarleyParseTree]] {
        guard !arrays.isEmpty else { return [[]] }
        
        var result: [[EarleyParseTree]] = [[]]
        
        for array in arrays {
            var newResult: [[EarleyParseTree]] = []
            for combination in result {
                for element in array {
                    var newCombination = combination
                    newCombination.append(element)
                    newResult.append(newCombination)
                }
            }
            result = newResult
        }
        
        return result
    }
    
    // Deduplicate equivalent parse trees
    private func deduplicateTrees(_ trees: [EarleyParseTree]) -> [EarleyParseTree] {
        var uniqueTrees: [EarleyParseTree] = []
        var seenStructures: Set<String> = []
        
        for tree in trees {
            let structure = treeStructureString(tree)
            if !seenStructures.contains(structure) {
                seenStructures.insert(structure)
                uniqueTrees.append(tree)
            }
        }
        
        return uniqueTrees
    }
    
    private func treeStructureString(_ tree: EarleyParseTree) -> String {
        if tree.children.isEmpty {
            return tree.symbol
        } else {
            let childStructures = tree.children.map { treeStructureString($0) }
            return "\(tree.symbol)(\(childStructures.joined(separator: ",")))"
        }
    }
}

// MARK: - Parse Tree Representation

public struct EarleyParseTree {
    public let symbol: String
    public let children: [EarleyParseTree]
    public let production: Production?
    
    public init(symbol: String, children: [EarleyParseTree] = [], production: Production? = nil) {
        self.symbol = symbol
        self.children = children
        self.production = production
    }
}

extension EarleyParseTree: CustomStringConvertible {
    public var description: String {
        if children.isEmpty {
            return symbol
        } else {
            let childrenStr = children.map { $0.description }.joined(separator: ", ")
            return "\(symbol)(\(childrenStr))"
        }
    }
}

// MARK: - Tree graph in graphviz format

extension EarleyParseTree {
    
    var graphviz: String {
        var result = ""
        var nodeCounter = 0
        
        func addNode(_ tree: EarleyParseTree, parentId: String? = nil) -> String {
            let nodeId = "node\(nodeCounter)"
            nodeCounter += 1
            
            let label = tree.symbol
            result += "  \(nodeId) [label=\"\(label)\"];\n"
            
            if let parentId = parentId {
                result += "  \(parentId) -- \(nodeId);\n"
            }
            
            for child in tree.children {
                _ = addNode(child, parentId: nodeId)
            }
            
            return nodeId
        }
        
        result += "graph ParseTree {\n"
        _ = addNode(self)
        result += "}\n"
        return result
    }
}

// MARK: - Tree outline for pretty printing

extension EarleyParseTree {
    
    public func printTree() {
        print(treeLines().joined(separator:"\n"))
    }

    func treeLines(_ nodeIndent: String = "", _ childIndent: String = "") -> [String] {
        let root: [String] = [ nodeIndent + symbol ]
        let tree: [String] = children.enumerated().map{ ($0 < children.count-1, $1) }
                .flatMap{ $0 ? $1.treeLines("┣╸","┃ ") : $1.treeLines("┗╸","  ") }
                .map{ childIndent + $0 }
        return root + tree
    }
}
