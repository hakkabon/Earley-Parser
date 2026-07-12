//
//  EarleyParser.swift
//  Earley-Parser
//
//  Created by Ulf Akerstedt-Inoue on 2023/10/22.
//  Copyright © 2015 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import OSLog

/// A parser implementation modelled after the Earley algorithm.
/// This implementation is almost literally taken from Grune & Jacobs [3] as described
/// in their book Parsing Techniques, A Practical Guide.
///
/// BSR addition following Scott & Johnstone algorithm
/// E. Scott et al., Science of Computer Programming 175 (2019) 63–84, pp. 76
///
/// [1] Earley, Jay (1970), "An efficient context-free parsing algorithm" (PDF), Communications of the ACM,
///     13 (2): 94–102, doi:10.1145/362007.362035
/// [2] Leo, Joop M. I. M. (1991), "A general context-free parsing algorithm running in linear time on every
///     LR(k) grammar without using lookahead", Theoretical Computer Science, 82 (1): 165–176,
///     doi:10.1016/0304-3975(91)90180-A, MR 1112117
/// [3] Parsing Techniques - Second Edition, Dick Grune and Ceriel J.H. Jacobs
///     VU University Amsterdam, The Netherlands. Published (2008) by Springer US, ISBN 978-1-4419-1901-4.
/// [4] Aycock, R.N. Horspool, Practical Earley parsing, Comput. J. 45 (6) (2002) 620–630.
/// [5] Scott, Elizabeth (April 1, 2008). "SPPF-Style Parsing From Earley Recognizers".
///     Electronic Notes in Theoretical Computer Science. 203 (2): 53–67. doi:10.1016/j.entcs.2008.03.044
/// [6] E. Scott, A. Johnstone, L. van Binsbergen, Derivation representation using binary subtree sets,
///     Sci. Comput. Program., 175 (2019), pp. 63-84, 10.1016/j.scico.2019.01.008
///
/// The Earley algorithm creates a syntax tree in O(n³) worst case run time.
/// For unambiguous grammars, the run time is O(n²).
/// For almost all LR(k) grammars, the run time is O(n).
/// Best performance can be achieved with left recursive grammars.
///
/// For ambiguous grammars, the runtime for parses may increase,
/// as some expressions have exponentially many possible parse trees depending on expression length.
/// This exponential growth can be avoided by only generating a single parse tree with `syntaxTree(for:)`.
///
/// For unambiguous grammars, the Earley parser performs better than the CYK parser.
public struct EarleyParser {
	
	/// The grammar recognized by the parser
    public let grammar: Grammar
	
	/// All non terminals which have productions which can produce an empty string
    private var nullableNonTerminals: Set<NonTerminal> {
        return grammar.nullableNonTerminals
    }

	/// Generates an earley parser for the given grammar.
	///
	/// Creates a syntax tree in O(n^3) worst case run time.
	/// For unambiguous grammars, the run time is O(n^2).
	/// For almost all LR(k) grammars, the run time is O(n).
	/// Best performance can be achieved with left recursive grammars.
	public init(grammar: Grammar) {
		self.grammar = grammar
	}
	
    /// This function is called when a non-terminal symbol Y is encountered to the right of the dot
    /// in an item (X ::= α·Yβ, i) in chart set S[j]).
    /// - X ::= α·Yβ is the production rule with the dot before the non-terminal Y.
    /// - i is the index of the start of the substring matched so far for this rule.
    /// - j is the current position in the input string.
    ///
    /// The Predictor performs the following actions:
    /// 1. Prediction: For every production rule Y ::= γ in the grammar, it adds a new item (Y ::= ·γ, j)
    /// to the current chart set S[j] (and to a worklist R[j] if it's not already present. The dot is
    /// at the beginning, anticipating that Y could start at this position j.
    /// 2. Immediate Completion: The pseudocode has an extra loop that appears to handle nullable non-terminals.
    /// For every already completed item (Y ::= δ·, j) in S[j], it immediately performs a Completer-like
    /// action by adding (X ::= αY·β, i) to S[j] and R[j]. This efficiently handles non-terminals
    /// that can derive an empty string ε.
    /// 3. BSR Addition (for nullables): It calls bsrAdd(X ::= αY·β, i, j, j). This records a derivation step.
    /// The span is (j, j), indicating that the non-terminal Y derived the empty string at position j
    private func predict(item: ParseStateItem, currentIndex: Int, productions: [NonTerminal: [Production]],  allStates: [Set<ParseStateItem>]) -> ([ParseStateItem], Set<BSR>) {
        var bsr = Set<BSR>()

        guard
			let symbol = item.nextSymbol,
			case .nonTerminal(let nonTerminal) = symbol
		else {
			return ([],[])
		}
		// Create new parse states for each non terminal which has been reached and filter out every known state
        // for all productions Y ::= γ {
        //    if (Y ::= ·γ, j) ∉ S[j] {
        //       add (Y ::= ·γ, j) to S[j] and to R[j]
        //    } ...
		var addedItems = productions[nonTerminal, default: []].map {
			ParseStateItem(production: $0, productionPosition: 0, startTokenIndex: currentIndex)
		}

		// If a nullable symbol was added, advance the production that added this symbol
        // due to Aycock and Horspool 
		if nullableNonTerminals.contains(nonTerminal) {
            // add X ::= αY· β  to S[j] and to R[j]
            addedItems.append(item.advanced())

            // bsrAdd(X ::= αY· β, i, j, j)
            if let bsrItem = bsrAdd(item: item.advanced(),              // X ::= αY· β
                                    leftExtent: item.startTokenIndex,   // i
                                    pivot: currentIndex,                // j
                                    rightExtent: currentIndex) {        // j
                bsr.insert(bsrItem)
            }
        }
        
        Logger.earley.trace("predict[\(currentIndex)]: \(addedItems)")
        Logger.bsr.trace("bsr predict: \(bsr)")
        return (addedItems, bsr)
	}
	
