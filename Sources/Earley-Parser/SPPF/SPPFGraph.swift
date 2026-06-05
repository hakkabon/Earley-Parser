//
//  ExtractSPPF.swift
//  grammar
//
//  Created by Ulf Akerstedt-Inoue on 2025/08/23.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import OSLog

public class SPPFGraph {
    private var graph: [GraphNode: Set<GraphNode>] = [:]
    
    /// Add a node to the graph.
    /// - parameter node: The node to be added.
    func add(_ node: GraphNode) {
        guard graph.index(forKey: node) == nil else { return }
        graph[node] = []
    }
    
    func addEdge(from parent: GraphNode, to child: GraphNode) {
        graph[parent, default: []].insert(child)
        add(child)
    }
    
    func getChildren(of node: GraphNode) -> Set<GraphNode> {
        return graph[node] ?? Set()
    }
    
    func getAllNodes() -> [GraphNode] {
        return Array(graph.keys)
    }

    // Get nodes that can be expanded (non-terminals and intermediates not yet processed)
    func getExtendableNodes() -> [GraphNode] {
        graph.keys.filter { node in
            switch node {
            case .leaf(_,_,_):
                return false
            case .symbol(_,_,_):
                return getChildren(of: node).isEmpty
            case .intermediate(_,_,_):
                return getChildren(of: node).isEmpty
            case .packed(_,_,_,_):
                return false
            }
        }
    }
    
    public func printGraph() {
        Logger.sppf.trace("SPPF Graph: \n")

        let nodes = graph.keys.sorted()
        for node in nodes {
            Logger.sppf.trace("  \(node)")
            let chidren = graph[node]!
            for child in chidren {
                Logger.sppf.trace("    -> \(child)")
            }
        }
    }
    
    func cleanup() {
        var productive = Set<GraphNode>()
        
        for node in graph.keys {
            if case .leaf = node {
                productive.insert(node)
            }
        }
        
        var changed = true
        while changed {
            changed = false
            for (node, children) in graph {
                if productive.contains(node) { continue }
                
                switch node {
                case .leaf:
                    break
                case .symbol, .intermediate:
                    let hasProductiveChild = children.contains { productive.contains($0) }
                    if hasProductiveChild {
                        productive.insert(node)
                        changed = true
                    }
                case .packed:
                    let allChildrenProductive = children.allSatisfy { productive.contains($0) }
                    if allChildrenProductive {
                        productive.insert(node)
                        changed = true
                    }
                }
            }
        }
        
        var newGraph: [GraphNode: Set<GraphNode>] = [:]
        for (node, children) in graph {
            if productive.contains(node) {
                let productiveChildren = children.filter { productive.contains($0) }
                newGraph[node] = productiveChildren
            }
        }
        self.graph = newGraph
    }
}

