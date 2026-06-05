//
//  NodeLabel.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2025/09/22.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

public struct NodeLabel: Codable {
    public let goal: NonTerminal
    public let symbols: [Symbol]
    public let position: Int
        
    var isCompleted: Bool {
        return !symbols.indices.contains(position)
    }

    var  isNullable: Bool {
        return symbols.allSatisfy { symbol in
            switch symbol {
            case .terminal(let t):
                return t.isEmpty
            case .nonTerminal(_):
                return false
            case .metaSymbol(_):
                return false
            }
        }
    }
    
    var split: (alpha: [Symbol], delta: [Symbol], dotPosition: Int) {
        let production = symbols
        let alpha = Array(production.prefix(position))
        let delta = Array(production.dropFirst(position))
        return (alpha, delta, dotPosition: position)
    }
}

extension NodeLabel: CustomStringConvertible {
    
    public var description: String {
        let label = symbols.map { symbol -> String in
            switch symbol {
            case .nonTerminal(let nonTerminal):
                return "\(nonTerminal.name)"
            case .metaSymbol(let meta):
                return "\(meta)"
            case .terminal(let terminal):
                return "\(terminal.description.replacingOccurrences(of: "\n", with: "\\n"))"
            }
        }.enumerated().reduce("") { (partialResult, string) in
            if string.offset == position {
                return partialResult.appending(" • \(string.element)")
            }
            return partialResult.appending(" \(string.element)")
        }
        return "\(goal) ::= \(label)"
    }
}

extension NodeLabel: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(goal)
        hasher.combine(symbols)
        hasher.combine(position)
    }
}

extension NodeLabel: Equatable {
    
    public static func == (lhs: NodeLabel, rhs: NodeLabel) -> Bool {
        return lhs.goal == rhs.goal && lhs.symbols == rhs.symbols && lhs.position == rhs.position
    }
}

extension NodeLabel {
    
    public var graphviz: String {
        let label = symbols.map { symbol -> String in
            switch symbol {
            case .nonTerminal(let nonTerminal):
                return "\(nonTerminal.name)"
            case .metaSymbol(let meta):
                return "\(meta)"
            case .terminal(let terminal):
                let stripped = terminal.description.replacingOccurrences(of: "\"", with: "")
                return "\(stripped.replacingOccurrences(of: "\n", with: "\\n"))"
            }
        }.enumerated().reduce("") { (partialResult, string) in
//            if string.offset == position {
//                return partialResult.appending(" • \(string.element)")
//            }
            return partialResult.appending(" \(string.element)")
        }
        return "\(goal) ::= \(label)"
    }
}
