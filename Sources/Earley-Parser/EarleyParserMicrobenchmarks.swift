import Foundation
import Grammar
import Parser

/// Engine-owned executable microbenchmarks for the Earley implementation.
public enum EarleyParserMicrobenchmarks {
    public static let ownerVersion = "0.2.1"
    public static let inputScale = 24

    private static let grammarSource = """
    <E> ::= <T> <R>
    <R> ::= '+' <T> <R> | ε
    <T> ::= 'id'
    """
    private static var input: String {
        Array(repeating: "id", count: inputScale).joined(separator: " + ")
    }

    public static func suite(
        buildConfiguration: ParserEngineMicrobenchmarkSuite.BuildConfiguration,
        warmupIterations: Int = 2,
        measurementIterations: Int = 10
    ) -> ParserEngineMicrobenchmarkSuite {
        .init(
            owner: .init(repository: "Earley-Parser", version: ownerVersion),
            engineID: "earley", id: "earley-core-v1", title: "Earley core workloads",
            buildConfiguration: buildConfiguration,
            warmupIterations: warmupIterations,
            measurementIterations: measurementIterations,
            cases: [.init(
                id: "expression-forest", title: "Build a right-recursive expression forest",
                operation: .forestConstruction,
                boundary: "Tokenize and construct the BSR/SPPF result with a pre-built EarleyParser.",
                workloadFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint([
                    grammarSource, input, "prebuilt-parser", "bsr-sppf"
                ]),
                scale: inputScale
            )]
        )
    }

    public static func run(
        buildConfiguration: ParserEngineMicrobenchmarkSuite.BuildConfiguration,
        warmupIterations: Int = 2,
        measurementIterations: Int = 10,
        environment: ParserEngineMicrobenchmarkEnvironment = .current
    ) throws -> ParserEngineMicrobenchmarkReport {
        let parser = EarleyParser(grammar: try Grammar(bnf: grammarSource, start: "E"))
        return try ParserEngineMicrobenchmarkRunner.run(
            suite(
                buildConfiguration: buildConfiguration,
                warmupIterations: warmupIterations,
                measurementIterations: measurementIterations
            ),
            environment: environment
        ) { _ in
            let result = try parser.parse(input)
            let nodes = result.sppfGraph?.getAllNodes().count ?? 0
            return .init(
                evidenceFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint([
                    String(result.isSuccessful), String(result.bsr.count), String(nodes)
                ]),
                counters: [
                    "accepted": result.isSuccessful ? 1 : 0,
                    "bsrCount": result.bsr.count, "forestNodeCount": nodes
                ]
            )
        }
    }
}
