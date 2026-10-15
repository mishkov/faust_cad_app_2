#!/usr/bin/env python3
"""Summarize native Metal diagnostics and export actual pixel comparison crops.

Pillow is required only when --images is supplied. No image is reconstructed or
smoothed: crops use nearest-neighbor enlargement and absolute RGB differences.
"""
import argparse
import json
from pathlib import Path


def percentile(values, fraction):
    values = sorted(values)
    return values[min(len(values) - 1, max(0, int(len(values) * fraction + .999999) - 1))] if values else None


def compact_stats(stats):
    result = {k: v for k, v in stats.items() if not isinstance(v, list)}
    for name in ('gpuMilliseconds', 'requestToPresentMilliseconds'):
        result[name] = {f'p{int(p * 100)}': percentile(stats.get(name, []), p) for p in (.5, .95, .99)}
    return result


def summarize(report):
    result = {}
    if 'imageComparisons' in report:
        rows = report['imageComparisons']
        result['imageComparisons'] = rows
        groups = {}
        for row in rows:
            groups.setdefault(row['scenario'], []).append(row)
        result['imageSummary'] = {
            name: {'cases': len(values), **{
                'maximum_' + key: max(v[key] for v in values)
                for key in ('meanAbsoluteChannelDelta', 'pixelsOver4Percent', 'interiorPixelsOver4Percent', 'maximumDelta')
            }} for name, values in groups.items()
        }
    if 'performance' in report:
        runs = {}
        for name, record in report['performance'].items():
            if name == 'soak':
                runs[name] = {'before': compact_stats(record['before']),
                              'samples': [compact_stats(s) for s in record['samples']]}
            else:
                runs[name] = {k: v for k, v in record.items() if k not in ('before', 'after')}
                for key in ('before', 'after'):
                    if record.get(key):
                        runs[name][key] = compact_stats(record[key])
        result['performance'] = runs
    return result


def crops(directory, output):
    from PIL import Image, ImageChops, ImageDraw, ImageEnhance
    for name, rect in [('default_0', (285, 270, 455, 435)),
                       ('partial_0', (230, 290, 445, 440)),
                       ('partial_5', (200, 110, 430, 300)),
                       ('holes_0', (300, 245, 455, 410))]:
        left, right = directory / f'{name}_canvas.png', directory / f'{name}_metal.png'
        if not left.exists() or not right.exists():
            continue
        a, b = Image.open(left).convert('RGB').crop(rect), Image.open(right).convert('RGB').crop(rect)
        delta = ImageEnhance.Brightness(ImageChops.difference(a, b)).enhance(4)
        width, height = a.width * 4, a.height * 4
        sheet = Image.new('RGB', (width * 3, height + 24), 'white')
        draw = ImageDraw.Draw(sheet)
        for i, (label, picture) in enumerate([('Canvas', a), ('Metal', b), ('Absolute RGB delta x4', delta)]):
            draw.text((i * width + 5, 5), label, fill='black')
            sheet.paste(picture.resize((width, height), Image.Resampling.NEAREST), (i * width, 24))
        sheet.save(output / f'{name}_boundaries.png')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('--images', type=Path)
    parser.add_argument('--output', type=Path, default=Path('build/metal_summary'))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    result = summarize(json.loads(args.report.read_text()))
    (args.output / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
    if args.images:
        crops(args.images, args.output)
    print(args.output / 'summary.json')


if __name__ == '__main__':
    main()
