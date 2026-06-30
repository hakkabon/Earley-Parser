# ALGORITHM.md — Earley-Parser

This document describes the parsing pipeline implemented in this package —
recognition, derivation-forest construction, and parse-tree extraction — and
gives a dedicated treatment of epsilon/nullable-symbol handling, which is the
single hardest correctness issue in this codebase and the source of the bug
fixed in `ExtractSPPF.expandSymbolNode`.

The pipeline has four stages:

```
input string
    │  EarleyParser.parse()
    ▼
recognizer chart  (Set<ParseStateItem> per position)
    │  predict / scan / complete
    ▼
BSR set ϒ   (Set<BSR>)                         — EarleyParser.swift
    │  extractSPPF()
    ▼
SPPF graph   (SPPFGraph)                       — BSR/ExtractSPPF.swift
    │  syntaxTree() / allSyntaxTrees()
    ▼
ParseTree(s)                                   — TreeBuilder.swift, CSTEnumeration.swift
```

---

## 1. The recognizer: predict / scan / complete

`EarleyParser` builds a sequence of chart sets `S[0]...S[n]`, one per input
position, each holding `ParseStateItem`s of the form `(X ::= α·β, i)` — "in
state `j`, production `X ::= αβ` has matched `α` starting at position `i`,
and is waiting to match `β`". Three functions populate the chart:

- **`predict(item:currentIndex:productions:allStates:)`** — when the next
  symbol is a non-terminal `Y`, add `(Y ::= ·γ, j)` for every production of
  `Y`.
- **`scan(state:token:currentIndex:)`** — when the next symbol is a terminal
  matching the current token, advance the dot.
- **`complete(item:currentIndex:allStates:)`** — when an item is fully
  matched, advance every item in `S[i]` that was waiting on this
  non-terminal.

This is the textbook algorithm, with one essential addition: **nullable-symbol
handling**, following Aycock & Horspool, *"Practical Earley Parsing"* (The
Computer Journal, 2002). Without it, a production like `A ::= a A | ε` would
need `A` to "complete" before it can be predicted into a waiting item, but a
zero-width completion never naturally fires inside the predict/scan/complete
loop in the same chart set — the classic Earley implementation either loops
forever on nullable cycles or under-derives. `predict()` works around this by
checking `nullableNonTerminals` (`Grammar.nullableNonTerminals`, a transitive
fixed-point over the grammar, computed once) and, if the predicted symbol is
nullable, *immediately* advancing the waiting item in the same step:

```swift
if nullableNonTerminals.contains(nonTerminal) {
    addedItems.append(item.advanced())                 // skip Y, as if it matched ε
    if let bsrItem = bsrAdd(item: item.advanced(),
                            leftExtent: item.startTokenIndex, pivot: currentIndex, rightExtent: currentIndex) {
        bsr.insert(bsrItem)
    }
}
```

This correctly and efficiently recognizes nullable derivations. But — and
this is the seed of everything in §4 — it does so by **never actually
completing an explicit `A ::= ε·` item**. The recognizer only ever proves
*that* `A` matched nothing at position `j`; it never produces a chart item
whose own completion records *which* production realized that ε-match. That
distinction matters as soon as something downstream needs to reconstruct a
tree, not just a yes/no answer.

---

## 2. Binary Subtree Representation (BSR)

Rather than building a Shared Packed Parse Forest (SPPF) *during* recognition
(which is what classical generalized parsers do, at a real memory cost for
highly ambiguous grammars), this implementation follows:

> E. Scott, A. Johnstone, L. van Binsbergen, *"Derivation representation
> using binary subtree sets,"* Science of Computer Programming 175 (2019),
> §3.1–3.2.

BSR (`BSR.swift`) records derivation *steps*, not trees. Each entry is a
4-tuple `(slot, i, k, j)` — either:

- **`snode (α, i, k, j)`** — the symbol sequence `α` (a partial left-spine of
  some production) matched `i..j` with split point `k`, or
- **`pnode (X ::= γ, i, k, j)`** — production `X ::= γ` is *complete*,
  spanning `i..j`, with `γ`'s last symbol starting at `k`.

`EarleyParser.bsrAdd(item:leftExtent:pivot:rightExtent:)` is the single
function that decides, for an advancing item `X ::= α·β`, whether an entry
is needed at all:

