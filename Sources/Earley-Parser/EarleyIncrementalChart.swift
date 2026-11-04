import Foundation
import IncrementalParsing
import Grammar

extension EarleyParser {
    /// Stable semantic identity used to guard native chart reuse.
    public var incrementalArtifactIdentity: IncrementalArtifactIdentity {
        func frame(_ value: String) -> String { "\(value.utf8.count):\(value)" }
        let productions = grammar.productions.map {
            GrammarProductionID(goal: $0.goal, symbols: $0.rule).rawValue
        }.sorted().map(frame).joined()
        let fingerprint = "earley-grammar-v1;S\(frame(grammar.start.name));P\(frame(productions))"
        return .init(id: "earley.grammar", revision: 0, fingerprint: fingerprint)
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
    public let factDependencies: Set<EarleyChartFactID>

    public init(
        id: EarleyChartFactID,
        value: Value,
        tokenDependencies: Set<EarleyTokenIdentity> = [],
        factDependencies: Set<EarleyChartFactID> = []
    ) {
        self.id = id
        self.value = value
        self.tokenDependencies = tokenDependencies
        self.factDependencies = factDependencies
    }
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
        var removed = Set(facts.values.lazy
            .filter { !$0.tokenDependencies.isDisjoint(with: changedTokens) }
            .map(\.id))
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
