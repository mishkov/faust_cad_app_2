# Bounded visibility-resolved curved mesh submission

## Reference and method

The work starts at refreshed `origin/main` **193114a**, including PR #32's
selective layers/projection reuse and PR #33's full-stroke visibility, depth
bounds checks, spatial index and unoccluded mesh batching. The separate worktree
uses `codex/curved-visibility-batching`. The reference checkout is untouched.

`test/support/baseline_shaded_scene_renderer.dart` freezes the latest main
renderer's draw/mask algorithm, with optional counters. Both paths use the same
spatial-index and edge-visibility implementation; the index now also offers an
allocation-reusing bounded query for numerical clipping. The older PR #32 report
remains historical. An initial pre-pause, single-reference capture (1035 × 772, DPR 1) is recorded in
`performance/curved_visibility_fresh_baseline_macos.json`. The desktop display
configuration changed across the pause. It is not compared with the later
captures. The final comparison establishes a fresh reference at the current
viewport/DPR and pairs both implementations in one process with matching
conditions, rather than comparing separate sessions.

Native measurements use macOS profile mode with `--enable-impeller`, Apple M1,
Flutter 3.47.5 / Dart 3.13.4. The benchmark fixes viewport dimensions and DPR across
all phases and records both in the raw report. It uses the existing default
scene (grid, cylinder, two cubes) and circle/polyline partial-extrusion fixture,
including its sketch overlay. Tessellation is unchanged and built before capture.

Orbit, pan and zoom use the same shared `ViewportProfilePainter` for reference,
optimized and memory runs. Each frame follows the original six-second camera
path: target (35,25,5), distance 220, focal length 500; orbit yaw
`-0.9 + 0.8*sin(t)` and pitch `-0.5 + 0.65*sin(2*t)`, where `t=seconds*pi/3`.
Pan is `(60*sin(t),40*cos(t))`; zoom is `1+0.3*sin(t)` about viewport centre.
Each phase warms for six seconds, captures six seconds of live engine frames,
then flushes timing callbacks for two seconds. Every workload runs ABBA
(reference, optimized, optimized, reference). No other task-owned Flutter apps,
tests, analysis or memory probes run during timing capture.

UI/raster quantiles are nearest ranks over concatenated raw engine frame samples,
not averages of per-run quantiles. The combined budget rate counts a frame once
when either stage exceeds 16.7 ms. Stage timers and layer/draw counters sample
one in thirty paints, including warmup; ranges are sampled, not exhaustive.
Delivered engine frames per second do not establish input-to-display latency.
Raw vsync timestamps are included for cadence inspection. These measurements are
controlled renderer workloads, not a full application interaction benchmark.
The window stays foreground and the Mac stays unlocked. Locked-desktop trials
were discarded because macOS throttled presentation to roughly ten FPS; an
optional `VIEWPORT_WAIT_FOR_FOCUS` gate allows activation before test invariants
are captured. Accessibility inspection during a timing run is avoided.

Layer counters distinguish curved cells, planar faces, edges and sketch overlay
layers. Draw counters separately record mesh submissions, planar fills, edge
segments and erase-mask paths. `cad_draws` sums those four draw categories; it
excludes sketch path draws. `mesh_batches` counts only shared submissions;
`mesh_draws` also includes isolated fallback cells. Counts are sampled once per
thirty paints, so before/after medians can sample different camera instants.

## Implementation and ownership

- Subtract convex occluders intersected with their strictly nearer reciprocal
  depth half-plane. Use the existing conservative depth rejection and index.
  Subtraction partitions each convex fragment into disjoint outside strips;
  holes, concavity and unsupported contours retain the existing even-odd masks.
  Intersecting surfaces resolve by local depth, independent of whole-face order.
- Start with each original projected fan cell, including camera/near-plane
  clipping. Interpolate its original opaque vertex colours in screen space,
  carrying unrounded double RGBA through every cut and rounding only at submission.
  Recomputing lighting at cut points would produce a different shading field.
