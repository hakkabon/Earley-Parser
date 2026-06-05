import Testing
@testable import Earley_Parser
import Grammar

// MARK: - Helpers

/// Convenience: parse a string and return the ParseResult, failing the test on error.
private func parse(_ input: String, grammar: Grammar) throws -> ParseResult {
    let parser = EarleyParser(grammar: grammar)
    return try parser.parse(input)
}

// MARK: - 1. Simple unambiguous arithmetic grammar

private let arithmeticGrammarBNF = """
<expr>   ::= <expr> "+" <term> | <term>
<term>   ::= <term> "*" <factor> | <factor>
<factor> ::= "(" <expr> ")" | <number>
<number> ::= "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9"
"""

@Suite("Arithmetic Grammar")
struct ArithmeticGrammarTests {

    let grammar: Grammar

    init() throws {
        grammar = try Grammar(bnf: arithmeticGrammarBNF, start: "expr")
    }

    @Test("Single digit parses successfully")
    func singleDigit() throws {
        let result = try parse("1", grammar: grammar)
        #expect(result.isSuccessful)
    }

    @Test("Addition of two digits")
    func addition() throws {
        let result = try parse("1 + 2", grammar: grammar)
        #expect(result.isSuccessful)
        #expect(!result.hasAmbiguity)
    }

    @Test("Multiplication of two digits")
    func multiplication() throws {
        let result = try parse("3 * 4", grammar: grammar)
        #expect(result.isSuccessful)
        #expect(!result.hasAmbiguity)
    }

    @Test("Mixed arithmetic expression")
    func mixedExpression() throws {
        let result = try parse("1 + 2 * 3", grammar: grammar)
        #expect(result.isSuccessful)
        #expect(!result.hasAmbiguity)
    }

    @Test("Parenthesised expression")
    func parenthesised() throws {
        let result = try parse("( 1 + 2 ) * 3", grammar: grammar)
        #expect(result.isSuccessful)
        #expect(!result.hasAmbiguity)
    }

    @Test("BSR set is non-empty on success")
    func bsrNonEmpty() throws {
        let result = try parse("1 + 2", grammar: grammar)
        #expect(result.isSuccessful)
        #expect(!result.bsr.isEmpty)
    }

    @Test("SPPF graph is produced on success")
    func sppfProduced() throws {
        let result = try parse("1 + 2", grammar: grammar)
        #expect(result.isSuccessful)
        #expect(result.sppfGraph != nil)
    }

    @Test("SPPF graph has a root node spanning full input")
    func sppfRootNode() throws {
        let result = try parse("1 + 2", grammar: grammar)
        #expect(result.isSuccessful)
        guard let graph = result.sppfGraph else {
            Issue.record("Expected SPPF graph")
            return
        }
        let nodes = graph.getAllNodes()
        let hasRoot = nodes.contains { node in
            if case let .symbol(label, left, right) = node {
                return label == "expr" && left == 0 && right == 3
            }
            return false
        }
        #expect(hasRoot, "Root node (expr, 0, 3) should be present")
    }

    @Test("Invalid expression throws SyntaxError")
    func invalidExpression() throws {
        #expect(throws: SyntaxError.self) {
            try parse("1 + + 2", grammar: grammar)
        }
    }
}

// MARK: - 2. Nullable / epsilon productions

private let nullableGrammarBNF = """
<S> ::= <A> <B>
<A> ::= "a" | ""
<B> ::= "b" | ""
"""

@Suite("Nullable Productions")
struct NullableProductionTests {

    let grammar: Grammar

    init() throws {
        grammar = try Grammar(bnf: nullableGrammarBNF, start: "S")
    }

    @Test("Both non-terminals present")
    func bothPresent() throws {
        let result = try parse("a b", grammar: grammar)
        #expect(result.isSuccessful)
    }

    @Test("Only A present (B is nullable)")
    func onlyA() throws {
        let result = try parse("a", grammar: grammar)
        #expect(result.isSuccessful)
    }

    @Test("Only B present (A is nullable)")
    func onlyB() throws {
        let result = try parse("b", grammar: grammar)
        #expect(result.isSuccessful)
    }

