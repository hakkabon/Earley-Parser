import Parser
import Testing
@testable import Earley_Parser

@Test("Earley owns a reproducible executable microbenchmark")
func earleyMicrobenchmark() throws {
    let report = try EarleyParserMicrobenchmarks.run(
        buildConfiguration: .release, warmupIterations: 0, measurementIterations: 3,
        environment: .init(
            operatingSystem: "test", architecture: "test",
            processorCount: 1, physicalMemoryBytes: 1
        )
    )
    #expect(report.suite.owner.repository == "Earley-Parser")
    #expect(report.suite.engineID == "earley")
    #expect(report.results.first?.counters["accepted"] == 1)
    #expect((report.results.first?.counters["forestNodeCount"] ?? 0) > 0)
}