```swift
private func bsrAdd(item: ParseStateItem, leftExtent: Int, pivot: Int, rightExtent: Int) -> BSR? {
    let (alpha, beta, _) = item.split

    // Nothing to record when the dot is at the very start (α is empty).
    guard !alpha.isEmpty else { return nil }

    if beta.isEmpty {                                   // β = ε — completed rule
        return BSR(node: .pnode(...), leftExtent: leftExtent, pivot: pivot, rightExtent: rightExtent)
    }
    if alpha.count > 1 {                                // |α| > 1 — intermediate
        return BSR(node: .snode(...), leftExtent: leftExtent, pivot: pivot, rightExtent: rightExtent)
    }
    return nil                                           // |α| = 1, β ≠ ε — nothing needed
}
```

The `guard !alpha.isEmpty` line is doing real work, and it is **correct**,
not a bug: per Scott et al. §3.1, a derivation step is only meaningful if
something was actually matched before the dot. If `α = ε` there is no split
to record — there's nothing on the left of a binary subtree whose right side
is everything. This is the formal justification for why **ϒ (the BSR set)
contains no entry for a direct epsilon production**, ever, by design.

The cost of that correctness is that ϒ is *not* a complete inventory of
"what happened" — it is a complete inventory of "what was *non-trivially*
derived". A direct ε-completion is real (it did happen, at a specific
position, via a specific production) but leaves no fingerprint in ϒ. Every
later stage that wants to reconstruct a full forest/tree has to know this
and compensate — see §4.

### A dead branch in `complete()`

`complete()` contains a second call site for `bsrAdd`, explicitly aimed at
epsilon rules:

```swift
// Special rule for ε rules: record a zero-width derivation at the current position.
if item.production.rule.isNullable {
    if let bsrItem = bsrAdd(item: item, leftExtent: currentIndex, pivot: currentIndex, rightExtent: currentIndex) {
        bsr.insert(bsrItem)
    }
}
```

This looks like it should be the fix for the gap just described — but trace
it through and it never fires. `item` here is a freshly-completed item whose
`productionPosition` is still `0` (an epsilon-rule item is never advanced by
`scan()`, since an epsilon terminal can never equal a real input token — see
§3 below). `item.split` computes `alpha = rule.prefix(productionPosition)`,
which is `rule.prefix(0) == []` regardless of what `rule` actually contains.
So `bsrAdd` hits `guard !alpha.isEmpty` and returns `nil` — every time, for
every grammar. This block is harmless, but it is dead code: it cannot ever
insert an entry for the case its comment describes. It's left in place here
deliberately, as a marker of *where* someone reasonably expected the fix to
live, and *why* it doesn't work there — the real fix has to live downstream,
where it's actually possible to know "this is fine, X is nullable" rather
than "there's nothing here."

---

## 3. Why epsilon is hard, mechanically (not just conceptually)

Two implementation details compound the formal gap in §2.

**(a) Epsilon-RHS representation — historical problem, now resolved.**
Previously, a production written `A ::= ε` in BNF was *not* normalized to
`rule == []` by the `Grammar` package's `StandardForm` rewrite: it produced
`rule == [.terminal(.meta(.eps))]`, a **one-element** array. This caused
several inconsistencies that propagated throughout the Earley parser:

- `Production.isNullable` and `Array<Symbol>.isNullable` both had to treat
  `[]` *and* `[.terminal(.meta(.eps))]` as nullable.
- `Symbol.isEpsilon` existed as a single-symbol predicate for the same check.
- A naive `rule.isEmpty` check — the obvious test — was **false** for the
  common case, since the rule was `[ε]`, not `[]`. This trap caused a bug
  in `Hygiene.eliminateEmpty` in the `Grammar` package, and was the root
  cause of the `expandSymbolNode` bug described in §4.

**This ambiguity is now eliminated.** `Production.init` in the `Grammar`
package normalizes every epsilon production to `rule == []` at creation: it
filters out any symbol for which `Symbol.isEpsilon` is true before storing
the rule. The epsilon meta character (`ε`, `λ`, etc.) is purely a rendering
concern — it is applied by `Grammar.bnf`/`ebnf`/`wsn` and `Production.description`
when producing human-readable output, but it is never part of stored data.

