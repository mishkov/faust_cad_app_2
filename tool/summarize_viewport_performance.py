"""Summarize paired native FrameTiming samples without averaging percentiles.

Usage: python3 tool/summarize_viewport_performance.py path/to/frames.json
"""

import json
import math
import statistics
import sys


def summarize(report):
    groups = {}
    for run in report["measurements"].values():
        key = (run["scene"], run["operation"], run["baseline"])
        groups.setdefault(key, []).append(run)
    result = {}
    for (scene, operation, baseline), runs in groups.items():
        ui = [v for run in runs for v in run["raw_ui_us"]]
        raster = [v for run in runs for v in run["raw_raster_us"]]
        assert len(ui) == len(raster) == sum(run["frames"] for run in runs)
        samples = [sample for run in runs for sample in run["layers"]]

        def timings(values):
            ordered = sorted(values)
            return {
                "mean_ms": statistics.mean(values) / 1000,
                "p95_ms": ordered[math.ceil(len(ordered) * .95) - 1] / 1000,
                "p99_ms": ordered[math.ceil(len(ordered) * .99) - 1] / 1000,
                "over_16_7_ms_percent": sum(v > 16700 for v in values)
                * 100 / len(values),
            }

        result[f"{scene}_{operation}_{'baseline' if baseline else 'optimized'}"] = {
            "runs": len(runs),
            "frames": len(ui),
            "fps": len(ui) / sum(run["capture_seconds"] for run in runs),
            "ui": timings(ui),
            "raster": timings(raster),
            "either_over_16_7_ms_percent": sum(
                a > 16700 or b > 16700 for a, b in zip(ui, raster)
            ) * 100 / len(ui),
            "layer_ranges": {
                key: [min(s[key] for s in samples), max(s[key] for s in samples)]
                for key in ["planar_faces", "curved_triangles", "edges",
                            "sketch_overlays", "hidden_edges", "hidden_triangles",
                            "mesh_batches"]
            },
            "total_layer_range": [
                function(sum(s[key] for key in ["planar_faces", "curved_triangles",
                                               "edges", "sketch_overlays"])
                         for s in samples)
                for function in [min, max]
            ],
            "sampled_cpu_median_ms": {
                key: statistics.median(s[key] for s in samples) / 1000
                for key in ["ui_projection_us", "ui_faces_us", "ui_edges_us",
                            "ui_sketch_us"]
            },
        }
    return result


if __name__ == "__main__":
    with open(sys.argv[1]) as source:
        print(json.dumps(summarize(json.load(source)), indent=2))
