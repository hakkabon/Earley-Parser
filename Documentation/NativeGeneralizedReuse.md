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
accepts those identities directly. Convenience parsing without supplied
identities conservatively aligns equal prefix and suffix terminals and assigns
new identities to the changed middle.

## Phase 25: live chart execution

`EarleyIncrementalSession` records the real Earley items produced by scanner,
predictor, and completer closure. Each completed chart column retains its BSR
contribution. A token edit invalidates the actual suffix facts through the
dependency index, retains columns through the last unchanged prefix token, and
continues the normal construction loop from there. SPPF extraction consumes the
combined retained and rebuilt BSR set; differential tests compare both BSR and
the portable forest with a clean parse.

The current safe reuse frontier is a contiguous prefix. Facts beyond the first
changed token are invalidated even when later token identities converge,
because Earley item origins and forest extents are positional. Reusing shifted
suffix graphs requires an explicit extent-relocation proof and is not claimed.
