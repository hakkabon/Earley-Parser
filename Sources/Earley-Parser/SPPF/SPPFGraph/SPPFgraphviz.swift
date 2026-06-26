//
//  SPPFgraphviz.swift
//  Earley-Parser
//
//  Created by Ulf Akerstedt-Inoue on 2025/09/23.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import OSLog


extension SPPFGraph {
    
    /// Generate Graphviz DOT representation of the SPPF
    public var graphviz: String {
        var dot = "digraph \"SPPF\" {\n"
        dot += "    rankdir=TB;\n"
        dot += "    node [fontname=\"Arial\", fontsize=10];\n"
        dot += "    edge [fontname=\"Arial\", fontsize=8];\n\n"
        
        // Get all nodes and create unique identifiers
        let allNodes = getAllNodes().sorted()
        var nodeIds: [SPPFNode: String] = [:]
        
        // Generate unique node IDs and define nodes
        for (index, node) in allNodes.enumerated() {
            let nodeId = "n\(index)"
            nodeIds[node] = nodeId
            
            let (label, shape, color, style) = getNodeAttributes(node)
            dot += "    \(nodeId) [label=\"\(escapeGraphvizLabel(label))\", shape=\(shape), color=\"\(color)\", style=\"\(style)\"];\n"
        }
        
        dot += "\n"
        
        // Add edges
        for node in allNodes {
            guard let nodeId = nodeIds[node] else { continue }
            let children = getChildren(of: node)
            
            for child in children.sorted() {
                guard let childId = nodeIds[child] else { continue }
                dot += "    \(nodeId) -> \(childId);\n"
            }
        }
        
        dot += "}\n"
        return dot
    }
    
    /// Get visual attributes for different node types
    private func getNodeAttributes(_ node: SPPFNode) -> (label: String, shape: String, color: String, style: String) {
        switch node {
        case let .leaf(label, leftExtent, rightExtent):
            let strippedLabel = label.description.replacingOccurrences(of: "\"", with: "")
            return (
                label: "\(strippedLabel), \(leftExtent), \(rightExtent)",
                shape: "box",
                color: "lightblue",
                style: "filled,rounded"
            )
            
        case let .symbol(label, leftExtent, rightExtent):
            return (
                label: "\(label), \(leftExtent), \(rightExtent)",
                shape: "box",
                color: "lightgreen",
                style: "filled,rounded"
            )
            
        case let .intermediate(labelNode, leftExtent, rightExtent):
            let truncatedLabel = truncateLabel(labelNode.graphviz, maxLength: 20)
            return (
                label: "\(truncatedLabel), \(leftExtent), \(rightExtent)",
                shape: "box",
                color: "lightgray",
                style: "filled"
            )
            
        case let .packed(labelNode, leftExtent, rightExtent, pivot):
            let truncatedLabel = truncateLabel(labelNode.graphviz, maxLength: 20)
            return (
                label: "\(truncatedLabel), \(leftExtent), \(rightExtent), \(pivot)",
                shape: "box",
                color: "lightcoral",
                style: "filled,rounded"
            )
        }
    }
    
    /// Escape special characters for Graphviz labels
    private func escapeGraphvizLabel(_ label: String) -> String {
        return label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
    
    /// Truncate long labels for better visualization
    private func truncateLabel(_ label: String, maxLength: Int) -> String {
        if label.count <= maxLength {
            return label
        }
        return String(label.prefix(maxLength - 3)) + "..."
    }
}

// MARK: - Create Graphviz output with additional styling

extension SPPFGraph {

