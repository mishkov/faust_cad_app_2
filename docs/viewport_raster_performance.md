# Desktop viewport raster optimization

Historical report for commit `693cb28` (PR #33). For the next visibility/batching
iteration and current reference helpers, see [curved visibility](curved_visibility_performance.md).
Reproduce this older report by checking out its recorded revision.

## Baseline and scope

PR [#32](https://github.com/mishkov/faust_cad_app_2/pull/32) is present:
`f7b11cc585fbcdb9ea4fc348aefb9dce1c3588c7` is an ancestor of refreshed
`origin/main` (`e7af918ccfbc27de5b4c2fbbfc6afd6c0a151598`). Its selective
layers, conservative affine depth checks, reused projected masks, cached camera
trigonometry/clipping planes and shared point transforms remain in use.
Implementation uses the separate Codex worktree on
`codex/viewport-raster-performance`, starting from that main revision.

The supplied DevTools sample was 41 FPS average, 14.2 ms UI painting,
18.6 ms rasterization and 334 `saveLayer` calls in one selected frame. Final
before/after values below come from the matched native workload matrix.

The reference renderer and index in `test/support/baseline_*` freeze PR #32,
with optional instrumentation added equally to both renderers. The sketch
renderer is unchanged apart from optional counters. Production paints do not
enable timing or counters.

## Implementation

- Resolve full-stroke visibility with the existing spatial index and reciprocal
  depth. Include the 1-pixel stroke and a conservative 1.5-logical-pixel support
  radius around it, retaining the original outline depth bias. Cache inward unit
  half-planes for each projected convex face. Holes and concave/self-crossing
  contours use the original even-odd path and explicit boundary-distance checks.
- Draw proven visible strokes directly; discard proven fully hidden strokes.
  Reuse the same spatial query and retain only possible occluders when constructing
  masks. Contour/depth crossings and uncertain AA coverage still use the original
  isolated draw-and-erase layer. Partial strokes are deliberately conservative:
  there is no centre-line-only clipping or synthetic endpoint/cap change.
- Bound native path subtraction to at most two masks, with bounds and stroke
  midpoint rejections first. This can prove that adjacent cells jointly erase an
  entire padded stroke, or that a mesh cell is entirely hidden. It does not
  modify the original geometry of any surviving draw.
- Batch contiguous unmasked curved cells only after all local depth comparisons.
  Keep the same tessellation, fan triangles, interpolated vertex colours and
  non-AA internal mesh edges. Flush before incompatible draws. Masked survivors
  keep their own layers; unrelated `dstOut` operations never share a layer.
- Use fixed spatial buckets and discard non-overlapping cell neighbours before
  sorting query results. Retain stable original candidate order.

All projected visibility data is rebuilt per paint. Camera-point caching is
cleared between paints, so mutable geometry and viewport resizing cannot reuse
stale stroke coverage or convex boundaries.

## Native measurement method

Measured on 2026-10-14: Apple M1, macOS 26.6.2 (25G83), Flutter 3.47.5 stable,
Dart 3.13.4, macOS **profile build with Impeller enabled**, viewport 890 × 756
logical pixels at the recorded DPR 1, beside a 240-pixel Material control panel.

`viewport_performance_test.dart` runs a live-vsync ticker, with time-based camera
orbit, pan and cursor-centred zoom. It uses the default grid/cylinder/two-cube
scene and the existing partial-extrusion fixture with its sketch overlay.
Tessellation is built before each scene's capture. Each phase warms for 6 seconds,
captures a full 6-second motion cycle, then flushes timing callbacks for 2 seconds.
The ABBA sequence is baseline, optimized, optimized, baseline for every workload
in the **same native app process**. No tests, analysis or other task-owned Flutter
apps run concurrently with capture.

Real engine `FrameTiming` samples are filtered by capture vsync timestamps. UI
time is `buildDuration`, which includes framework painting; raster time is
`rasterDuration`. FPS is delivered frames / capture duration, not the reciprocal
of a paint-recording duration. Quantiles use nearest rank over concatenated raw
frames from both repeats, rather than averaging per-run percentiles. The budget
rate counts a frame once if either UI or raster exceeds 16.7 ms. Optional layer
and stage counters sample one in thirty paints, including warmup, and are excluded
from normal production painting. Layer ranges are sampled, not exhaustive maxima.

Independent-process trial captures varied substantially, including unchanged
projection work. The paired raw captures below are the final comparison; trial
captures are not used to claim achieved FPS. These are controlled renderer
workloads in a native app with real presentation, not a complete end-user input
latency or all-application-workflow benchmark. The recorded performance DPR is 1;
these timings do not establish performance at DPR 2.

## Paired native results

Each cell is **PR #32 → optimized**. Times are milliseconds. Raw samples:
[frames](performance/viewport_frames_macos.json); recomputed aggregates:
[summary](performance/viewport_summary_macos.json).

| Scene / motion | FPS | UI p95 | UI p99 | Raster p95 | Raster p99 | Either >16.7 ms |
|---|---:|---:|---:|---:|---:|---:|
| default / orbit | 39.8 → 54.4 | 17.16 → 11.46 | 18.12 → 11.84 | 33.51 → 26.19 | 35.40 → 28.55 | 100.0% → 68.6% |
| default / pan | 33.5 → 53.5 | 19.92 → 10.95 | 21.38 → 12.58 | 33.75 → 24.76 | 35.15 → 27.70 | 100.0% → 63.6% |
| default / zoom | 30.1 → 42.3 | 29.93 → 15.82 | 32.92 → 18.56 | 35.96 → 28.75 | 38.45 → 29.54 | 100.0% → 100.0% |
| partial extrusion / orbit | 23.9 → 30.7 | 31.55 → 24.09 | 34.88 → 28.78 | 54.17 → 39.74 | 57.87 → 45.92 | 100.0% → 100.0% |
| partial extrusion / pan | 19.9 → 33.7 | 44.09 → 21.65 | 49.61 → 23.15 | 56.92 → 33.78 | 59.34 → 35.41 | 100.0% → 100.0% |
| partial extrusion / zoom | 21.7 → 29.9 | 36.97 → 28.68 | 40.24 → 31.55 | 50.45 → 39.58 | 52.84 → 42.43 | 100.0% → 100.0% |

**The <14 ms UI/raster p95 target and stable 60 FPS are not achieved.**
Default orbit/pan UI p95 is below 14 ms; zoom and the partial fixture still
exceed it. Raster p95 remains above 14 ms in every workload. UI and raster
over-budget rates are also available separately in the summary/raw records.

## Sampled saveLayer counts

Ranges below cover individual CAD paint samples, including warmup. They exclude
Material/framework layers outside the CAD/sketch renderers. Each entry is
baseline range → optimized range.

| Scene / motion | Planar faces | Curved triangles | Edges | Sketch overlays | Total |
|---|---:|---:|---:|---:|---:|
| default / orbit | 12–14 → 12–14 | 66–128 → 64–128 | 245–317 → 57–289 | 0 → 0 | 324–459 → 140–369 |
| default / pan | 12–14 → 12–14 | 114–128 → 114–128 | 282–318 → 116–208 | 0 → 0 | 409–459 → 257–338 |
| default / zoom | 12–14 → 12–14 | 128 → 128 | 292–296 → 128–200 | 0 → 0 | 432–438 → 269–341 |
| partial extrusion / orbit | 17–18 → 17–18 | 66–198 → 66–202 | 341–473 → 210–344 | 1 → 1 | 431–690 → 357–515 |
| partial extrusion / pan | 17–18 → 17–18 | 136–162 → 134–162 | 390–436 → 214–308 | 1 → 1 | 544–617 → 390–463 |
| partial extrusion / zoom | 17–18 → 16–18 | 150–160 → 150–160 | 404–416 → 224–300 | 1 → 1 | 572–595 → 401–468 |

Curved-layer counts change modestly: batching applies to resolved unmasked cells,
while partial overlaps keep isolated masks. Sampling differs with delivered FPS;
range endpoints need not be identical camera instants. The small planar-range
variation in partial zoom reflects this sampling, not a changed planar algorithm.

## Sampled CPU costs

Median per-paint CPU stages from the same paired capture; values are baseline →
optimized milliseconds. These diagnostic samples include native path operations
and are not substitutes for the engine UI/raster measurements above.

| Scene / motion | Projection + index | Face masking + submission | Edge visibility + masking | Sketch |
|---|---:|---:|---:|---:|
| default / orbit | 0.48 → 0.39 | 4.49 → 2.86 | 9.21 → 5.63 | 0.00 → 0.00 |
| default / pan | 0.48 → 0.39 | 4.73 → 2.97 | 10.47 → 5.45 | 0.00 → 0.00 |
| default / zoom | 0.62 → 0.47 | 6.99 → 3.73 | 14.31 → 6.78 | 0.00 → 0.00 |
| partial extrusion / orbit | 0.97 → 0.76 | 7.24 → 5.38 | 15.93 → 9.26 | 1.21 → 1.12 |
| partial extrusion / pan | 1.05 → 0.77 | 7.91 → 5.49 | 19.74 → 10.33 | 1.34 → 1.20 |
| partial extrusion / zoom | 1.01 → 0.91 | 10.03 → 6.44 | 20.23 → 11.78 | 1.30 → 1.40 |

## Image correctness

Native Impeller comparisons cover two scenes × nine yaw/pitch views × DPR 1/2
(36 pairs), alternating logical viewport sizes 743 × 696 and 640 × 480.
**20/36 pairs are byte-identical**. All others differ by at most **1/255** in any
RGBA channel, with at most **0.0398%** of pixels changed in any image; zero pixels
differ by more than two. Original solid opacity, smooth shading and silhouettes
are retained. Raw results: [native images](performance/viewport_images_native.json).

Headless comparisons also pass all 36 pairs: 34 byte-identical, maximum
channel difference 1/255, maximum changed area 0.0013%. Raw results:
[headless images](performance/viewport_images_headless.json).

The comparison test bounds both changed area (<0.5%) and channel error (≤4), with
at most 32 contact pixels above two, to detect coverage regressions while allowing
sparse GPU AA rounding. Actual final native results are tighter than these bounds.
Selected planar-face colours are checked against the reference at two viewport
sizes (maximum channel difference ≤2); reversing object order is byte-identical.
The native orbit test also checks that opaque solids remain visible and Material
button pixels, dropdown menus and text entry remain correct.

Focused regression coverage includes full-stroke rim contact, holes, concave
notches, self-crossing contours, reciprocal-depth crossings across the stroke
width, coplanar outline bias, candidate order, two-cell coverage, partially visible
mesh, and rebuilding coverage after geometry mutation and viewport resize.

## Rejected approaches and remaining work

Unbounded Dart polygon subtraction moved the bottleneck to UI (a trial default
orbit UI p95 reached about 61 ms), so it was removed. Splitting long edges into
hard-clipped strips and hard-clipping partially visible mesh changed AA coverage
substantially (channel differences up to 173 and 94 in trial comparisons); neither
approach is present. Shared mask layers were also rejected. Native Boolean proofs
are bounded to two masks and benchmarked as part of the final renderer.

The remaining scene still records hundreds of isolated masks on partially covered
strokes and curved cells. These are the main candidates for remaining raster cost;
`FrameTiming` measures the complete raster stage, not GPU time per primitive.
The edge CPU stage remains about 9–12 ms at the partial fixture's sampled median.
Selection, holes, intersections and boundary AA restrict
safe batching. Further progress needs a coverage-preserving way to resolve these
partial regions or a renderer with a real depth buffer; simple whole-face sorting
or unrestricted `drawVertices` batching cannot supply that visibility.

## Validation

- Complete `flutter test`: **496 passed**, including existing rendering and
  tessellation/cache tests and the new visibility/image regressions.
- `dart analyze`: **no issues**; changed Dart files are formatted.
- Native macOS Impeller profile rendering integration suite: **passed** (image
  matrix, selected/reordered/resized scene, continuous orbit and Material controls).
- Paired native profile benchmark: **all 24 phases passed**, 6 seconds of warmup
  and capture per phase.
- Worktree debug app: hot reload succeeded; runtime-error check was empty.

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
```

Single-backend runs can omit `VIEWPORT_PAIRED` and optionally use
`--dart-define=VIEWPORT_BASELINE=true`. The driver writes each run's response to
`build/integration_response_data.json`; copy it before the next drive command.
For headless image statistics, set `VIEWPORT_IMAGE_REPORT=/path/to/report.json`
when running `flutter test test/cad_scene/rendering/viewport_image_comparison_test.dart`.
