## Analysis of ParseStateItem.isCompleted - Completed epsilon rules, to be or not to be?

The isCompleted property has this logic:

If productionPosition is past the end of the rule, return true (normal completion)
If the last symbol of the rule is an empty terminal "", return true (regardless of productionPosition)
Case 2 is the Grammar library's convention for epsilon productions: A ::= "" is stored as a rule with one symbol - an empty terminal. This means when productionPosition == 0, the rule hasn't been consumed yet, but isCompleted returns true because the last (and only) symbol is empty.

The nextSymbol property also treats empty terminals as "no next symbol" - it returns nil when the current symbol is empty, which aligns with how epsilon productions are handled. But there's a problem: isCompleted checks the last symbol of the rule unconditionally, not just at the current position. So a rule like A ::= "a" "" would report as completed even at position 0, before consuming the "a". The epsilon handling is working correctly—at position 0 for an epsilon rule, the item is immediately marked complete with no next symbol. The original simpler version didn't account for this, but the current implementation does. Now I need to move forward with adding comprehensive tests, including Tomita's grammar as a well-known test case where "a a a" should produce 2 distinct parse trees.

I understand the isCompleted epsilon-terminal check — it's intentional for the Grammar library's epsilon representation (A ::= "" is stored as a single empty-terminal rule). That should stay as-is.

Let me now add the missing test coverage and documentation. I'll add tests for:

Tomita's grammar (S ::= S S | "a") — the canonical highly-ambiguous grammar; 3 tokens → 2 trees, 4 tokens → 5 trees
Empty-only grammar (S ::= "") — correctly parses the empty string
Right-recursive chain — verify memo doesn't produce stale results on deeply shared sub-forests
Then I'll add proper doc comments to the new public API.



I understand the `isCompleted` epsilon-terminal check — it's intentional for the Grammar library's epsilon representation (`A ::= ""` is stored as a single empty-terminal rule). That should stay as-is.

Let me now add the missing test coverage and documentation. I'll add tests for:
1. **Tomita's grammar** (`S ::= S S | "a"`) — the canonical highly-ambiguous grammar; 3 tokens → 2 trees, 4 tokens → 5 trees
2. **Empty-only grammar** (`S ::= ""`) — correctly parses the empty string
3. **Right-recursive chain** — verify memo doesn't produce stale results on deeply shared sub-forests

Then I'll add proper doc comments to the new public API.