- Keep all depth and clipping arithmetic in `Float64List`/double precision.
  Convert positions to native float only when submitting `Vertices.raw`.
  Fan-triangulate surviving polygons, batch contiguous compatible mesh draws,
  and flush before planar or isolated-mask draws. Outlines/sketches retain their
  existing order. No unrelated `dstOut` masks share a layer.
- Bound each source cell to 32 fragments, 24 vertices per fragment, 256 queried
  candidates and 128 vertices in a supported convex occluder. Clip-vertex visits
  and device-pixel contact scans share limits of 8,192 work units per cell and
  262,144 per paint. Convexity validation is cached on projected faces and capped
  by the contour limit. Exhaustion discards the entire numerical result and
  invokes the original isolated-mask fallback; no partial result is submitted.
- Reject ambiguous source/cut edge contacts near device pixel centres with a
  conservative 1/8-physical-pixel guard. It uses the canvas scale/translation and
  current view DPR; unsupported shear/perspective transforms retain masks.
  Mathematically disjoint masks can still affect native AA fringes, so they also
  participate in this check. The guard is bounded by the same work budget.
- Reuse roughly 130 KiB of UI-isolate numerical scratch (fragment arrays and a
  4,095-vertex submission buffer). It stores no face/model/camera references
  across paints. Candidate lists clear in `finally`; the renderer releases its
  camera-point map and invalidates scratch results even when drawing throws.
  Native vertex wrappers are explicitly disposed after recording, while display
  lists own their captured data. Buffer reuse/disposal is covered by an image test.
- Rebuild projections, index, convexity and visibility after every paint.
  Geometry edits, camera changes, viewport resizing and DPR changes cannot reuse
  an earlier visibility solution. Tessellation caching remains unchanged.

## Image validation

Direct hard clipping initially produced isolated high-contrast pixel changes;
those paths were rejected. A shared resolved-mesh layer was also rejected after
native image tests showed coverage changes. The final path adds no shared masks
or new mesh layers.

Impeller MSAA differs from headless Skia. Separately resolving each reference
cell into an offscreen layer leaves light seams on some mesh boundaries; batching
can make these pixels darker and more opaque. The image comparison therefore
checks these changes explicitly instead of claiming byte equality: maximum channel
error 32/255, maximum brightening 4/255, and every pixel with error above four
must be within one physical pixel of an original projected mesh-cell edge.
The changed area stays below 0.5%. Interior changes and new bright holes do not
receive the relaxed AA-seam tolerance. Existing selection comparisons remain
at two units and reversed object order remains byte-identical.

The final 36 native image pairs pass with maximum channel delta **27/255**,
maximum brightening **3/255**, and **zero** off-boundary pixels exceeding four
units. The maximum changed area is **0.0078125%**. The 36 headless pairs have
maximum delta **1/255**, zero brightening, changed area at most **0.0006511%**,
and zero off-boundary exceptions. Exact per-image changed areas and errors are retained in
`performance/curved_visibility_images_{native,headless}.json`.

## Memory investigation

Memory is measured in separate profile processes at 560 × 600 logical pixels,
DPR 2, with the same orbit path. The reference runs ten cycles per scene; the
optimized path runs twenty to test whether repetition plateaus. The camera stops
for external VM/RSS/`vmmap` probes. Initial, resting and unmounted probes request
GC; rotation cycles do not. Probe latency is excluded from the six-second path.

| Sample (MiB) | Reference RSS | Optimized RSS | Reference live Dart after GC | Optimized live Dart after GC |
| --- | ---: | ---: | ---: | ---: |
| Blank viewport | 142.8 | 142.5 | 6.405 | 6.419 |
| Default scene idle | 182.5 | 187.2 | 6.552 | 6.688 |
| Default scene resting after cycles | 235.8 | 233.9 | 6.552 | 6.687 |
| Partial extrusion resting after cycles | 245.8 | 245.7 | 6.662 | 6.798 |
| Viewport cleared and unmounted | 201.9 | 203.6 | 6.450 | 6.585 |

