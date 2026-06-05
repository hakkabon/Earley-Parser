//
//  GrammarLogger.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2025/09/21.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import OSLog

extension Logger {
    /// Using your bundle identifier is a great way to ensure a unique identifier.
    private static let subsystem = "com.grammar.hakkabon"

    /// Logs all processing related to the parsing domain.
    static let ll = Logger(subsystem: subsystem, category: "LL(1)")

    /// Logs all processing related to the Earley parsing domain.
    static let earley = Logger(subsystem: subsystem, category: "Earley")

    /// Logs all processing related to the Binary Subtree Representation (BSR) domain.
    static let bsr = Logger(subsystem: subsystem, category: "BSR")

    /// Logs all processing related to the Shared Packed Parse Forest (SPPF) domain.
    static let sppf = Logger(subsystem: subsystem, category: "SPPF")
}