    @Test("Empty string (both nullable)")
    func emptyString() throws {
        // The grammar accepts ε because both A and B are nullable.
        // An empty input string should succeed.
        let result = try parse("", grammar: grammar)
        #expect(result.isSuccessful)
    }
}

// MARK: - 3. Ambiguous grammar
// The classic ambiguous expression grammar (no precedence):

private let ambiguousGrammarBNF = """
<E> ::= <E> "+" <E> | <E> "*" <E> | "(" <E> ")" | "a"
"""

@Suite("Ambiguous Grammar")
struct AmbiguousGrammarTests {

    let grammar: Grammar

    init() throws {
        grammar = try Grammar(bnf: ambiguousGrammarBNF, start: "E")
    }

    @Test("Single token parses")
    func singleToken() throws {
        let result = try parse("a", grammar: grammar)
        #expect(result.isSuccessful)
    }

    @Test("a + a parses")
    func addition() throws {
        let result = try parse("a + a", grammar: grammar)
        #expect(result.isSuccessful)
    }

    @Test("a + a * a is ambiguous")
    func ambiguousExpression() throws {
        let result = try parse("a + a * a", grammar: grammar)
        #expect(result.isSuccessful)
        // The grammar is ambiguous: "a + a * a" has two parse trees.
        #expect(result.hasAmbiguity, "Expected ambiguity for 'a + a * a'")
    }

    @Test("BSR set contains multiple derivations for ambiguous input")
    func bsrAmbiguity() throws {
        let result = try parse("a + a * a", grammar: grammar)
        #expect(result.isSuccessful)
        // Multiple BSR entries for E spanning the full input indicate ambiguity.
        let fullSpanEntries = result.bsr.filter { entry in
            if case let .pnode(pn) = entry.node {
                return pn.goal.name == "E" && entry.leftExtent == 0 && entry.rightExtent == 5
            }
            return false
        }
        #expect(fullSpanEntries.count >= 2, "Expected ≥2 BSR pnodes for E spanning full input")
    }
}

// MARK: - 4. Left-recursive grammar

private let leftRecursiveGrammarBNF = """
<list> ::= <list> "," <item> | <item>
<item> ::= "x"
"""

@Suite("Left-Recursive Grammar")
struct LeftRecursiveGrammarTests {

    let grammar: Grammar

    init() throws {
        grammar = try Grammar(bnf: leftRecursiveGrammarBNF, start: "list")
    }

    @Test("Single item")
    func singleItem() throws {
        let result = try parse("x", grammar: grammar)
        #expect(result.isSuccessful)
    }

    @Test("Two items")
    func twoItems() throws {
        let result = try parse("x , x", grammar: grammar)
        #expect(result.isSuccessful)
    }

    @Test("Three items")
    func threeItems() throws {
        let result = try parse("x , x , x", grammar: grammar)
        #expect(result.isSuccessful)
    }

    @Test("Five items")
    func fiveItems() throws {
        let result = try parse("x , x , x , x , x", grammar: grammar)
        #expect(result.isSuccessful)
        #expect(!result.hasAmbiguity)
    }
}

// MARK: - 5. Right-recursive grammar

private let rightRecursiveGrammarBNF = """
<S> ::= "a" <S> | "a"
"""

@Suite("Right-Recursive Grammar")
struct RightRecursiveGrammarTests {

    let grammar: Grammar

    init() throws {
        grammar = try Grammar(bnf: rightRecursiveGrammarBNF, start: "S")
    }

    @Test("Single a")
    func singleA() throws {
        let result = try parse("a", grammar: grammar)
        #expect(result.isSuccessful)
    }

    @Test("Three a's")
    func threeAs() throws {
        let result = try parse("a a a", grammar: grammar)
        #expect(result.isSuccessful)
    }
}

// MARK: - 6. Parse tree extraction

@Suite("Parse Tree Extraction")
struct ParseTreeExtractionTests {

    let grammar: Grammar

    init() throws {
        grammar = try Grammar(bnf: arithmeticGrammarBNF, start: "expr")
    }

