//
//  ParseStateItem.swift
//  Earley-Parser
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

    /// Returns `true` when the dot has advanced past the last symbol in the rule,
    /// i.e. `productionPosition == production.rule.count`.
    ///
    /// With Grammar's epsilon normalization, an epsilon production is always
    /// stored as `rule == []`, so `productionPosition == 0` immediately makes
    /// `!production.rule.indices.contains(0)` true — no extra epsilon-terminal
    /// branch is needed here.
    var isCompleted: Bool {
        return !production.rule.indices.contains(productionPosition)
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
    
    /// The symbol immediately to the right of the dot, or `nil` when the item
    /// is completed.
    ///
    /// Because `Production.init` normalizes any epsilon symbol away at creation
    /// (see hakkabon/Grammar's Production.swift), a `rule` can never contain a
    /// bare `.terminal(.meta(.eps))` or `.terminal(.string(""))` at runtime.
    /// The earlier pattern-match that tested for an empty terminal and returned
    /// `nil` prematurely is therefore gone: the only way `nextSymbol` is `nil`
    /// is when `isCompleted` is true, i.e. the dot is past the end of the rule.
    var nextSymbol: Symbol? {
        guard production.rule.indices.contains(productionPosition) else {
            return nil
        }
        return production.rule[productionPosition]
    }
    
    var split: (alpha: [Symbol], beta: [Symbol], dotPosition: Int) {
        let alpha: [Symbol] = Array(production.rule.prefix(productionPosition))
        let beta = Array(production.rule.dropFirst(productionPosition))
        return (alpha, beta, dotPosition: productionPosition)
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
