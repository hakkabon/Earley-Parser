# Earley-Parser

A Swift implementation of the Earley parsing algorithm with full support for ambiguous grammars, nullable productions, and left/right recursion. The parser produces a **Shared Packed Parse Forest (SPPF)** that compactly represents all possible parse trees for an input string, including all derivations for ambiguous grammars.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)  
[![Platforms](https://img.shields.io/badge/platforms-macOS%2011%20%7C%20iOS%2014-blue.svg)](https://developer.apple.com/swift/)  
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)  

---

## Features

- Handles **all context-free grammars** — ambiguous, left-recursive, right-recursive, and grammars with nullable (ε) productions
- O(n³) worst-case time complexity, O(n²) for unambiguous grammars, and O(n) for most LR(k) grammars
- Internally stores derivations as a **BSR (Binary Subtree Representation)** set
- Synthesises a **SPPF graph** from the BSR set on demand
- Complies with **`DeterministicParser`** to extract a single `ParseTree` (`SyntaxTree<NonTerminal, Range<String.Index>>`)
- Extracts all possible **parse trees** (`allSyntaxTrees(for:)`) from the SPPF for ambiguous inputs
- Performs **Reachability & Productivity garbage collection** on the SPPF to eliminate dead-end states
- Graphviz DOT output for visualising the SPPF
- Command-line tool (`gtool`) for interactive grammar exploration

---

## Theoretical Background

The implementation draws on three primary sources:

1. **Grune & Jacobs** — *Parsing Techniques: A Practical Guide*, 2nd ed., Springer 2008.  
   The core Earley recogniser (Predictor / Scanner / Completer) follows the presentation in Chapter 7.

2. **Scott, Johnstone & van Binsbergen** — *Derivation representation using binary subtree sets*, Science of Computer Programming 175 (2019) 63–84.  
   The BSR set construction (Algorithm 1) and the SPPF extraction algorithm (§3.2) are taken directly from this paper.

3. **Scott & Johnstone** — *Recognition Is Not Parsing — SPPF-Style Parsing From Cubic Recognisers*, 2009.  
   The SPPF node types (symbol, intermediate, packed, leaf) and the binarised structure of the SPPF follow this paper.

### The Earley Algorithm

The Earley algorithm processes an input string of length *n* by maintaining *n+1* chart sets S[0]…S[n]. Each chart set contains **Earley items** of the form `(X ::= α·β, i)`, meaning: production `X ::= αβ` has been partially matched, `α` has been consumed starting at position `i`, and the dot is currently before `β`.

Three operations drive the algorithm:

| Operation | Trigger | Action |  
|-----------|---------|--------|  
| **Predictor** | Item `(X ::= α·Yβ, i)` — dot before non-terminal Y | Add `(Y ::= ·γ, j)` to S[j] for every production `Y ::= γ`. Predicts immediate completion (Aycock & Horspool style) if Y is nullable. |  
| **Scanner** | Item `(X ::= α·bβ, i)` — dot before terminal b | If input[j] = b, add `(X ::= αb·β, i)` to S[j+1] |  
| **Completer** | Item `(X ::= α·, i)` — completed | For every `(Y ::= δ·Xμ, k)` in S[i], add `(Y ::= δX·μ, k)` to S[j] |  

### BSR Set

Rather than building a parse forest directly during recognition, the parser records **BSR tuples** ϒ. Each tuple encodes one derivation step:

```
(X ::= αβ, i, k, j)   — pnode: complete derivation of X from i to j, split at k  
(α, i, k, j)          — snode: intermediate left-spine derivation of α from i to j, split at k  
```

The BSR rules (Scott et al. Algorithm 1) are:

- **β = ε** (completed rule): insert pnode `(X ::= αβ, i, k, j)`
- **|α| > 1** (intermediate): insert snode `(α, i, k, j)`
- **|α| = 1** (dot at position 1, β ≠ ε): nothing to record (no binary split to represent)
- **|α| = 0** (dot at start): nothing to record

### SPPF Extraction & Garbage Collection

The SPPF is built from the BSR set using the algorithm from Scott et al. §3.2:

1. Create root symbol node `(S, 0, n)`.
2. While the graph has an **extendable** node `(μ, i, j)` (a symbol or intermediate node with no children yet):
   - If μ is a non-terminal X: find all `(X ::= γ, i, k, j) ∈ ϒ` and call `makePackedNode`.
   - If μ is an intermediate label `X ::= α·δ`:
     - If |α| = 1: call `makePackedNode` with pivot = i.
     - If |α| > 1: find all `(α, i, k, j) ∈ ϒ` and call `makePackedNode`.
3. `makePackedNode(X ::= α·δ, i, k, j)` creates a packed node `(X ::= α·δ, i, j, k)` and attaches:
   - Right child: last symbol of α, spanning (k, j).
   - Left child (if |α| ≥ 2): symbol node for α[0] (if |α| = 2) or intermediate node (if |α| > 2) spanning (i, k).

**Garbage Collection**: To prevent dead-end paths (symbol or intermediate nodes representing branches that did not complete) from bloating the graph or leaving unexpanded nodes, a post-extraction productivity analysis is run. A node is productive if it is a leaf, if it has at least one productive packed child, or if it is a packed node whose children are all productive. Unproductive nodes are purged.

---

## Concrete Syntax Tree (CST) Enumeration

The parser supports extracting concrete syntax trees as `ParseTree` structures, defined as `SyntaxTree<NonTerminal, Range<String.Index>>`. 

### The Enumeration Algorithm

We traverse the SPPF graph starting from the root symbol node `(S, 0, n)` to reconstruct the syntax tree:
- **Leaf nodes** `leaf(label, i, j)` yield a leaf tree containing the token range `Range<String.Index>`.
- **Symbol nodes** `symbol(label, i, j)` wrap their children in a `.node(NonTerminal(label), children: [...])` structure.
- **Intermediate nodes** represent prefix groupings. They do **not** introduce new nodes in the final syntax tree; instead, their child derivations are **flattened** directly into the children list of their parent packed node.
- **Packed nodes** represent the binary split. They combine the child list of their left branch (from an intermediate or symbol node) and right branch (from a symbol or leaf node) into a single concatenated list of children.

Cycles are detected during traversal using a visited set to prevent infinite loops on recursive grammars.

---

## Project Structure

```
Sources/
  Earley-Parser/
    EarleyParser.swift          — Core Predictor, Scanner, Completer, bsrAdd
    EarleyParserParse.swift     — parse(), syntaxTree(for:), allSyntaxTrees(for:)
    CSTEnumeration.swift        — CST extraction, intermediate node flattening, and ranges mapping
    ExtractSPPF.swift           — SPPF construction from BSR set and GC cleanup
    ExtractParseTree.swift      — Parse tree extraction for internal EarleyParseTree
    BSR/
      BinarySubtreeRepresentation.swift  — BSR tuple types
    SPPF/
      SPPFGraph.swift             — SPPF graph data structure & cleanup
      SPPFNode.swift              — GraphNode enum (leaf/symbol/intermediate/packed)
      NodeLabel.swift             — Production label with dot position
      SPPFAnalyze.swift           — Debug/analysis helpers
      SPPFgraphviz.swift          — Graphviz DOT output
    Parser/
      DeterministicParser.swift   — DeterministicParser protocol, ParseTree alias
      GeneralizedParser.swift     — GeneralizedParser protocol, ParseResult
      ParserLogger.swift          — OSLog categories
      SyntaxError.swift           — Error type
  gtool/
    GrammarTool.swift             — CLI entry point
    Parse.swift                   — `parse` subcommand
    Definitions.swift             — CLI option types
Tests/
  Earley-ParserTests/
    Earley_ParserTests.swift      — Test suite
```

---

## Usage

### As a Library

```swift
import Grammar
import Earley_Parser

// 1. Define a grammar in BNF notation
let bnf = """
<expr>   ::= <expr> "+" <term> | <term>
<term>   ::= <term> "*" <factor> | <factor>
<factor> ::= "(" <expr> ")" | <number>
<number> ::= "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9"
"""

let grammar = try Grammar(bnf: bnf, start: "expr")
let parser  = EarleyParser(grammar: grammar)

// 2. Parse an input string and get a single Concrete Syntax Tree
do {
    let tree = try parser.syntaxTree(for: "1 + 2 * 3")
    print("Parsed successfully!")
    print(tree) // Pretty print visual representation of the tree
} catch {
    print("Failed to parse: \(error)")
}

// 3. For ambiguous grammars, get all possible Parse Trees
let ambiguousBNF = "<E> ::= <E> \"+\" <E> | <E> \"*\" <E> | \"a\""
let ambGrammar = try Grammar(bnf: ambiguousBNF, start: "E")
let ambParser = EarleyParser(grammar: ambGrammar)

if let trees = try? ambParser.allSyntaxTrees(for: "a + a * a") {
    print("Found \(trees.count) parse trees:")
    for (index, tree) in trees.enumerated() {
        print("\nTree #\(index + 1):")
        print(tree)
    }
}
```

### Parsing a `TokenStream` directly

`parse(_ string:)` is a convenience over `parse(stream:)` that tokenizes with
GrammarTokenizer's general-purpose `Tokenizer`. Any `TokenStream` — from
[Lexer](https://github.com/hakkabon/Lexer) — can be passed directly instead,
which is what makes a fully automated, `GrammarVocabulary`-driven DFA lexer a
drop-in replacement for the hand-written tokenizer:

```swift
import Grammar
import Lexer
import Earley_Parser

// Option 1: a DFA lexer built from this grammar's own GrammarVocabulary.
var builder = LexerBuilder()
builder.loadVocabulary(myGrammarVocabulary)
let lexer = try builder.build()
let dfaStream = try LexerTokenStream(source: "1 + 2 * 3", lexer: lexer)
let result1 = try parser.parse(stream: dfaStream)

// Option 2: GrammarTokenizer's hand-written Tokenizer (what parse(_:) uses
// internally by default).
let tokenizerStream = TokenizerStream(source: "1 + 2 * 3", symbols: ["+", "*"])
let result2 = try parser.parse(stream: tokenizerStream)
```

Both streams satisfy the same `TokenStream` protocol, so a parser never has to
know or care which front end produced the tokens it's reading.

### Command-Line Tool (`gtool`)

```bash
# Build the tool
swift build -c release

# Parse a string using a BNF grammar file
.build/release/gtool --grammar mygrammar.bnf --start expr --input "1 + 2 * 3"

# Display the SPPF as a PDF (requires Graphviz)
.build/release/gtool --grammar mygrammar.bnf --start expr --input "1 + 2" --analysis sppf
```

---

## SPPF Node Types

| Node type | Description | Identity |  
|-----------|-------------|----------|  
| `symbol(label, i, j)` | Non-terminal X spanning input[i..j] | (label, i, j) |  
| `leaf(label, i, j)` | Terminal or ε spanning input[i..j] | (label, i, j) |  
| `intermediate(label, i, j)` | Partial derivation `X ::= α·δ` spanning (i, j) | (label, i, j) |  
| `packed(label, i, j, k)` | One specific production application for `(i, j)` with pivot k | (label, i, j, k) |  

---

## Running the Tests

```bash
swift test
```

The test suite covers:

| Suite | What it tests |
|-------|---------------|
| `Arithmetic Grammar` | Successful parses, SPPF root node, error handling |  
| `Nullable Productions` | ε rules, partial nullable inputs, empty string |  
| `Ambiguous Grammar` | Ambiguity detection, multiple BSR entries |  
| `Left-Recursive Grammar` | Lists of varying length |  
| `Right-Recursive Grammar` | Right-recursive sequences |  
| `Parse Tree Extraction` | Internal `EarleyParseTree` count, root symbol |  
| `BSR Correctness` | Start symbol coverage, extent consistency, failure case |  
| `SPPF Structural Invariants` | Symbol→packed children, packed ≤ 2 children, no extendable nodes remain |  
| `Deterministic and General Syntax Tree Extraction` | `syntaxTree(for:)`, `allSyntaxTrees(for:)`, character ranges |  

---

## Dependencies

- [Grammar](https://github.com/hakkabon/Grammar) (Grammar types, BNF/EBNF/WSN parsers)
- [Lexer](https://github.com/hakkabon/Lexer) (`TokenStream` protocol, DFA lexer, and GrammarTokenizer bridge — see below)
- [GrammarDiagram](https://github.com/hakkabon/GrammarDiagram) (Railroad diagram generation)
- [TerminalColors](https://github.com/hakkabon/TerminalColors) (Coloured terminal output)
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) (CLI `gtool`)
- [ShellOut](https://github.com/JohnSundell/ShellOut) (Shell commands)

---

## License

MIT License — see [LICENSE](LICENSE) for details.  
