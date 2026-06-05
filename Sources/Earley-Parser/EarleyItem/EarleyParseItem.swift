//
//  EarleyParseItem.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2024/07/15.
//  Copyright © 2020 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

/// Represents a partial parse of a production
public struct EarleyParseItem {
    /// The partially parsed production
    let production: Production
    
    /// The index of the next symbol to be parsed
    let productionPosition: Int
    
    /// The index of the first token parsed in this partial parse
    let startTokenIndex: Int
}

extension EarleyParseItem {
    
    var isCompleted: Bool {
        return !production.rule.indices.contains(productionPosition)
    }
    
    func advanced() -> EarleyParseItem {
        guard !isCompleted else {
            return self
        }
        return EarleyParseItem(
            production: production,
            productionPosition: productionPosition + 1,
            startTokenIndex: startTokenIndex
        )
    }
    
    var nextSymbol: Symbol? {
        guard production.rule.indices.contains(productionPosition) else {
            return nil
        }
        return production.rule[productionPosition]
    }
}

extension EarleyParseItem: Equatable {
    
    public static func == (lhs: EarleyParseItem, rhs: EarleyParseItem) -> Bool {
        return lhs.production == rhs.production
        && lhs.productionPosition == rhs.productionPosition
        && lhs.startTokenIndex == rhs.startTokenIndex
    }
}

extension EarleyParseItem: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(production.hashValue)
        hasher.combine(productionPosition.hashValue)
        hasher.combine(startTokenIndex.hashValue)
    }
}

extension EarleyParseItem: CustomStringConvertible {
    
    public var description: String {
        let producedString = production.rule.map { symbol -> String in
            switch symbol {
            case .nonTerminal(let nonTerminal):
                return "<\(nonTerminal.name)>"
            case .metaSymbol(let meta):
                return "\(meta)"
            case .terminal(let terminal):
                return "\(terminal.description.replacingOccurrences(of: "\n", with: "\\n"))"
            }
        }.enumerated().reduce("") { (partialResult, string) in
            if string.offset == productionPosition {
                return partialResult.appending(" • \(string.element)")
            }
            return partialResult.appending(" \(string.element)")
        }
        if isCompleted {
            return "<\(production.goal)> ::=\(producedString) • (\(startTokenIndex))"
        } else {
            return "<\(production.goal)> ::=\(producedString) (\(startTokenIndex))"
        }
    }
}
