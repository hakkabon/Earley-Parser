import Testing
@testable import Earley_Parser
import Grammar

// MARK: - Helpers

/// Convenience: parse a string and return the ParseResult, failing the test on error.
private func parse(_ input: String, grammar: Grammar) throws -> ParseResult {
    let parser = EarleyParser(grammar: grammar)
    return try parser.parse(input)
}

// Scott et al 2008, Example 1
// S ::= ST | a     B ::= ϵ     T ::= aB | a
// input: a a
// Earley sets:
// E0 = { (S ::=·ST, 0), (S ::=·a,0) }
// E1 = { (S ::= a·,0), (S ::= S· T, 0), (T ::=·aB,1), (T ::=·a,1) }
// E2 = { (T ::= a· B,1), (T ::= a·,1), (B ::=·,2), (S ::= ST·,0), (T ::= aB·,1), (S ::= S· T, 0), (T ::=·aB,2), (T ::=·a,2) }
private let ScottJohnstone2008_1 = """
<S> ::= <S> <T> 
<S> ::= 'a'     
<B> ::= ε     
<T> ::= 'a' <B>  
<T> ::= 'a'
"""

// Scott et al 2008, Example 2
// input: bbb
private let ScottJohnstone2008_2 = """
<S> ::= <S> <S>
<S> ::=  'b'
"""

// Scott et al 2008, Example 3
// input: abbb
private let ScottJohnstone2008_3 = """
<S> ::= <A> <T> | 'a' <T>
<A> ::= 'a' | <B> <A>
<B> ::= ε
<T> ::= 'b' 'b' 'b'
"""

// Scott et al 2008, Example 4
// S ::= a A b B    A ::= a     B ::= A | a
// input string: aaba
private let ScottJohnstone2008_4 = """
<S> ::= 'a' <A> 'b' <B>
<A> ::= 'a'
<B> ::= <A>
<B> ::= 'a'
"""

// 𝚪1 in Scott et al. (2019)
// S ::= a A B | a A b    A ::= a | c | ϵ    B ::= b | B c | ϵ
// input: a a b
// ϒ = { (S ::= a A B,0,2,3), (S ::= a Ab,0,2,3), (a A,0,1,2), (B ::= b,2,2,3), (A ::= a,1,1,2) }
private let ScottJohnstone2019_1 = """
<S> ::= 'a' <A> <B>
<S> ::= 'a' <A> 'b'
<A> ::= 'a'
<A> ::= 'c'
<A> ::= ε
<B> ::= 'b'
<B> ::= <B> 'c'
<B> ::= ε
"""

// 𝚪2 in Scott et al. (2019)
// S ::= A C a B | A B a a  A ::= a A | a   B ::= b B | b   C ::= b C | b
// input: a b a a
// ϒ = { (A ::= a,0,0,1), (C ::= b,1,1,2), (AC ,0,1,2), (B ::= b,1,1,2),
//       (A B,0,1,2), (ACa,0,2,3), (A Ba,0,2,3), (S ::= A Baa,0,3,4) }
private let ScottJohnstone2019_2 = """
<S> ::= <A> <C> 'a' <B>
<S> ::= <A> <B> 'a' 'a'
<A> ::= 'a' <A>
<A> ::= 'a'
<B> ::= 'b' <B>
<B> ::= 'b'
<C> ::= 'b' <C>
<C> ::= 'b'
"""

// Scott et al 2019, Example 3 (Catalan numbers)
// S ::= b | SS | SSS
// input: b b b b b  (tests results p.82 depend on the number 'b's)
// BSR: {  not given, but can be derived from the Earley sets below
// }
private let ScottJohnstone2019_3 = """
<S> ::= 'b'
<S> ::= <S> <S>
<S> ::= <S> <S> <S>
"""

// Scott et al 2019, Example 4 (not numbered in the paper)
// S := A B | C B  A ::= b b   B ::= b | b b   C ::= b
// input string: b b b
// BSR:
// S0 = { (S ::= ·A B,0), (S ::= ·C B,0), (A ::= ·bb,0), (C ::= ·b,0) }
// S1 = { (A ::= b· b,0), (C ::= b·,0), (S ::= C· B,0), (B ::= ·bb,1), (B ::= ·b,1) }
// S2 = { (B ::= b·,1), (B ::= b· b,1), (A ::= bb·,0), (S ::= C B·,0),
//        (S ::= A· B,0), (B ::= ·bb,2), (B ::= ·b,2) }
// S3 = { (S ::= A B·,0), (S ::= C B·,0), (B ::= bb·,1), (B ::= b·,2), (B ::= b· b,2) }
private let ScottJohnstone2019_4 = """
<S> := <A> <B>
<S> := <C> <B>
<A> ::= 'b' 'b'
<B> ::= 'b'
<B> ::= 'b' 'b'
<C> ::= 'b'
"""

