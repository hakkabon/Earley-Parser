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
        .package(url: "https://github.com/hakkabon/Grammar.git", revision: "69f85d7a493e1862412c34493e3656e94331df06"),
        .package(url: "https://github.com/hakkabon/Lexer.git", revision: "efac321be75676bdb88a447f7ea0dd9d1b3bb851"),
        .package(url: "https://github.com/hakkabon/GrammarDiagram.git", revision: "dc17ab061a1614ba0692be06aa69043b45bbbcd4"),
        .package(url: "https://github.com/hakkabon/TerminalColors.git", from: "0.0.1"),
        .package(url: "https://github.com/hakkabon/Parser.git", revision: "3663097550f3ed1b8dcad8a26f4c2c55cc61b4e1"),
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
