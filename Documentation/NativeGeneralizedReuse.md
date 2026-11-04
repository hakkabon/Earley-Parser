# Phase 11: Native generalized reuse

Earley chart facts are retained by stable fact identity. Scanner facts name the
stable tokens that justify them, while predictor and completer facts name the
chart facts they depend on. Changing a token removes its direct users and the
complete reverse-dependency closure. Independent facts retain their stored
values and, when those values are reference types, their object identity.

Every chart is bound to `EarleyParser.incrementalArtifactIdentity`, a stable
fingerprint of the start symbol and production multiset. Rebinding to another
grammar clears all native facts and reports `incompatibleArtifact`; no chart
state crosses grammar boundaries.

After rebuilding the invalidated closure,
`EarleyChartInvalidation.executionEvidence(rebuiltFactCount:)` reports native
chart-fact reuse through the shared Phase 9 evidence schema. Differential tests
compare the resulting fact graph and payloads with a clean reconstruction.

Stable token identity remains owned by the lexer or language kit. Earley-Parser
does not infer token continuity from offsets or lexemes.