Optimized default RSS at cycles 1/10/20 is 202.4/229.2/228.0 MiB; partial
extrusion is 252.0/252.2/253.5 MiB. The final five cycles range 228.0–229.7
and 253.5–254.4 MiB respectively. Both processes peak around 256 MiB RSS.
There is no measured process-memory reduction. The optimized path reaches a
plateau over these repeated paths; this is bounded evidence, not a guarantee
about every long application session.

Transient Dart usage reaches about 12 MiB and returns to about 6.8 MiB after GC.
Retained capacity remains 9–14 MiB. After-GC live `ProjectedFace`,
`ProjectedFaceIndex`, `ShadedSceneRenderer` and `Vertices` counts are zero. The
optimized process retains exactly one visibility workspace and one mesh batch;
its roughly 0.135 MiB higher live heap agrees with the bounded numerical buffers.
Model vector counts return from 1,309/2,229 for the two fixtures to 145 when
unmounted. No projected frame or camera history appears in these snapshots.

Native mappings account for much more growth than Dart objects. In the optimized
process, `vmmap` physical footprint grows from 121.9 MiB blank to 371.3/373.2 MiB
at scene rest, then falls to 143.5 MiB after unmounting. Resident IOAccelerator
graphics mappings grow from 7.3 to 160.4/164.1 MiB and return to 9.2 MiB. Native
malloc at default rest has 43.6 MiB resident versus 24.6 MiB allocated. IOSurface
mappings also differ between independent runs (44.1 versus 58.8 MiB), so these
are not an exact per-renderer accounting. Physical footprint and process RSS are
different OS metrics and should not be subtracted from one another.

The observed release on unmount and plateau are consistent with graphics resource
pools and allocator high-water capacity, rather than a growing Dart-frame leak.
The installed Impeller `RenderTargetCache` also keeps reusable targets for four
rendered frames; a stationary viewport does not continuously age those entries.
This is an attribution inference from source and mappings, not a measured identity
for every native allocation. Raw VM/RSS samples and sanitized native summaries
are in `performance/curved_visibility_memory_{baseline,optimized,summary}.json`.

## Frame measurements

Final foreground capture: **560 × 600 logical pixels, DPR 2**, 24 phases, two
captures per implementation and workload (approximately twelve captured seconds
per row). All phases passed. Raw frame samples and the generated summary are in
`performance/curved_visibility_frames_macos.json` and
`performance/curved_visibility_summary_macos.json`.

| Workload | Mode | Frames | UI p50 / p95 / p99 (ms) | Raster p50 / p95 / p99 (ms) | UI >16.7 ms | Raster >16.7 ms | Either >16.7 ms | Frames/s |
| --- | --- | ---: | --- | --- | ---: | ---: | ---: | ---: |
| default orbit | reference | 499 | 9.90 / 11.63 / 12.07 | 23.93 / 30.47 / 32.22 | 0.0% | 86.0% | 86.0% | 41.5 |
| default orbit | optimized | 528 | 11.60 / 14.10 / 15.18 | 22.35 / 29.37 / 30.92 | 0.6% | 78.8% | 78.8% | 44.0 |
| default pan | reference | 488 | 10.10 / 11.13 / 11.78 | 24.06 / 29.08 / 30.03 | 0.0% | 100.0% | 100.0% | 40.7 |
| default pan | optimized | 521 | 11.94 / 13.20 / 13.52 | 20.07 / 27.62 / 29.26 | 0.0% | 100.0% | 100.0% | 43.4 |
| default zoom | reference | 485 | 10.02 / 11.45 / 11.76 | 24.14 / 29.83 / 30.59 | 0.0% | 100.0% | 100.0% | 40.4 |
| default zoom | optimized | 523 | 11.46 / 14.07 / 17.19 | 20.59 / 26.73 / 28.44 | 1.1% | 100.0% | 100.0% | 43.5 |
| partial orbit | reference | 342 | 15.93 / 20.89 / 29.11 | 34.22 / 43.12 / 47.35 | 33.9% | 100.0% | 100.0% | 28.5 |
| partial orbit | optimized | 370 | 18.57 / 22.62 / 23.92 | 31.89 / 38.70 / 40.26 | 73.5% | 100.0% | 100.0% | 30.8 |
| partial pan | reference | 337 | 18.19 / 21.10 / 23.48 | 34.79 / 38.86 / 40.79 | 90.2% | 100.0% | 100.0% | 28.1 |
| partial pan | optimized | 364 | 20.84 / 23.32 / 25.10 | 31.88 / 36.45 / 37.26 | 100.0% | 100.0% | 100.0% | 30.3 |
| partial zoom | reference | 334 | 17.92 / 21.23 / 23.70 | 33.79 / 40.26 / 42.85 | 75.7% | 100.0% | 100.0% | 27.8 |
| partial zoom | optimized | 359 | 20.58 / 24.93 / 26.14 | 32.16 / 36.43 / 37.15 | 100.0% | 100.0% | 100.0% | 29.9 |

