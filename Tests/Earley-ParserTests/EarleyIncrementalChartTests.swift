import XCTest
import IncrementalParsing
import Grammar
@testable import Earley_Parser

final class EarleyIncrementalChartTests: XCTestCase {
    func testTokenInvalidationPropagatesOnlyThroughDependentChartFacts() {
        let chart = EarleyIncrementalChart<String>()
        let left = EarleyChartFactID("scan:left")
        let completed = EarleyChartFactID("complete:left")
        let right = EarleyChartFactID("scan:right")
        chart.record(.init(id: left, value: "left", tokenDependencies: [.init("t0")]))
        chart.record(.init(id: completed, value: "completed", factDependencies: [left]))
        chart.record(.init(id: right, value: "right", tokenDependencies: [.init("t9")]))

        let evidence = chart.invalidate(tokens: [.init("t0")])

        XCTAssertEqual(evidence.removed, [left, completed])
        XCTAssertEqual(evidence.retained, [right])
        XCTAssertEqual(chart[right]?.value, "right")
    }

    func testArtifactBindingFailsClosedAndPublishesSharedEvidence() {
        let chart = EarleyIncrementalChart<String>()
        let first = IncrementalArtifactIdentity(
            id: "grammar", revision: 1, fingerprint: "first")
        let second = IncrementalArtifactIdentity(
            id: "grammar", revision: 2, fingerprint: "second")

        XCTAssertEqual(chart.bind(to: first)?.strategy, .full)
        chart.record(.init(id: .init("fact"), value: "value"))
        XCTAssertNil(chart.bind(to: first))

        let fallback = chart.bind(to: second)
        XCTAssertEqual(fallback?.strategy, .fallback)
        XCTAssertEqual(fallback?.fallback?.code, "incompatibleArtifact")
        XCTAssertEqual(
            fallback?.measurements.first { $0.dimension == .chartFacts }?.removed,
            1)
        XCTAssertEqual(chart.count, 0)
    }

    func testParserArtifactIdentityIsStableAndGrammarSensitive() throws {
        let first = EarleyParser(grammar: try Grammar(bnf: "S ::= 'a'", start: "S"))
        let equivalent = EarleyParser(grammar: try Grammar(bnf: "S ::= 'a'", start: "S"))
        let changed = EarleyParser(grammar: try Grammar(bnf: "S ::= 'b'", start: "S"))

        XCTAssertEqual(first.incrementalArtifactIdentity, equivalent.incrementalArtifactIdentity)
        XCTAssertNotEqual(
            first.incrementalArtifactIdentity.fingerprint,
            changed.incrementalArtifactIdentity.fingerprint)
    }

    func testRebuildAfterDependencyInvalidationMatchesCleanChart() {
        final class Box {
            let value: String
            init(_ value: String) { self.value = value }
        }

        let artifact = IncrementalArtifactIdentity(
            id: "grammar", revision: 1, fingerprint: "stable")
        let left = EarleyChartFactID("scan:left")
        let right = EarleyChartFactID("scan:right")
        let completed = EarleyChartFactID("complete:root")
        let chart = EarleyIncrementalChart<Box>()
        _ = chart.bind(to: artifact)
        chart.record(.init(
            id: left, value: Box("old-left"),
            tokenDependencies: [.init("left-token")]))
        let retainedBox = Box("right")
        chart.record(.init(
            id: right, value: retainedBox,
            tokenDependencies: [.init("right-token")]))
        chart.record(.init(
            id: completed, value: Box("old-root"),
            factDependencies: [left, right]))

        let invalidation = chart.invalidate(tokens: [.init("left-token")])
        XCTAssertTrue(chart[right]?.value === retainedBox)
        chart.record(.init(
            id: left, value: Box("new-left"),
            tokenDependencies: [.init("new-left-token")]))
        chart.record(.init(
            id: completed, value: Box("new-root"),
            factDependencies: [left, right]))

        let clean = EarleyIncrementalChart<Box>()
        _ = clean.bind(to: artifact)
        clean.record(.init(
            id: left, value: Box("new-left"),
            tokenDependencies: [.init("new-left-token")]))
        clean.record(.init(
            id: right, value: Box("right"),
            tokenDependencies: [.init("right-token")]))
        clean.record(.init(
            id: completed, value: Box("new-root"),
            factDependencies: [left, right]))

        XCTAssertEqual(chart.factIDs, clean.factIDs)
        for id in clean.factIDs {
            XCTAssertEqual(chart[id]?.value.value, clean[id]?.value.value)
        }
        let evidence = invalidation.executionEvidence(rebuiltFactCount: 2)
        XCTAssertEqual(evidence.strategy, .incremental)
        XCTAssertEqual(evidence.measurements.first?.reused, 1)
        XCTAssertEqual(evidence.measurements.first?.rebuilt, 2)
        XCTAssertEqual(evidence.measurements.first?.removed, 2)
    }
}
