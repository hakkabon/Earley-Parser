//
//  SPPFNode.swift
//  Earley-Parser
//
//  Created by Ulf Akerstedt-Inoue on 2024/07/15.
//  Copyright © 2020 hakkabon software. All rights reserved.
//

import Foundation

/// SPPF Node types following Scott & Johnstone:
public enum SPPFNode: Codable {
    /// Terminal and epsilon leaf nodes. The `label` for an epsilon leaf is the
    /// grammar's configured epsilon meta character (e.g. `"ε"` or `"λ"`, set via
    /// `Grammar.epsilon` and applied in `ExtractSPPF.makePackedNode`). It is a
    /// display-only string — the underlying production that generated the node
    /// has `rule == []`, never a stored epsilon terminal symbol.
    case leaf(label: String, leftExtent: Int, rightExtent: Int)
    /// symbol nodes: non-terminals and terminals
    case symbol(label: String, leftExtent: Int, rightExtent: Int)
    /// intermediate nodes: represent partial derivations
    case intermediate(label: NodeLabel, leftExtent: Int, rightExtent: Int)
    /// packed nodes: represent specific production applications
    case packed(label: NodeLabel, leftExtent: Int, rightExtent: Int, pivot: Int)
}

extension SPPFNode: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case let .leaf(label, leftExtent, rightExtent):
            return "Leaf(\(label), \(leftExtent), \(rightExtent))"
        case let .symbol(label, leftExtent, rightExtent):
            return "Symbol(\(label), \(leftExtent), \(rightExtent))"
        case let .intermediate(label: label, leftExtent, rightExtent):
            return "Intermediate(\(label), \(leftExtent), \(rightExtent))"
        case let .packed(label: label, leftExtent, rightExtent, pivot):
            return "Packed(\(label), \(leftExtent), \(rightExtent), \(pivot))"
        }
    }
}

extension SPPFNode: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .leaf(label, leftExtent, rightExtent):
            hasher.combine(label)
            hasher.combine(leftExtent)
            hasher.combine(rightExtent)
        case let .symbol(label, leftExtent, rightExtent):
            hasher.combine(label)
            hasher.combine(leftExtent)
            hasher.combine(rightExtent)
        case let .intermediate(label: label, leftExtent, rightExtent):
            hasher.combine(label)
            hasher.combine(leftExtent)
            hasher.combine(rightExtent)
        case let .packed(label: label, leftExtent, rightExtent, pivot):
            hasher.combine(label)
            hasher.combine(leftExtent)
            hasher.combine(rightExtent)
            hasher.combine(pivot)
        }
    }
}

extension SPPFNode: Equatable {
    
    public static func == (lhs: SPPFNode, rhs: SPPFNode) -> Bool {
        switch (lhs,rhs) {
        case (.leaf(_,_,_), .symbol(_,_,_)): return false
        case (.leaf(_,_,_), .intermediate(_,_,_)): return false
        case (.leaf(_,_,_), .packed(_,_,_,_)): return false
        case (.symbol(_,_,_), .leaf(_,_,_)): return false
        case (.symbol(_,_,_), .intermediate(_,_,_)): return false
        case (.symbol(_,_,_), .packed(_,_,_,_)): return false
        case (.intermediate(_,_,_), .leaf(_,_,_)): return false
        case (.intermediate(_,_,_), .symbol(_,_,_)): return false
        case (.intermediate(_,_,_), .packed(_,_,_,_)): return false
        case (.packed(_,_,_,_), .leaf(_,_,_)): return false
        case (.packed(_,_,_,_), .symbol(_,_,_)): return false
        case (.packed(_,_,_,_), .intermediate(_,_,_)): return false

        case let (.leaf(lhsLabel, lhsLeftExtent, lhsRightExtent), .leaf(rhsLabel, rhsLeftExtent, rhsRightExtent)):
            return lhsLabel == rhsLabel && lhsLeftExtent == rhsLeftExtent && lhsRightExtent == rhsRightExtent
        case let (.symbol(lhsLabel, lhsLeftExtent, lhsRightExtent), .symbol(rhsLabel, rhsLeftExtent, rhsRightExtent)):
            return lhsLabel == rhsLabel && lhsLeftExtent == rhsLeftExtent && lhsRightExtent == rhsRightExtent
        case let (.intermediate(lhsLabel, lhsLeftExtent, lhsRightExtent), .intermediate(rhsLabel, rhsLeftExtent, rhsRightExtent)):
            return lhsLabel == rhsLabel && lhsLeftExtent == rhsLeftExtent && lhsRightExtent == rhsRightExtent
        case let (.packed(lhsLabel, lhsLeftExtent, lhsRightExtent, lhsPivot), .packed(rhsLabel, rhsLeftExtent, rhsRightExtent, rhsPivot)):
            return lhsLabel == rhsLabel && lhsLeftExtent == rhsLeftExtent && lhsRightExtent == rhsRightExtent && lhsPivot == rhsPivot
        }
    }
}

extension SPPFNode: Comparable {
    
    public static func < (lhs: SPPFNode, rhs: SPPFNode) -> Bool {
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
        let lhsExtents = lhs.extents
        let rhsExtents = rhs.extents
        
        if lhsExtents.0 != rhsExtents.0 {
            return lhsExtents.0 < rhsExtents.0
        }
        
        return lhsExtents.1 < rhsExtents.1
    }
    
    private var typeOrder: Int {
        switch self {
        case .leaf: return 0
        case .symbol: return 1
        case .intermediate: return 2
        case .packed: return 3
        }
    }
    
    private var label: String {
        switch self {
        case let .leaf(label, _, _): return label
        case let .symbol(label, _, _): return label
        case let .intermediate(label, _, _): return label.description
        case let .packed(label, _, _, _): return label.description
        }
    }
    
    private var extents: (Int, Int) {
        switch self {
        case let .leaf(_, leftExtent, rightExtent): return (leftExtent, rightExtent)
        case let .symbol(_, leftExtent, rightExtent): return (leftExtent, rightExtent)
        case let .intermediate(_, leftExtent, rightExtent): return (leftExtent, rightExtent)
        case let .packed(_, leftExtent, rightExtent, _): return (leftExtent, rightExtent)
        }
    }
}
