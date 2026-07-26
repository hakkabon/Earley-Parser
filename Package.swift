// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Earley-Parser",
    platforms: [.macOS(.v11), .iOS(.v14)],
    products: [
        .library(name: "Earley-Parser", targets: ["Earley-Parser"]),
        .executable(name: "earley-gtool", targets: ["earley-gtool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2"),
        .package(url: "https://github.com/JohnSundell/ShellOut.git", from: "2.0.0"),
        .package(url: "https://github.com/hakkabon/Grammar.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/Lexer.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/GrammarDiagram.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/TerminalColors.git", from: "0.0.1"),
        .package(url: "https://github.com/hakkabon/Parser.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Earley-Parser",
            dependencies: [
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "Lexer", package: "Lexer"),
                .product(name: "GrammarDiagram", package: "GrammarDiagram"),
                .product(name: "TerminalColors", package: "TerminalColors"),
                .product(name: "Parser", package: "Parser"),
            ]
        ),
        .testTarget(
            name: "Earley-ParserTests",
            dependencies: [
                "Earley-Parser",
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "Parser", package: "Parser"),
            ]
        ),
        // Move executable target to its destination (grammar toolbox) when library confirmed working.
        .executableTarget(
            name: "earley-gtool",
            dependencies: [
                "Earley-Parser",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ShellOut", package: "shellout"),
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "GrammarDiagram", package: "GrammarDiagram"),
                .product(name: "Parser", package: "Parser"),
            ],
            path: "Sources/gtool"
        ),
    ]
)