**The resulting invariant throughout this codebase:** `rule.isEmpty` is the
correct and complete test for "this production derives the empty string".
`Production.isNullable`, `Array<Symbol>.isNullable`, and `Symbol.isEpsilon`
remain available but are now redundant for the direct epsilon case; their
utility is in the *derived nullable* case — a non-terminal whose every rule
contains only nullable non-terminals.

**(b) `ParseStateItem` papers over (a) — two checks now removed.**
The old `isCompleted` and `nextSymbol` each contained a pattern-match that
treated a bare epsilon terminal as if the dot was at the end of the rule.
With `rule == []` as the canonical form, those branches were dead code: a
`rule` can never contain `.terminal(.meta(.eps))` or `.terminal(.string(""))`
after normalization. Both have been removed; `isCompleted` is now simply:

```swift
var isCompleted: Bool {
    return !production.rule.indices.contains(productionPosition)
}
```

For an epsilon production, `rule == []`, so `rule.indices` is empty, and
`contains(0)` is immediately false — `isCompleted` is true from the first
position. No secondary check required.


---

## 4. BSR → SPPF: `extractSPPF`, and the bug

`extractSPPF(tokens:bsr:)` builds an `SPPFGraph` top-down from ϒ:

1. Create the root `Symbol(S, 0, n)`.
2. Repeat: for every *extendable* node (a `.symbol` or `.intermediate` node
   with no children yet), expand it:
   - **`expandSymbolNode`** — for a `Symbol(X, i, j)`, find every
     `pnode (X ::= γ, i, k, j) ∈ ϒ` and call `makePackedNode` for each.
   - **`expandIntermediateNode`** — for an intermediate `(X ::= α·δ, i, j)`,
     either use `pivot = i` directly (if `|α| = 1`, per §2's "nothing
     needed" case) or look up `snode (α, i, k, j) ∈ ϒ` (if `|α| > 1`).
   - **`makePackedNode`** — attaches the packed node's left/right children
     (leaves, symbols, or a shorter intermediate), recursing the dot one
     step left each time.
3. `graph.cleanup()` then computes *productivity*: a `.leaf` is always
   productive; a `.symbol`/`.intermediate` is productive iff it has at least
   one productive child; a `.packed` node is productive iff *all* of its
   children are productive. Anything left unproductive — and everything
   reachable only through it — is pruned.

This is sound *given a complete ϒ*. But §2 established that ϒ is
incomplete by design for direct epsilon productions. So: take a nullable
`A`, reached as `Symbol(A, i, i)` (e.g. the right child of the packed node
for `A ::= a·A` once `a` is consumed). `expandSymbolNode` searches ϒ for a
`pnode` matching `(A, i, i)` — finds none, for exactly the reasons in §2 —
and does nothing. `Symbol(A, i, i)` is left with **zero children**.

`cleanup()` cannot tell the difference between "no children because this
derivation is invalid" and "no children because the one production that
justifies this node is a direct epsilon rule that ϒ never recorded." It
treats both as unproductive. Once `Symbol(A, i, i)` is unproductive, so is
the packed node above it (needs *all* children productive), so is
`Symbol(A, i, j)` above that, and so on — the unproductivity propagates all
the way to the root. The *entire* graph for an otherwise perfectly valid
parse gets pruned, `result.sppfGraph` ends up empty of any tree, and
`TreeBuilder.syntaxTree(for:)` throws `.unmatchedPattern` — even though the
recognizer chart proved the string was in the language.

This is precisely the failure observed on Scott & Johnstone's grammar Γ1
(`S ::= A S b | a`, `A ::= a A | ε`) on input `a a b`: `Symbol(A, 1, 1)`
(the nested, nullable `A` inside `A ::= a A`) had no BSR entry, was pruned,
and took the root down with it.

### The fix

`expandSymbolNode` now recognizes this exact shape — an extendable
`Symbol(X, i, i)` with `i == j` — as a case ϒ is known to never cover, and
synthesizes the missing derivation directly from the grammar instead of
looking it up:

```swift
if leftExtent == rightExtent {
    let epsilonProductions = grammar.productions.filter {
        $0.goal.name == label && $0.rule.isEmpty
    }
    for production in epsilonProductions {
        makePackedNode(
            label: NodeLabel(goal: production.goal, symbols: production.rule, position: 0),
            leftExtent: leftExtent, pivot: leftExtent, rightExtent: rightExtent,
            parent: node, in: graph, bsr: bsr
        )
    }
}
```

Two things make this correct:

- It uses `rule.isEmpty` — which, after Grammar's normalization, is the
  exact and sufficient test for "this production derives the empty string".
  An earlier version of this fix used `Production.isNullable` as a belt-and-
  suspenders measure when `rule == [.terminal(.meta(.eps))]` was still a
  possibility; that is no longer needed.
- It passes `position: 0` to the synthesized `NodeLabel`. Since
  `symbols.prefix(0) == []` regardless of what `symbols` actually contains,
  this unconditionally hits `makePackedNode`'s existing `alpha.isEmpty`
  branch — which already existed, already attached a single epsilon leaf
  correctly, and was simply unreachable before, because nothing had ever
  called `makePackedNode` with an empty-`α` label (no such `pnode` ever
  came out of ϒ). The fix doesn't invent new tree-shape logic; it wires up
  a path to logic that was already sitting there, waiting for a caller.

---

## 5. Lessons for the rest of the pipeline

The common thread across §2–§4 is: **ϒ is a sound but incomplete record of
derivations, and "incomplete" specifically means "silent about direct
epsilon completions."** Every consumer of ϒ has to treat a nullable symbol
with an empty span as a case to *construct from the grammar*, never a case
to *look up*. Concretely, for anyone extending this pipeline (RNGLR/GLR's
SPPF sharing, the CYK BSR/SPPF path, future incremental or partial parsing):

- Don't add a "does ϒ have an entry for this empty span?" check without also
  adding the synthesize-from-`rule.isEmpty` fallback — the absence of an
  entry is expected, not an error condition, for exactly this one shape.
- Always test nullable handling with at least: (1) a directly-nullable
  symbol used as the *only* symbol consumed by a production (covered by Γ1
  above), and (2) a chain of two or more nullable non-terminals composed in
  one production (`X ::= Y Z`, both nullable) — the recognizer's own
  Completer mechanism happens to produce a real `pnode` for the *composed*
  case (because the second nullable symbol's recognition is what triggers
  `complete()`'s normal, non-special-cased path), so it is not currently
  known to be broken, but it has not been traced as carefully as the direct
  case and is worth a dedicated regression test.
- **`rule.isEmpty` is now the correct and complete test for "is this an
  epsilon production"** — the `Grammar` package's `Production.init`
  normalizes epsilon away at construction time. `Production.isNullable`,
  `Array<Symbol>.isNullable`, and `Symbol.isEpsilon` are still the right
  tools for the *derived nullable* case (all rules of a non-terminal
  contain only nullable non-terminals), but for a direct epsilon production,
  `rule.isEmpty` is exact. The trap that caused the `Hygiene.eliminateEmpty`
  bug and the `expandSymbolNode` bug documented here — reaching for
  `rule.isEmpty` when the rule was `[.terminal(.meta(.eps))]` — is
  structurally prevented now.
- The dead branch in `complete()` (§2) and the formerly-dead `alpha.isEmpty`
  branch in `makePackedNode` (§4, now reachable) are both worth keeping —
  they're small, correctly-reasoned pieces of logic for a case that's easy
  to special-case in the wrong layer. Removing them would just mean
  re-discovering the same need later.
---

## 6. References

- J. Earley, *"An Efficient Context-Free Parsing Algorithm,"* Communications
  of the ACM 13(2), 1970.
- J. Aycock, R. N. Horspool, *"Practical Earley Parsing,"* The Computer
  Journal 45(6), 2002. (Nullable-symbol/immediate-completion fix used in
  `predict()`.)
- E. Scott, A. Johnstone, L. van Binsbergen, *"Derivation representation
  using binary subtree sets,"* Science of Computer Programming 175 (2019),
  63–84. (BSR formalism; §3.1 `bsrAdd` rules, §3.2 BSR→SPPF construction.)
- E. Scott, A. Johnstone, *"Table traversing parsers,"* 2026. (Example
  grammar Γ1 used as the regression case throughout this document.)
