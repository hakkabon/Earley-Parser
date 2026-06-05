//
//  SPPFAnalyze.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2025/09/23.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import OSLog

// MARK: - Additional Debugging Methods

extension SPPFGraph {
    
    public func log() {
        Logger.sppf.trace("SPPF Graph Debug")
        let allNodes = getAllNodes().sorted()
        
        for node in allNodes {
            Logger.sppf.trace("\(node)")
            let children = getChildren(of: node)
            if children.isEmpty {
                Logger.sppf.trace("  No children (leaf)")
            } else {
                for child in children.sorted() {
                    Logger.sppf.trace("    -> \(child)")
                }
            }
        }
        
        // Analyze potential issues
        Logger.sppf.trace("Potential Issues")
        
        // Check for nodes with excessive children
        for node in allNodes {
            let childCount = getChildren(of: node).count
            if childCount > 5 {
                Logger.sppf.trace("⚠️  Node \(node) has \(childCount) children (potential explosion)")
            }
        }
        
        // Check for cycles (simplified)
        var visited: Set<GraphNode> = []
        var inPath: Set<GraphNode> = []
        
        func hasCycle(_ node: GraphNode) -> Bool {
            if inPath.contains(node) {
                Logger.sppf.trace("⚠️  Cycle detected at node: \(node)")
                return true
            }
            if visited.contains(node) {
                return false
            }
            
            visited.insert(node)
            inPath.insert(node)
            
            for child in getChildren(of: node) {
                if hasCycle(child) {
                    return true
                }
            }
            
            inPath.remove(node)
            return false
        }
        
        for rootNode in allNodes {
            if case .symbol = rootNode {
                _ = hasCycle(rootNode)
            }
        }
    }
}