The 60 FPS / p95 <14 ms / p99 <16.7 ms goal is **not achieved**. Raster p95
improves 3.6–10.4% across these workloads and delivered frame rate improves
roughly 6–8%, while UI p95 generally rises by about 2–4 ms. Default zoom also has
a 17.19 ms UI p99. Partial extrusion remains both CPU- and raster-bound. The
short paired captures characterize this machine/configuration; they are not a
cross-device guarantee.

### Layer and draw counts

Values below are sampled medians, reference → optimized. The last column gives
the sampled total-layer range, including all four layer categories.

| Workload | Curved layers | Planar layers | Edge layers | Sketch layers | Total layer range |
| --- | ---: | ---: | ---: | ---: | --- |
| default orbit | 76 → 64 | 14 → 14 | 220.5 → 183 | 0 → 0 | [138, 372] → [134, 333] |
| default pan | 128 → 103 | 13 → 13 | 146 → 149 | 0 → 0 | [259, 340] → [227, 324] |
| default zoom | 128 → 101.5 | 13 → 13 | 156 → 149 | 0 → 0 | [268, 338] → [244, 314] |
| partial orbit | 136.5 → 119.5 | 18 → 18 | 254 → 275 | 1 → 1 | [308, 483] → [342, 484] |
| partial pan | 156 → 118 | 17 → 18 | 262 → 265 | 1 → 1 | [386, 463] → [351, 438] |
| partial zoom | 154 → 118 | 18 → 17 | 254 → 254 | 1 → 1 | [402, 469] → [364, 424] |

| Workload | Mesh draws | Mask draws | CAD draws | Resolved partial cells | Visibility fallbacks |
| --- | ---: | ---: | ---: | ---: | ---: |
| default orbit | 99.5 → 94 | 4150.5 → 3691.5 | 4557 → 4004.5 | 22.5 | 105.5 |
| default pan | 128 → 120 | 4417.5 → 3807 | 4726.5 → 4104 | 23 | 105 |
| default zoom | 128 → 120 | 4038 → 3535 | 4370 → 3851 | 26 | 101.5 |
| partial orbit | 151.5 → 151 | 5235.5 → 4999.5 | 5819.5 → 5551 | 28 | 173.5 |
| partial pan | 166 → 150.5 | 5970.5 → 5267.5 | 6548 → 5758.5 | 37 | 165 |
| partial zoom | 165 → 149 | 5587 → 5052 | 6108 → 5558 | 38 | 164 |

Complete per-category min/max, mesh batch/vertex counts and numerical work
limits are in the machine-readable summary. Unchanged planar/edge/sketch
algorithms can have different sampled medians because the two frame rates visit
different points on the same timed camera path. Layer totals can therefore grow
at individual sampled orbit angles even though resolved curved cells need no
layer.

### Remaining costs

