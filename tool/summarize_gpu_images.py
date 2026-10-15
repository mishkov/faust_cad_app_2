"""Save numerical comparisons and enlarged, unfiltered boundary examples.

Usage: python3 tool/summarize_gpu_images.py IMAGE_DIRECTORY OUTPUT_DIRECTORY
Requires Pillow. Image captures come from integration_test/gpu_renderer_test.dart.
"""
import json
from pathlib import Path
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFont

source, output = map(Path, sys.argv[1:3])
output.mkdir(parents=True, exist_ok=True)
rows = json.loads((source / 'report.json').read_text())
(output / 'image_statistics_macos.json').write_text(json.dumps(rows, indent=2) + '\n')
summary = {}
for scene in ['default', 'partial_extrusion', 'tube']:
    cases = [r for r in rows if r['scene'] == scene]
    summary[scene] = {
        'cases': len(cases),
        'quality_gate_passes': sum(r['reference_quality_gate_passed'] for r in cases),
        'maximum_channel_delta': max(r['maximum_channel_delta'] for r in cases),
        'maximum_rmse_rgb': max(r['rmse_rgb'] for r in cases),
        'maximum_changed_percent': max(100*r['changed_pixels']/r['pixels'] for r in cases),
    }
(output / 'image_summary_macos.json').write_text(json.dumps(summary, indent=2) + '\n')

# Crops are specified in logical coordinates of the captured viewport. Scale
# by capture DPR, then enlarge with nearest-neighbor to expose the actual pixels.
examples = [
    ('default_0_2.0', (310, 270, 455, 390), 2),
    ('partial_extrusion_0_2.0', (230, 240, 420, 400), 2),
    ('tube_0_2.0', (290, 240, 450, 390), 2),
    ('default_12_1.0', (240, 110, 430, 460), 1),
]
font = ImageFont.load_default(size=20)
for name, box, dpr in examples:
    images = [Image.open(source / f'{name}_{backend}.png').convert('RGB')
              for backend in ['canvas', 'gpu']]
    crop = tuple(round(v*dpr) for v in box)
    patches = [i.crop(crop) for i in images]
    delta = ImageChops.difference(*patches).point(lambda v: min(255, v*4))
    patches.append(delta)
    scale = 2
    patches = [p.resize((p.width*scale, p.height*scale), Image.Resampling.NEAREST)
               for p in patches]
    width, height = patches[0].size
    panel = Image.new('RGB', (width*3, height+40), 'white')
    draw = ImageDraw.Draw(panel)
    for n, (label, patch) in enumerate(zip(['Canvas reference', 'GPU 4x MSAA', 'Absolute RGB difference x4'], patches)):
        draw.text((n*width+8, 8), label, fill='black', font=font)
        panel.paste(patch, (n*width, 40))
    panel.save(output / f'{name}_enlarged.png')
print(json.dumps(summary, indent=2))