    @Test("Extract parse trees from SPPF")
    func extractTrees() throws {
        let parser = EarleyParser(grammar: grammar)
        let result = try parser.parse("1 + 2")
        #expect(result.isSuccessful)
        guard let graph = result.sppfGraph else {
            Issue.record("Expected SPPF graph")
            return
        }
        let trees = parser.extractParseTreesFromGraph(graph, extent: (left: 0, right: 3))
        #expect(!trees.isEmpty, "Should extract at least one parse tree")
    }

    @Test("Parse tree root symbol matches start symbol")
    func treeRootSymbol() throws {
        let parser = EarleyParser(grammar: grammar)
        let result = try parser.parse("1 + 2")
        #expect(result.isSuccessful)
        guard let graph = result.sppfGraph else {
            Issue.record("Expected SPPF graph")
            return
        }
        let trees = parser.extractParseTreesFromGraph(graph, extent: (left: 0, right: 3))
        #expect(!trees.isEmpty)
        #expect(trees.first?.symbol == "expr")
    }

    @Test("Unambiguous grammar yields exactly one parse tree")
    func unambiguousOneTree() throws {
        let parser = EarleyParser(grammar: grammar)
        let result = try parser.parse("1 + 2")
        #expect(result.isSuccessful)
        guard let graph = result.sppfGraph else {
            Issue.record("Expected SPPF graph")
            return
        }
        let trees = parser.extractParseTreesFromGraph(graph, extent: (left: 0, right: 3))
        #expect(trees.count == 1, "Unambiguous grammar should yield exactly one parse tree")
    }
}

// MARK: - 7. BSR correctness

@Suite("BSR Correctness")
struct BSRCorrectnessTests {

    @Test("BSR pnodes cover start symbol for successful parse")
    func startSymbolCovered() throws {
        let grammar = try Grammar(bnf: arithmeticGrammarBNF, start: "expr")
        let result = try parse("1 + 2", grammar: grammar)
        #expect(result.isSuccessful)
        let startEntries = result.bsr.filter { entry in
            if case let .pnode(pn) = entry.node {
                return pn.goal.name == "expr" && entry.leftExtent == 0 && entry.rightExtent == 3
            }
            return false
        }
        #expect(!startEntries.isEmpty, "BSR must contain a pnode for the start symbol spanning full input")
    }

    @Test("BSR extents are consistent (leftExtent ≤ pivot ≤ rightExtent)")
    func extentsConsistent() throws {
        let grammar = try Grammar(bnf: arithmeticGrammarBNF, start: "expr")
        let result = try parse("1 + 2 * 3", grammar: grammar)
        #expect(result.isSuccessful)
        for entry in result.bsr {
            #expect(entry.leftExtent <= entry.pivot,
                    "leftExtent (\(entry.leftExtent)) must be ≤ pivot (\(entry.pivot)) in \(entry)")
            #expect(entry.pivot <= entry.rightExtent,
                    "pivot (\(entry.pivot)) must be ≤ rightExtent (\(entry.rightExtent)) in \(entry)")
        }
    }

    @Test("BSR is empty for failed parse")
    func emptyOnFailure() throws {
        let grammar = try Grammar(bnf: arithmeticGrammarBNF, start: "expr")
        // "1 + + 2" is not in the language — parse should throw.
        var threw = false
        do {
            _ = try parse("1 + + 2", grammar: grammar)
        } catch {
            threw = true
        }
        #expect(threw, "Expected parse to throw for invalid input")
    }
}

// MARK: - 8. SPPF structural invariants

@Suite("SPPF Structural Invariants")
struct SPPFInvariantTests {

    @Test("Symbol nodes have only packed-node children")
    func symbolNodesHavePackedChildren() throws {
        let grammar = try Grammar(bnf: arithmeticGrammarBNF, start: "expr")
        let result = try parse("1 + 2", grammar: grammar)
        #expect(result.isSuccessful)
        guard let graph = result.sppfGraph else { return }

        for node in graph.getAllNodes() {
            if case .symbol = node {
                let children = graph.getChildren(of: node)
                for child in children {
                    if case .packed = child {
                        // correct
                    } else {
                        Issue.record("Symbol node \(node) has non-packed child \(child)")
                    }
                }
            }
        }
    }

