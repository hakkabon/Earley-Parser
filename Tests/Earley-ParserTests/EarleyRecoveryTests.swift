import Earley_Parser
import Grammar
import Parser
import Testing

@Suite("Generalized recovery")
struct EarleyRecoveryTests {
    private let grammar = try! Grammar(
        bnf: #"<program> ::= "begin" "name" ";" "end" ".""#,
        start: "program"
    )

    @Test("Accepted input does not invent repairs")
    func accepted() throws {
        let result = try EarleyParser(grammar: grammar).parseRecovering(
            "begin name ; end .", insertionCandidates: [";", "."]
        )

        #expect(result.status == .accepted)
        #expect(result.recoveryEdits.isEmpty)
        #expect(result.parseResult?.isSuccessful == true)
    }

    @Test("Two insertions produce a real recovered SPPF")
    func insertsMissingPunctuation() throws {
        let result = try EarleyParser(grammar: grammar).parseRecovering(
            "begin name end",
            insertionCandidates: [";", "."],
            policy: .init(maximumEditCost: 2, maximumExploredStates: 100)
        )

        #expect(result.status == .recovered)
        #expect(result.recoveryEdits.count == 2)
        #expect(result.diagnostics.map(\.reason) == [.missingToken, .missingToken])
        #expect(result.parseResult?.isSuccessful == true)
        #expect(result.parseResult?.sppfGraph != nil)
    }

    @Test("Budget exhaustion rejects and remains finite")
    func rejectsAtBudget() throws {
        let result = try EarleyParser(grammar: grammar).parseRecovering(
            "noise noise noise",
            insertionCandidates: [";", "."],
            policy: .init(maximumEditCost: 3, maximumExploredStates: 3)
        )

        #expect(result.status == .rejected)
        #expect(result.reachedSearchLimit)
        #expect(result.exploredStates == 3)
    }
}