	/// Finds productions which produce a non terminal and checks,
	/// if the expected terminal matches the observed one.
    ///
    /// Scanner((X ::= α· bβ, i), j)
    /// This function is called to match a terminal symbol b.
    /// - X ::= α·bβ is the production rule.
    /// - i is the start index of the item.
    /// - j is the current position in the input string.
    /// The Scanner performs the following actions:
    func scan(state: Set<ParseStateItem>, token: Terminal, currentIndex: Int) -> (Set<ParseStateItem>, Set<BSR>) {
        var bsr = Set<BSR>()
		let items = state.reduce(into: Set<ParseStateItem>()) { partialResult, item in
			guard
                // Check that the next symbol of the production is a terminal and
                // and that it matches the current token a[j+1] as follows:
                // b == a[j+1]
				let next = item.nextSymbol,
				case .terminal(let terminal) = next,
                // `terminal` is the grammar's expected symbol (a literal, character
                // range, regex, or list — already resolved from any `lexical { }`
                // declaration by StandardNotation); `token` is the concrete lexeme
                // the Lexer produced. Terminal.== is strict structural equality and
                // does not do this kind of pattern-vs-lexeme matching; matches(_:)
                // is the asymmetric check meant for exactly this call site.
				terminal.matches(token)
			else {
				return
			}
            
            // Create a new state with an advanced production position.
            // add (X ::= αb · β, i) to S[j+1] and to R[j+1]
            partialResult.insert(item.advanced())

            // Add BSR entry for scanner
            // bsrAdd(X ::= αb · β, i, j, j + 1)
            if let bsrItem = bsrAdd(item: item.advanced(),
                                    leftExtent: item.startTokenIndex,       // i
                                    pivot: currentIndex,                    // j
                                    rightExtent: currentIndex + 1)          // j+1
            {
                bsr.insert(bsrItem)
            }
		}
        Logger.earley.trace("scan[\(currentIndex)]: \(items)")
        Logger.bsr.trace("bsr scan: \(bsr)")
        return (items, bsr)
	}
	
	/// Processes completed items.
    ///
    /// Completer((X ::= α·, i), j)
    /// This function is called when a completed item (X ::= α·, i) is found in chart set S[j].
    /// - X ::= α· is the completed production rule. i is the start index of the substring derived by X.
    /// - j is the end index of the substring derived by X.
    /// The Completer performs the following actions:
	private func complete(item: ParseStateItem, currentIndex: Int, allStates: [Set<ParseStateItem>]) -> ([ParseStateItem], Set<BSR>) {
		guard item.isCompleted else {
			return ([], [])
		}
		
        // find all (Y ::= δ·Xμ, k) ∈ S[i]
        // where i = item.startTokenIndex
		let stateItems = (allStates.indices.contains(item.startTokenIndex) ? allStates[item.startTokenIndex] : []).filter { stateItem in
            !stateItem.isCompleted && stateItem.nextSymbol == Symbol.nonTerminal(item.production.goal)
        }

        // advance items to get (Y ::= δX·μ, k)
        let advancedItems = stateItems.map { $0.advanced() }
        
        // Add BSR entry for each advancement.
        // Per Scott et al.: bsrAdd(Y ::= δX·μ, k, i, j)
        //   leftExtent = k  (start of the waiting item Y ::= δ·Xμ)
        //   pivot      = i  (start of the completed item X ::= α·, i.e. item.startTokenIndex)
        //   rightExtent= j  (current position)
        var bsr = Set<BSR>()
        for (stateItem, advancedItem) in zip(stateItems, advancedItems) {
            if let bsrItem = bsrAdd(item: advancedItem,                     // Y ::= δX·μ
                                    leftExtent: stateItem.startTokenIndex,  // k
                                    pivot: item.startTokenIndex,            // i
                                    rightExtent: currentIndex) {            // j
                bsr.insert(bsrItem)
            }
        }
        
        // Special rule for ε productions: record a zero-width derivation at the current
        // position. With Grammar's normalization, an epsilon production is always
        // `rule == []`, so `rule.isEmpty` is the exact test — no epsilon terminal
        // symbol can appear inside a rule.
        if item.production.rule.isEmpty {
            if let bsrItem = bsrAdd(item: item,
                                    leftExtent: currentIndex,   // j
                                    pivot: currentIndex,        // j
                                    rightExtent: currentIndex) {// j
                bsr.insert(bsrItem)
            }
        }
        
        Logger.earley.trace("complete[\(currentIndex)]: \(advancedItems)")
        Logger.bsr.trace("bsr complete: \(bsr)")
        return (advancedItems, bsr)
	}