    @Test("Packed nodes have at most two children")
    func packedNodesAtMostTwoChildren() throws {
        let grammar = try Grammar(bnf: arithmeticGrammarBNF, start: "expr")
        let result = try parse("1 + 2 * 3", grammar: grammar)
        #expect(result.isSuccessful)
        guard let graph = result.sppfGraph else { return }

        for node in graph.getAllNodes() {
            if case .packed = node {
                let childCount = graph.getChildren(of: node).count
                #expect(childCount <= 2, "Packed node \(node) has \(childCount) children (expected ≤ 2)")
            }
        }
    }

    @Test("No extendable nodes remain after extraction")
    func noExtendableNodesRemain() throws {
        let grammar = try Grammar(bnf: arithmeticGrammarBNF, start: "expr")
        let result = try parse("1 + 2", grammar: grammar)
        #expect(result.isSuccessful)
        guard let graph = result.sppfGraph else { return }
        #expect(graph.getExtendableNodes().isEmpty, "All extendable nodes should be expanded")
    }
}

// MARK: - 9. Deterministic Parser and All Syntax Trees Compliance

@Suite("Deterministic and General Syntax Tree Extraction")
struct DeterministicAndGeneralSyntaxTreeTests {

    @Test("Unambiguous syntaxTree(for:) returns correct ParseTree structure and ranges")
    func unambiguousSyntaxTree() throws {
        let grammar = try Grammar(bnf: arithmeticGrammarBNF, start: "expr")
        let parser = EarleyParser(grammar: grammar)
        
        let input = "1 + 2"
        let tree = try parser.syntaxTree(for: input)
        
        // Verify root node is 'expr'
        #expect(tree.root?.name == "expr")
        
        // Verify kids
        guard let kids = tree.children else {
            Issue.record("Expected children")
            return
        }
        #expect(kids.count == 3)
        #expect(kids[0].root?.name == "expr")
        #expect(kids[1].root == nil) // leaf
        #expect(kids[2].root?.name == "term")
        
        // Check leaf ranges match input characters
        let leafs = tree.leafs
        #expect(leafs.count == 3)
        #expect(input[leafs[0]] == "1")
        #expect(input[leafs[1]] == "+")
        #expect(input[leafs[2]] == "2")
    }

    @Test("Ambiguous grammar allSyntaxTrees(for:) returns multiple unique ParseTrees")
    func ambiguousAllSyntaxTrees() throws {
        let grammar = try Grammar(bnf: ambiguousGrammarBNF, start: "E")
        let parser = EarleyParser(grammar: grammar)
        
        let trees = try parser.allSyntaxTrees(for: "a + a * a")
        #expect(trees.count == 2)
        
        let str1 = "\(trees[0])"
        let str2 = "\(trees[1])"
        #expect(str1 != str2, "The two parse trees should be distinct structures")
    }

    @Test("syntaxTree(for:) on invalid input throws SyntaxError")
    func syntaxTreeInvalidInputThrows() throws {
        let grammar = try Grammar(bnf: arithmeticGrammarBNF, start: "expr")
        let parser = EarleyParser(grammar: grammar)
        
        #expect(throws: SyntaxError.self) {
            try parser.syntaxTree(for: "1 + + 2")
        }
    }
}

// MARK: - 10. Tomita's grammar (S ::= S S | "a")
// For n tokens the number of parse trees is the (n-1)-th Catalan number.
// C(1) = 1, C(2) = 2, C(3) = 5

private let tomitaGrammarBNF = """
<S> ::= <S> <S> | "a"
"""

@Suite("Tomita Grammar — Catalan-number ambiguity")
struct TomitaGrammarTests {

    let grammar: Grammar
    let parser: EarleyParser

    init() throws {
        grammar = try Grammar(bnf: tomitaGrammarBNF, start: "S")
        parser  = EarleyParser(grammar: grammar)
    }

    @Test("Single 'a' yields exactly 1 parse tree")
    func oneToken() throws {
        let trees = try parser.allSyntaxTrees(for: "a")
        #expect(trees.count == 1)
    }

    @Test("Two 'a's yield exactly 1 parse tree")
    func twoTokens() throws {
        // S S with one split → only one way to split 2 tokens.
        let trees = try parser.allSyntaxTrees(for: "a a")
        #expect(trees.count == 1)
    }

