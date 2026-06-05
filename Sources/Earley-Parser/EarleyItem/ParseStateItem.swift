//
//  ParseStateItem.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2024/02/18.
//  Copyright © 2020 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

/// Represents a partial parse of a production
struct ParseStateItem {
    /// The partially parsed production
    let production: Production
    
    /// The index of the next symbol to be parsed
    let productionPosition: Int
    
    /// The index of the first token parsed in this partial parse
    let startTokenIndex: Int
}

extension ParseStateItem {

    // Note: The epsilon-terminal check is redundant and confusing.
    // isCompleted should only check if the dot is past the end of the rule.
    // The empty-terminal trick for nullable handling is a Grammar-layer concern,
    // not a completion check.
    var isCompleted: Bool {
//        return !production.rule.indices.contains(productionPosition)
        if !production.rule.indices.contains(productionPosition) {
            return true
        }
        if case let .terminal(t) = production.rule.last, t.isEmpty {
            return true
        }
        return false
    }
    
    func advanced() -> ParseStateItem {
        guard !isCompleted else {
            return self
        }
        return ParseStateItem(
            production: production,
            productionPosition: productionPosition + 1,
            startTokenIndex: startTokenIndex
        )
    }
    
    var nextSymbol: Symbol? {
        guard production.rule.indices.contains(productionPosition) else {
            return nil
        }
//        return production.rule[productionPosition]
        if case let .terminal(t) = production.rule[productionPosition], t.isEmpty {
            return nil
        }
        return production.rule[productionPosition]
    }
    
    var split: (alpha: [Symbol], beta: [Symbol], dotPosition: Int) {
        let alpha: [Symbol] = Array(production.rule.prefix(productionPosition))
        let beta = Array(production.rule.dropFirst(productionPosition))
        return (alpha, beta, dotPosition: productionPosition)
    }
    
    func isNullable(_ symbols: [Symbol]) -> Bool {
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
}

extension ParseStateItem: Equatable {
    
    static func == (lhs: ParseStateItem, rhs: ParseStateItem) -> Bool {
        return lhs.production == rhs.production
        && lhs.productionPosition == rhs.productionPosition
        && lhs.startTokenIndex == rhs.startTokenIndex
    }
}

extension ParseStateItem: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(production)
        hasher.combine(productionPosition)
        hasher.combine(startTokenIndex)
    }
}

extension ParseStateItem: CustomStringConvertible {
    
    var description: String {
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