    // The Completer/Predictor Loop
    // `currentIndex` is the index of the state currently being built (i.e. stateCollection.count after appending).
    func processState(productions: [NonTerminal: [Production]], allStates: [Set<ParseStateItem>], knownItems: Set<ParseStateItem>, newItems: Set<ParseStateItem>, currentIndex: Int) -> (Set<ParseStateItem>, Set<BSR>) {
		var addedItems: Set<ParseStateItem> = newItems
		var knownItems: Set<ParseStateItem> = knownItems
        var bsrSet = Set<BSR>()

		repeat {
			addedItems = addedItems.reduce(into: Set<ParseStateItem>()) { (addedItems, item) in
				switch item.nextSymbol {
				case .none:
                    Logger.earley.trace("process state: next symbol \(item) is nil")
                    let (completed, bsr) = complete(item: item, currentIndex: currentIndex, allStates: allStates)
					addedItems.reserveCapacity(addedItems.count + completed.count)
					addedItems.formUnion(completed)
                    bsrSet.formUnion(bsr)
				case .some(.terminal):
                    Logger.earley.trace("process state: next symbol \(item) is a terminal")
					break
				case .some(.nonTerminal):
                    Logger.earley.trace("process state: next symbol \(item) is a nonterminal")
					let (predicted, bsr) = predict(item: item, currentIndex: currentIndex, productions: productions, allStates: allStates)
					addedItems.reserveCapacity(addedItems.count + predicted.count)
					addedItems.formUnion(predicted)
                    bsrSet.formUnion(bsr)
                case .some(let .metaSymbol(meta)):
                    // meta symbols like { [ ( } ] ) and | should not be present
                    fatalError("meta symbol \(meta) found in earley item")
				}
			}.subtracting(knownItems)

			knownItems.reserveCapacity(addedItems.count + knownItems.count)
			knownItems.formUnion(addedItems)

		} while !addedItems.isEmpty

		return (knownItems, bsrSet)
	}
}

// MARK: - BSR set generating Earley parser

extension EarleyParser {
    
    /// Constructs and adds a BSR tuple to the set ϒ, following Scott et al. (2019) Algorithm 1.
    /// Note: Do not conflate 'generating of BSR' with with 'SPPF graph extraction from BSR'.
    /// There were some confusing comments written here earlier.
    ///
    /// - Parameters:
    ///   - item:        The Earley item after the dot has been advanced (X ::= α·β).
    ///   - leftExtent:  i — start position of the rule X.
    ///   - pivot:       k — boundary between the left and right children.
    ///   - rightExtent: j — end position of the current derivation step.
    private func bsrAdd(item: ParseStateItem, leftExtent: Int, pivot: Int, rightExtent: Int) -> BSR? {
        
        // Get the symbols before and after the dot: X ::= α·β
        let (alpha, beta, _) = item.split

        // Nothing to record when the dot is at the very start (α is empty).
        guard !alpha.isEmpty else { return nil }

        // Case 1: β = ε — completed rule.
        // Insert pnode (X ::= αβ, i, k, j) representing the full derivation of X.
        if beta.isEmpty {
            let bsr = BSR(
                node: .pnode(ProductionNode(goal: item.production.goal, symbols: item.production.rule)),
                leftExtent: leftExtent,
                pivot: pivot,
                rightExtent: rightExtent
            )
            Logger.bsr.trace("add BSR pnode \(bsr) [β=ε, complete]")
            return bsr
        }

        // Case 2: |α| > 1 — intermediate derivation.
        // Insert snode (α, i, k, j) to represent the partial left spine.
        if alpha.count > 1 {
            let bsr = BSR(
                node: .snode(SymbolNode(symbols: alpha)),
                leftExtent: leftExtent,
                pivot: pivot,
                rightExtent: rightExtent
            )
            Logger.bsr.trace("add BSR snode \(bsr) [|α|>1, intermediate]")
            return bsr
        }
        return nil
    }
}
