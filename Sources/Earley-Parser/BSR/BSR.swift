//
//  BSR.swift
//  Earley-Parser
//
//  Created by Ulf Akerstedt-Inoue on 2024/08/15.
//  Copyright © 2020 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import OSLog

/// Binary Subtree Representation (BSR).
/// - Derivation representation using binary subtree sets, E. Scott et al.
///
public struct BSR: Codable {
    let node: BinarySubtreeNode
    let leftExtent: Int
    let pivot: Int
    let rightExtent: Int
}

extension BSR: CustomStringConvertible{
    public var description: String {
        switch self.node {
        case let .snode(node):
            return "(\(node), \(leftExtent), \(pivot), \(rightExtent))"
        case let .pnode(node):
            return "(\(node), \(leftExtent), \(pivot), \(rightExtent))"
        }
    }
}

extension BSR: Comparable {
    public static func < (lhs: BSR, rhs: BSR) -> Bool {
        // First compare by type
        let lhsType = lhs.typeOrder
        let rhsType = rhs.typeOrder
        if lhsType != rhsType {
            return lhsType < rhsType
        }
        
        // Then by label
        let lhsLabel = lhs.label
        let rhsLabel = rhs.label
        if lhsLabel != rhsLabel {
            return lhsLabel < rhsLabel
        }
        
        // Then by extents
        if lhs.leftExtent != rhs.leftExtent {
            return lhs.leftExtent < rhs.leftExtent
        }
        return lhs.rightExtent < rhs.rightExtent
    }

    private var typeOrder: Int {
        switch self.node {
        case .snode: return 0
        case .pnode: return 1
        }
    }
    
    private var label: String {
        switch self.node {
        case let .snode(node): return node.description
        case let .pnode(node): return node.description
        }
    }
}

extension BSR: Hashable {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(node)
        hasher.combine(leftExtent)
        hasher.combine(pivot)
        hasher.combine(rightExtent)
    }
}

extension BSR: Equatable {

    public static func == (lhs: BSR, rhs: BSR) -> Bool {
        return lhs.node == rhs.node &&
        lhs.leftExtent == rhs.leftExtent &&
        lhs.pivot == rhs.pivot &&
        lhs.rightExtent == rhs.rightExtent
    }
}


public enum BinarySubtreeNode: Codable {
    case pnode(ProductionNode)
    case snode(SymbolNode)
}

extension BinarySubtreeNode: CustomStringConvertible{
    public var description: String {
        switch self {
        case let .snode(node):
            return "\(node)"
        case let .pnode(node):
            return "\(node))"
        }
    }
}

extension BinarySubtreeNode: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .snode(node):
            hasher.combine(node)
        case let .pnode(node):
            hasher.combine(node)
        }
    }
}

extension BinarySubtreeNode: Equatable {
    
    public static func == (lhs: BinarySubtreeNode, rhs: BinarySubtreeNode) -> Bool {
        switch (lhs,rhs) {
        case let (.snode(lnode), .snode(rnode)):
            return lnode == rnode
        case let (.pnode(lnode), .pnode(rnode)):
            return lnode == rnode
        case (.pnode(_), .snode(_)):
            return false
        case (.snode(_), .pnode(_)):
            return false
        }
    }
}


public struct ProductionNode: Codable {
    public let goal: NonTerminal
    public let symbols: [Symbol]
}

extension ProductionNode: CustomStringConvertible{
    public var description: String {
        return "\(goal) ::= \(symbols.map { $0.description }.joined(separator: " ") )"
    }
}

extension ProductionNode: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(goal)
        hasher.combine(symbols)
    }
}

extension ProductionNode: Equatable {
    
    public static func == (lhs: ProductionNode, rhs: ProductionNode) -> Bool {
        return lhs.goal == rhs.goal && lhs.symbols == rhs.symbols
    }
}


public struct SymbolNode: Codable {
    public let symbols: [Symbol]
}

extension SymbolNode: CustomStringConvertible{
    public var description: String {
        return "\(symbols.map { $0.description }.joined(separator: " ") )"
    }
}

extension SymbolNode: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(symbols)
    }
}

extension SymbolNode: Equatable {
    
    public static func == (lhs: SymbolNode, rhs: SymbolNode) -> Bool {
        return lhs.symbols == rhs.symbols
    }
}



extension Set<BSR> {
    
    public func log() {
        Logger.bsr.trace("Binary Subtree Representation \n")

        for entry in self.sorted() {
            Logger.bsr.trace("  \(entry)")
        }
    }
}
