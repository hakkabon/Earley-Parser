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

    @Test("Recovery resumes the retained minimum-edit search")
    func resumesSearch() throws {
        let session = GeneralizedRecoverySearchSession<Terminal>()
        let limited = try EarleyParser(grammar: grammar).parseRecovering(
            "begin name end", insertionCandidates: [";", "."],
            policy: .init(maximumEditCost: 2, maximumExploredStates: 3),
            searchSession: session)
        #expect(limited.reachedSearchLimit)

        let resumed = try EarleyParser(grammar: grammar).parseRecovering(
            "begin name end", insertionCandidates: [";", "."],
            policy: .init(maximumEditCost: 2, maximumExploredStates: 100),
            searchSession: session)
        #expect(resumed.status == .recovered)
        #expect(resumed.quality.editCost == 2)
        #expect(resumed.quality.resumedStates == 3)
    }
}
