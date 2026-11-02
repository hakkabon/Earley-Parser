import XCTest
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
}