| Workload | Face recording median ms, reference → optimized | Edge recording median ms, reference → optimized |
| --- | ---: | ---: |
| default orbit | 2.68 → 4.96 | 6.12 → 5.70 |
| default pan | 3.08 → 5.44 | 5.93 → 5.95 |
| default zoom | 3.13 → 5.27 | 6.02 → 5.60 |
| partial orbit | 4.24 → 7.73 | 8.73 → 8.66 |
| partial pan | 5.41 → 8.01 | 9.82 → 9.44 |
| partial zoom | 5.28 → 7.95 | 10.11 → 9.56 |

Clipping plus the pixel-contact guard adds numerical CPU work; face recording
now costs roughly 5 ms in the default scene and 8 ms in partial extrusion. Edge
recording remains roughly 6 ms and 9–10 ms respectively. Thousands of residual
erase paths and hundreds of isolated layers still burden Impeller, especially
edge visibility and the deliberately retained difficult-cell fallbacks. Projection
is below 0.8 ms and sketch recording is about 1.0–1.2 ms in sampled medians.
Numerical work is now a material UI cost, so isolate design is a separate possible
follow-up requiring transfer/invalidation measurements. It is not included here.

## Final validation

- `dart analyze`: no issues.
- `flutter test`: **513 passed**; focused final image export: **2 passed**.
- Native macOS profile Impeller: all **three rendering tests passed** (36 image
  pairs, selection/order/resize checks, 60-step GPU orbit with button/dropdown/text
  field checks). Driver teardown also passed. The driver reports a native plugin
  detection warning; the exported timing data match all 24 timing-log records,
  and the exported image matrix contains all 36 passing comparisons.
- Paired native timing run: all **24 phases passed**, with viewport/DPR equality
  asserted across runs. Locked/throttled or accessibility-interrupted trials are
  discarded and are not included in the final JSON.
- Memory runs: **26 reference / 46 optimized samples**, complete cycles, no VM,
  GC, resume or native-map probe errors.
- This worktree's debug app: **hot reload succeeded**, **hot restart succeeded**,
  and the Dart tooling runtime error check returned **no errors**. The app was
  then quit. `git diff --check` is clean.

Focused tests cover local depth crossings and order, partial area/colour fields,
overlapping occluder unions, opaque alpha, coplanar/far cases, large-depth double
precision, holes/concavity fallback, all budget boundaries, buffer reuse/disposal,
clipped fans, subpixel fallback and frame invalidation. Existing cavity, concave,
near-plane, silhouette and selection regression coverage remains in the full
suite. Widget coverage verifies DPR changes refresh painter configuration.

## Reproduction

```sh
flutter test
dart analyze
flutter drive --profile -d macos --enable-impeller \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/rendering_impeller_test.dart
flutter drive --profile -d macos --enable-impeller \
  --dart-define=VIEWPORT_PAIRED=true \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/viewport_performance_test.dart
python3 tool/summarize_viewport_performance.py build/integration_response_data.json
python3 tool/profile_viewport_memory.py /tmp/curved-memory-baseline --baseline
python3 tool/profile_viewport_memory.py /tmp/curved-memory-optimized --cycles=20
```

Run image, timing and memory jobs in separate processes. Before timings, keep the
window foreground, the desktop unlocked, and avoid accessibility inspection.
When automatic app activation fails, add `--dart-define=VIEWPORT_WAIT_FOR_FOCUS=true`,
activate the task-owned app before capture, then call the main isolate's
`ext.cad.startBenchmark` VM-service extension after `VIEWPORT_FOCUS_READY`.

The driver overwrites `build/integration_response_data.json`; save each result
before the next run. Memory runs are separate from timings: each scene performs
ten reference or twenty optimized six-second orbit cycles and a ten-second rest. An external client
samples VM heap usage/capacity/external bytes and process RSS. Initial/rest probes
request GC; rotation cycles run without forced GC. Optional `vmmap`
summaries distinguish allocator/graphics mappings from the Dart heap. Native
mappings and RSS are not equivalent to live Dart objects or proof of a leak.