    /// Generate a more detailed Graphviz representation with additional styling
    public func graphviz(title: String = "SPPF", showExtents: Bool = true, clusterByExtent: Bool = false) -> String {
        var dot = "digraph \"\(title)\" {\n"
        dot += "    rankdir=TB;\n"
        dot += "    compound=true;\n"
        dot += "    node [fontname=\"Arial\", fontsize=10];\n"
        dot += "    edge [fontname=\"Arial\", fontsize=8];\n\n"
        
        let allNodes = getAllNodes().sorted()
        var nodeIds: [SPPFNode: String] = [:]
        
        // Group nodes by extent if clustering is enabled
        if clusterByExtent {
            let nodesByExtent = Dictionary(grouping: allNodes) { node -> String in
                let extents = node.leftRightExtents
                return "(\(extents.0),\(extents.1))"
            }
            
            var clusterIndex = 0
            for (extent, nodes) in nodesByExtent.sorted(by: { $0.key < $1.key }) {
                dot += "    subgraph cluster_\(clusterIndex) {\n"
                dot += "        label=\"Extent \(extent)\";\n"
                dot += "        style=\"dashed\";\n"
                dot += "        color=\"gray\";\n\n"
                
                for (index, node) in nodes.enumerated() {
                    let nodeId = "c\(clusterIndex)_n\(index)"
                    nodeIds[node] = nodeId
                    
                    let (label, shape, color, style) = getDetailedNodeAttributes(node, showExtents: showExtents)
                    dot += "        \(nodeId) [label=\"\(escapeGraphvizLabel(label))\", shape=\(shape), fillcolor=\"\(color)\", style=\"\(style)\"];\n"
                }
                
                dot += "    }\n\n"
                clusterIndex += 1
            }
        } else {
            // Standard layout without clustering
            for (index, node) in allNodes.enumerated() {
                let nodeId = "n\(index)"
                nodeIds[node] = nodeId
                
                let (label, shape, color, style) = getDetailedNodeAttributes(node, showExtents: showExtents)
                dot += "    \(nodeId) [label=\"\(escapeGraphvizLabel(label))\", shape=\(shape), fillcolor=\"\(color)\", style=\"\(style)\"];\n"
            }
        }
        
        dot += "\n    // Edges\n"
        
        // Add edges with different styles
        for node in allNodes {
            guard let nodeId = nodeIds[node] else { continue }
            let children = getChildren(of: node)
            
            for child in children.sorted() {
                guard let childId = nodeIds[child] else { continue }
                
                let edgeStyle = getEdgeStyle(from: node, to: child)
                dot += "    \(nodeId) -> \(childId) [style=\"\(edgeStyle)\"];\n"
            }
        }
        
        // Add legend
        dot += "\n    // Legend\n"
        dot += "    subgraph cluster_legend {\n"
        dot += "        label=\"Legend\";\n"
        dot += "        style=\"filled\";\n"
        dot += "        fillcolor=\"white\";\n"
        dot += "        legend_symbol [label=\"Symbol\\n(Non-terminal)\", shape=ellipse, fillcolor=\"lightgreen\", style=\"filled\"];\n"
        dot += "        legend_leaf [label=\"Leaf\\n(Terminal)\", shape=box, fillcolor=\"lightblue\", style=\"filled,rounded\"];\n"
        dot += "        legend_intermediate [label=\"Intermediate\\n(Partial)\", shape=box, fillcolor=\"lightyellow\", style=\"filled\"];\n"
        dot += "        legend_packed [label=\"Packed\\n(Production)\", shape=circle, fillcolor=\"lightcoral\", style=\"filled\"];\n"
        dot += "        legend_symbol -> legend_leaf -> legend_intermediate -> legend_packed [style=\"invis\"];\n"
        dot += "    }\n"
        
        dot += "}\n"
        return dot
    }
    
    /// Get detailed node attributes with more styling options
    private func getDetailedNodeAttributes(_ node: SPPFNode, showExtents: Bool) -> (label: String, shape: String, color: String, style: String) {
        switch node {
        case let .leaf(label, leftExtent, rightExtent):
            let displayLabel = showExtents ? "\(label)\\n(\(leftExtent),\(rightExtent))" : label
            return (
                label: displayLabel,
                shape: "box",
                color: "lightblue",
                style: "filled,rounded"
            )
            
        case let .symbol(label, leftExtent, rightExtent):
            let displayLabel = showExtents ? "\(label)\\n(\(leftExtent),\(rightExtent))" : label
            return (
                label: displayLabel,
                shape: "ellipse",
                color: "lightgreen",
                style: "filled"
            )
            
        case let .intermediate(labelNode, leftExtent, rightExtent):
            let prodLabel = formatProductionLabel(labelNode)
            let displayLabel = showExtents ? "\(prodLabel)\\n(\(leftExtent),\(rightExtent))" : prodLabel
            return (
                label: displayLabel,
                shape: "box",
                color: "lightyellow",
                style: "filled"
            )
            
        case let .packed(labelNode, leftExtent, rightExtent, pivot):
            let prodLabel = formatProductionLabel(labelNode)
            let displayLabel = showExtents ? "\(prodLabel)\\n(\(leftExtent),\(rightExtent))\\nπ=\(pivot)" : prodLabel
            return (
                label: displayLabel,
                shape: "circle",
                color: "lightcoral",
                style: "filled"
            )
        }
    }
    
    /// Format production labels for better readability
    private func formatProductionLabel(_ labelNode: NodeLabel) -> String {
        let goal = labelNode.goal.name
        let symbols = labelNode.symbols.map { $0 }
        let position = labelNode.position
        
        var rhs = ""
        for (i, symbol) in symbols.enumerated() {
            if i == position {
                rhs += "•"
            }
            rhs += "\(symbol)"
            if i < symbols.count - 1 {
                rhs += " "
            }
        }
        if position >= symbols.count {
            rhs += "•"
        }
        
        return "\(goal) → \(rhs)"
    }
    
    /// Get edge styling based on node types
    private func getEdgeStyle(from parent: SPPFNode, to child: SPPFNode) -> String {
        switch (parent, child) {
        case (.symbol, .packed):
            return "solid"
        case (.packed, _):
            return "bold"
        case (.intermediate, _):
            return "dashed"
        default:
            return "solid"
        }
    }
}

// Helper extension for GraphNode to get extents

extension SPPFNode {
    var leftRightExtents: (Int, Int) {
        switch self {
        case let .leaf(_, leftExtent, rightExtent): return (leftExtent, rightExtent)
        case let .symbol(_, leftExtent, rightExtent): return (leftExtent, rightExtent)
        case let .intermediate(_, leftExtent, rightExtent): return (leftExtent, rightExtent)
        case let .packed(_, leftExtent, rightExtent, _): return (leftExtent, rightExtent)
        }
    }
}