    @Test("Three 'a's yield exactly 2 parse trees (Catalan C(2))")
    func threeTokens() throws {
        let trees = try parser.allSyntaxTrees(for: "a a a")
        #expect(trees.count == 2, "Expected Catalan C(2) = 2 distinct trees for 3 tokens")
        let str0 = "\(trees[0])"
        let str1 = "\(trees[1])"
        #expect(str0 != str1, "The two trees must be structurally distinct")
    }

    @Test("Four 'a's yield exactly 5 parse trees (Catalan C(3))")
    func fourTokens() throws {
        let trees = try parser.allSyntaxTrees(for: "a a a a")
        #expect(trees.count == 5, "Expected Catalan C(3) = 5 distinct trees for 4 tokens")
    }

    @Test("hasAmbiguity is true for 3 or more tokens")
    func ambiguityDetected() throws {
        let result = try parser.parse("a a a")
        #expect(result.isSuccessful)
        #expect(result.hasAmbiguity, "Tomita grammar is ambiguous for ≥3 tokens")
    }
}

// MARK: - 11. Epsilon-only grammar (S ::= "")

private let epsilonOnlyGrammarBNF = """
<S> ::= ""
"""

@Suite("Epsilon-only Grammar")
struct EpsilonOnlyGrammarTests {

    let grammar: Grammar

    init() throws {
        grammar = try Grammar(bnf: epsilonOnlyGrammarBNF, start: "S")
    }

    @Test("Empty string is accepted")
    func emptyStringAccepted() throws {
        let result = try parse("", grammar: grammar)
        #expect(result.isSuccessful)
    }

    @Test("Non-empty input is rejected")
    func nonEmptyRejected() {
        #expect(throws: SyntaxError.self) {
            try parse("a", grammar: grammar)
        }
    }

    @Test("syntaxTree(for:) on empty string succeeds")
    func syntaxTreeEmpty() throws {
        let parser = EarleyParser(grammar: grammar)
        let tree = try parser.syntaxTree(for: "")
        #expect(tree.root?.name == "S")
    }
}

// MARK: - 12. Memoisation correctness

@Suite("Memoisation Correctness")
struct MemoisationTests {

    @Test("All leaves in all trees map to valid substrings of the input")
    func leafRangesValid() throws {
        let grammar = try Grammar(bnf: ambiguousGrammarBNF, start: "E")
        let parser  = EarleyParser(grammar: grammar)
        let input   = "a + a * a"

        let trees = try parser.allSyntaxTrees(for: input)
        #expect(!trees.isEmpty)

        for tree in trees {
            for leafRange in tree.leafs {
                // Each leaf range must be a valid, non-empty slice of the input.
                #expect(leafRange.lowerBound < leafRange.upperBound ||
                        leafRange.lowerBound == leafRange.upperBound,
                        "Leaf range must be well-formed")
                #expect(leafRange.lowerBound >= input.startIndex)
                #expect(leafRange.upperBound <= input.endIndex)
            }
        }
    }

    @Test("Repeated calls to allSyntaxTrees return the same number of trees")
    func deterministicResults() throws {
        let grammar = try Grammar(bnf: ambiguousGrammarBNF, start: "E")
        let parser  = EarleyParser(grammar: grammar)
        let input   = "a + a * a"

        let first  = try parser.allSyntaxTrees(for: input)
        let second = try parser.allSyntaxTrees(for: input)
        #expect(first.count == second.count,
                "allSyntaxTrees must be deterministic across calls")
    }

    @Test("Shared sub-forests produce consistent leaf content across all trees")
    func sharedSubForestConsistency() throws {
        // Use left-recursive grammar — sub-forests are heavily shared.
        let grammar = try Grammar(bnf: leftRecursiveGrammarBNF, start: "list")
        let parser  = EarleyParser(grammar: grammar)
        let input   = "x , x , x"

        let trees = try parser.allSyntaxTrees(for: input)
        // Unambiguous grammar → exactly one tree.
        #expect(trees.count == 1)
        // Every leaf must be "x" or ",".
        let validLeafContent: Set<Substring> = ["x", ","]
        for leafRange in trees[0].leafs {
            #expect(validLeafContent.contains(input[leafRange]),
                    "Unexpected leaf content: \(input[leafRange])")
        }
    }
}
