# Headless feature-history foundation

`CadDocument` owns immutable `FeatureDefinition` values. A caller supplies stable
`FeatureId` values (unique within the document); updates retain those IDs. Each
definition contains a type, deeply frozen value parameters, explicit dependency
IDs, and named semantic inputs. Input references automatically become graph
edges. Definitions contain no topology, tessellation, or camera data.

Evaluators are registered by type when creating the document. They receive only
their definition and declared dependency outputs. They should be deterministic
functions of those inputs. `setFeature`, `removeFeature`, and `replaceFeatures`
evaluate synchronously and publish definitions and one `EvaluationSnapshot`
together. Observers during evaluation see the previous complete publication.
Nested edits are rejected. Duplicate IDs reject an edit without publication.
Use `replaceFeatures` to make a batch edit in one publication.

The evaluator traverses dependencies in stable ID order. Value changes rebuild
only the changed feature and its transitive descendants. Unaffected results are
reused; reordering definitions alone does not rebuild. `rebuild(ids)` explicitly
invalidates evaluator inputs managed outside the definition. Evaluator registry
changes require a new document. Snapshot revisions count publications.

Cycle members fail with a cycle diagnostic; their descendants are blocked.
Missing dependency IDs fail their referring feature. Unknown feature types and
exceptions fail the feature, while independent features can remain valid. A
missing or ambiguous semantic input fails its consumer. Failed and blocked
features publish no current outputs. Last successful outputs are retained only
in `diagnosticOutputs`, across repeated failures. They are excluded from reference
resolution and render geometry. Recovery rebuilds descendants and clears stale
diagnostics. `evaluationOrder` includes all features (cycle members ordered by ID
within their component); `rebuiltFeatures` identifies invalidated current IDs.

An `OutputReference` names `(featureId, kind, key)`. Keys belong to the producing
feature's semantic contract, never face indices, coordinate hashes, or proximity
search. Cube supplies body `body` and planar faces `front`, `back`, `bottom`,
`top`, `left`, `right`, assigned during topology construction. Changing Cube size
or center preserves these meanings. `snapshot.resolve` reports resolved, missing,
ambiguous, or unavailable. Duplicate semantic keys are permitted to represent
unresolved naming ambiguity; the resolver never selects one candidate. Future
features that split or remove outputs must deliberately maintain or retire keys.
This foundation makes no general topological naming claim for arbitrary booleans.

Topology is copied at output capture and every consumer boundary because legacy
`Vertex` vectors remain mutable. Copies preserve shared boundary identities.
Supported copy geometry includes the existing linear/planar and circular/cylinder
primitives; unsupported types fail explicitly. Public collections are immutable.
Parameters accept finite scalars, lists, and string-keyed maps, recursively copied;
arbitrary mutable objects such as vectors are rejected.

`EvaluationSnapshot.geometry` exports copies of valid body topology only. Named
faces serve as attachment targets rather than additional render surfaces.
`SceneTessellator.buildGeometry` converts this topology into separate render data.
`CadScene` accepts it through `geometry`; `CadScenePainter` prepares render data
before painting, so paints and camera motion do not run document evaluators.
Legacy object inputs remain supported, but are built when constructing a painter.
The demo owns a document with two Cube definitions and uses its evaluated bodies.
The grid and existing cylinder remain fixed scene geometry.

Tests include a tiny dependent feature that places a half-sized Cube above a named
support face, plus a diamond graph, overlapping cycles, failure/recovery, missing
and ambiguous references, atomic publication, and mutation isolation. There are no
sketches, extrusion features, disk persistence, or history UI in this change.