// Earley table traversing parsers, 2026
// Example grammar Γ1
// S ::= A S b | a     A ::= a A | 𝜖
// input: a a b
//
//     E0 = {(S ::=⋅ASb,0),(S ::=⋅a,0),(A ::=⋅aA,0),(A ::=⋅,0),(S ::=A⋅ Sb,0)}
//     E1 = {(S ::=a⋅,0), (A ::=a⋅ A,0), (A ::=⋅aA,1), (A ::=⋅,1),(S ::=AS⋅ b,0),
//           (A ::=aA⋅,0), (S ::=A⋅ Sb,0), (S ::=⋅ASb,1),(S ::=⋅a,1), (S ::=A⋅ Sb,1)}
//     E2 = {(S ::=a⋅,1), (A ::=a⋅ A,1), (A ::=⋅aA,2), (A ::=⋅,2),
//           (S ::=AS⋅ b,0), (S ::=AS⋅ b,1), (A ::=aA⋅,1), (A ::=aA⋅,0),
//           (S ::=A⋅ Sb,1), (S ::=⋅ASb,2), (S ::=⋅a,2), (S ::=A⋅ Sb,0),
//           (S ::=A⋅ Sb,2)}
//     E3 = {(S ::=ASb⋅,0), (S ::=ASb⋅,1), (S ::=AS⋅ b,0), (S ::=AS⋅ b,1)}
private let ScottJohnstone2026_1 = """
<S> ::= <A> <S> 'b'
<S> ::= 'a'
<A> ::= 'a' <A>
<A> ::= ε
"""

@Test("Scott et al 2008, Example 1")
func scottJohnstone2008_1() throws {
    let grammar = try Grammar(bnf: ScottJohnstone2008_1, start: "S")
    let result = try parse("a a", grammar: grammar)
    #expect(result.isSuccessful)
}

@Test("Scott et al 2008, Example 2")
func scottJohnstone2008_2() throws {
    let grammar = try Grammar(bnf: ScottJohnstone2008_2, start: "S")
    let result = try parse("b b b", grammar: grammar)
    #expect(result.isSuccessful)
}

@Test("Scott et al 2008, Example 3")
func scottJohnstone2008_3() throws {
    let grammar = try Grammar(bnf: ScottJohnstone2008_3, start: "S")
    let result = try parse("a b b b", grammar: grammar)
    #expect(result.isSuccessful)
}

@Test("Scott et al 2008, Example 4")
func scottJohnstone2008_4() throws {
    let grammar = try Grammar(bnf: ScottJohnstone2008_4, start: "S")
    let result = try parse("a a b a", grammar: grammar)
    #expect(result.isSuccessful)
}

@Test("Scott et al 2019, Example 1")
func scottJohnstone2019_1() throws {
    let grammar = try Grammar(bnf: ScottJohnstone2019_1, start: "S")
    let result = try parse("a a b", grammar: grammar)
    #expect(result.isSuccessful)
}

@Test("Scott et al 2019, Example 2")
func scottJohnstone2019_2() throws {
    let grammar = try Grammar(bnf: ScottJohnstone2019_2, start: "S")
    let result = try parse("a b a a", grammar: grammar)
    #expect(result.isSuccessful)
}

@Test("Scott et al 2019, Example 3")
func scottJohnstone2019_3() throws {
    let grammar = try Grammar(bnf: ScottJohnstone2019_3, start: "S")
    let result = try parse("b b b b b", grammar: grammar)
    #expect(result.isSuccessful)
}

@Test("Scott et al 2019, Example 4")
func scottJohnstone2019_4() throws {
    let grammar = try Grammar(bnf: ScottJohnstone2019_4, start: "S")
    let input = "b b b"
    let result = try parse(input, grammar: grammar)
    #expect(result.isSuccessful)
}

@Test("Scott et al 2026, Example 1")
func scottJohnstone2026_1() throws {
    let grammar = try Grammar(bnf: ScottJohnstone2026_1, start: "S")
    let input = "a a b"
    let result = try parse(input, grammar: grammar)
    #expect(result.isSuccessful)
    #expect(result.sppfGraph != nil)
}


@Test("Scott et al 2026, Example 1 Parse-Tree")
func scottJohnstone_parsetree_2026_1() throws {
    let grammar = try Grammar(bnf: ScottJohnstone2026_1, start: "S")
    let parser = EarleyParser(grammar: grammar)
    let input = "a a b"
    let parsetree = try parser.syntaxTree(for: input).mapLeafs{ String(input[$0]) }
    #expect(parsetree.root == "S")
}
