import Foundation
import IncrementalParsing
import Grammar

extension EarleyParser {
    /// Stable semantic identity used to guard native chart reuse.
    public var incrementalArtifactIdentity: IncrementalArtifactIdentity {
        .init(
            id: "earley.grammar", revision: 0,
            fingerprint: grammar.incrementalSemanticFingerprint)
    }
}

/// Stable identity supplied by an incremental token stream.
public struct EarleyTokenIdentity: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// Stable identity of a chart fact (an Earley item at a chart position).
public struct EarleyChartFactID: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// A retained chart fact plus the exact token and chart facts that justified it.
public struct EarleyChartFact<Value> {
    public let id: EarleyChartFactID
    public let value: Value
    public let tokenDependencies: Set<EarleyTokenIdentity>
    public let productionDependencies: Set<GrammarProductionID>
    public let factDependencies: Set<EarleyChartFactID>

    public init(
        id: EarleyChartFactID,
        value: Value,
        tokenDependencies: Set<EarleyTokenIdentity> = [],
        productionDependencies: Set<GrammarProductionID> = [],
        factDependencies: Set<EarleyChartFactID> = []
    ) {
        self.id = id
        self.value = value
        self.tokenDependencies = tokenDependencies
        self.productionDependencies = productionDependencies
        self.factDependencies = factDependencies
    }
}

public struct EarleyGrammarTransition: Sendable {
    public let invalidation: EarleyChartInvalidation
    public let evidence: IncrementalExecutionEvidence
    public let appliedIncrementally: Bool
    public let convergence: GrammarEngineTransition?
}

/// Result of dependency-indexed chart invalidation.
public struct EarleyChartInvalidation: Sendable {
    public let removed: Set<EarleyChartFactID>
    public let retained: Set<EarleyChartFactID>

    /// Projects native chart invalidation into the shared evidence vocabulary
    /// after the caller has rebuilt the missing closure.
    public func executionEvidence(rebuiltFactCount: Int) -> IncrementalExecutionEvidence {
        precondition(rebuiltFactCount >= 0, "rebuilt fact count cannot be negative")
        return .init(
            strategy: .incremental,
            measurements: [.init(
                dimension: .chartFacts,
                reused: retained.count,
                rebuilt: rebuiltFactCount,
                removed: removed.count,
                strategy: "dependency-indexed-invalidation")])
    }
}

/// Engine-owned incremental Earley chart storage.
///
/// Scanner facts depend on stable token identities; predictor/completer facts
/// depend on other chart facts. An edit invalidates direct token users and the
/// transitive reverse-dependency closure, while unrelated chart regions keep
/// both their values and object storage.
public final class EarleyIncrementalChart<Value> {
    private var facts: [EarleyChartFactID: EarleyChartFact<Value>] = [:]
    private var reverseDependencies: [EarleyChartFactID: Set<EarleyChartFactID>] = [:]
    public private(set) var artifactIdentity: IncrementalArtifactIdentity?

    public init() {}
    public var count: Int { facts.count }
    public var factIDs: Set<EarleyChartFactID> { Set(facts.keys) }
    public subscript(id: EarleyChartFactID) -> EarleyChartFact<Value>? { facts[id] }

    /// Binds retained facts to the grammar/table artifact that produced them.
    /// A first binding is a full baseline; changing artifacts drops every fact
    /// and reports an explicit fallback rather than attempting unsafe reuse.
    @discardableResult
    public func bind(
        to artifact: IncrementalArtifactIdentity
    ) -> IncrementalExecutionEvidence? {
        if let current = artifactIdentity, current == artifact { return nil }
        let removed = facts.count
        removeAll()
        let wasBound = artifactIdentity != nil
        artifactIdentity = artifact
        let measurement = ReuseMeasurement(
            dimension: .chartFacts,
            reused: 0,
            rebuilt: 0,
            removed: removed,
            strategy: "dependency-indexed-invalidation")
        if wasBound {
            return .init(
                strategy: .fallback,
                fallback: .incompatibleArtifact,
                measurements: [measurement])
        }
        return .init(strategy: .full, measurements: [measurement])
    }

    public func record(_ fact: EarleyChartFact<Value>) {
        if let old = facts[fact.id] {
            for dependency in old.factDependencies {
                reverseDependencies[dependency]?.remove(fact.id)
            }
        }
        facts[fact.id] = fact
        for dependency in fact.factDependencies {
            reverseDependencies[dependency, default: []].insert(fact.id)
        }
    }

