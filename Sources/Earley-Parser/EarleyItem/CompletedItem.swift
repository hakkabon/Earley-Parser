//
//  CompletedItem.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2024/02/18.
//  Copyright © 2020 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

/// A parse edge
public struct CompletedItem {
    /// The production
    let production: Production
    
    /// State index at which the item was completed
    let completedIndex: Int
}

extension CompletedItem: Equatable {

    public static func == (lhs: CompletedItem, rhs: CompletedItem) -> Bool {
        return lhs.production == rhs.production && lhs.completedIndex == rhs.completedIndex
    }
}

extension CompletedItem: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(production.hashValue)
        hasher.combine(completedIndex.hashValue)
    }
}

extension CompletedItem: CustomStringConvertible {
    
    public var description: String {
        let producedString = production.rule.reduce("") { (partialResult, symbol) -> String in
            switch symbol {
            case .nonTerminal(let nonTerminal):
                return partialResult.appending(" <\(nonTerminal.name)>")
                
            case .terminal(let terminal):
                return partialResult.appending(" \(terminal.description.replacingOccurrences(of: "\n", with: "\\n"))")
                
            case .metaSymbol(let meta):
                return partialResult.appending(" \(meta)")
            }
        }
        return "<\(production.goal.name)> ::=\(producedString) (\(completedIndex))"
    }
}