    @discardableResult
    public func invalidate(tokens changedTokens: Set<EarleyTokenIdentity>) -> EarleyChartInvalidation {
        let seeds = Set(facts.values.lazy
            .filter { !$0.tokenDependencies.isDisjoint(with: changedTokens) }
            .map(\.id))
        return invalidate(seedFacts: seeds)
    }

    /// Invalidates facts justified by changed grammar productions and their
    /// transitive chart dependents.
    @discardableResult
    public func invalidate(
        productions changedProductions: Set<GrammarProductionID>
    ) -> EarleyChartInvalidation {
        let seeds = Set(facts.values.lazy
            .filter { !$0.productionDependencies.isDisjoint(with: changedProductions) }
            .map(\.id))
        return invalidate(seedFacts: seeds)
    }

    /// Transitions retained chart storage to a new grammar artifact when the
    /// supplied delta proves its exact source and target fingerprints.
    public func transition(
        to artifact: IncrementalArtifactIdentity,
        change: GrammarChangeSet,
        rebuiltFactCount: Int = 0
    ) -> EarleyGrammarTransition {
        let sourceArtifact = artifactIdentity
        let grammarMeasurement = ReuseMeasurement(
            dimension: .grammarProductions,
            reused: change.retainedProductionIDs.count,
            rebuilt: change.addedProductionIDs.count,
            removed: change.removedProductionIDs.count,
            strategy: "structural-grammar-delta")
        guard artifactIdentity?.fingerprint == change.sourceFingerprint,
              artifact.fingerprint == change.targetFingerprint else {
            let oldIDs = Set(facts.keys)
            let wasBound = artifactIdentity != nil
            removeAll()
            artifactIdentity = artifact
            let measurement = ReuseMeasurement(
                dimension: .chartFacts, reused: 0, rebuilt: rebuiltFactCount,
                removed: oldIDs.count,
                strategy: "grammar-dependency-invalidation")
            let evidence = wasBound
                ? IncrementalExecutionEvidence(
                    strategy: .fallback,
                    fallback: .incompatibleArtifact,
                    measurements: [measurement, grammarMeasurement])
                : IncrementalExecutionEvidence(
                    strategy: .full,
                    measurements: [measurement, grammarMeasurement])
            return .init(
                invalidation: .init(removed: oldIDs, retained: []),
                evidence: evidence,
                appliedIncrementally: false,
                convergence: sourceArtifact.flatMap { source in
                    guard source != artifact, evidence.strategy == .fallback else {
                        return nil
                    }
                    return GrammarEngineTransition(
                        engineID: "earley", sourceArtifact: source,
                        targetArtifact: artifact, appliedIncrementally: false,
                        requiresRetokenization: change.requiresRetokenization,
                        evidence: evidence)
                })
        }

        let invalidation = invalidate(
            productions: change.invalidatedProductionIDSet)
        artifactIdentity = artifact
        let chartEvidence = invalidation.executionEvidence(
            rebuiltFactCount: rebuiltFactCount)
        let evidence = IncrementalExecutionEvidence(
            strategy: .incremental,
            measurements: chartEvidence.measurements + [grammarMeasurement])
        return .init(
            invalidation: invalidation,
            evidence: evidence,
            appliedIncrementally: true,
            convergence: sourceArtifact.flatMap { source in
                guard source != artifact else { return nil }
                return GrammarEngineTransition(
                    engineID: "earley", sourceArtifact: source,
                    targetArtifact: artifact, appliedIncrementally: true,
                    requiresRetokenization: change.requiresRetokenization,
                    evidence: evidence)
            })
    }

    private func invalidate(
        seedFacts: Set<EarleyChartFactID>
    ) -> EarleyChartInvalidation {
        var removed = seedFacts
        var work = Array(removed)
        while let invalid = work.popLast() {
            for dependent in reverseDependencies[invalid, default: []] where removed.insert(dependent).inserted {
                work.append(dependent)
            }
        }
        for id in removed {
            if let fact = facts.removeValue(forKey: id) {
                for dependency in fact.factDependencies {
                    reverseDependencies[dependency]?.remove(id)
                }
            }
            reverseDependencies.removeValue(forKey: id)
        }
        return .init(removed: removed, retained: Set(facts.keys))
    }

    public func removeAll() {
        facts.removeAll()
        reverseDependencies.removeAll()
    }

    public func reset() {
        removeAll()
        artifactIdentity = nil
    }
}
