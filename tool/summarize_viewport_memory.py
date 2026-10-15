"""Summarize memory probes and sanitized vmmap categories.

Usage: python3 tool/summarize_viewport_memory.py OUTPUT_PREFIX [OUTPUT_PREFIX...]
The companion profiler writes PREFIX.json and PREFIX_*_vmmap.txt.
"""
import json
import pathlib
import re
import sys


def size(value):
    match = re.fullmatch(r'([0-9.]+)([KMG]?)', value)
    return round(float(match[1]) * {'': 1, 'K': 1024, 'M': 1024**2, 'G': 1024**3}[match[2]])


def native_summary(path):
    text = path.read_text()
    result = {}
    for label in ['Physical footprint', 'Physical footprint (peak)']:
        match = re.search(r'^' + re.escape(label) + r':\s+(\S+)', text, re.M)
        if match:
            result[label] = size(match[1])
    result['regions'] = {}
    for label in ['IOAccelerator (graphics)', 'IOSurface', 'VM_ALLOCATE',
                  'owned unmapped (graphics)']:
        match = re.search(r'^' + re.escape(label) + r'\s+(.+)$', text, re.M)
        if match:
            fields = match[1].split()
            result['regions'][label] = {
                'virtual_bytes': size(fields[0]),
                'resident_bytes': size(fields[1]),
                'dirty_bytes': size(fields[2]),
                'regions': int(fields[7]),
            }
    zones = text.split('MALLOC ZONE')[-1]
    total = re.search(r'^TOTAL\s+(.+)$', zones, re.M)
    if total:
        fields = total[1].split()
        result['malloc_zones'] = {
            'virtual_bytes': size(fields[0]),
            'resident_bytes': size(fields[1]),
            'allocated_bytes': size(fields[5]),
            'fragmentation_bytes': size(fields[6]),
        }
    return result


def summarize(prefix):
    prefix = pathlib.Path(prefix)
    samples = json.loads(prefix.with_suffix('.json').read_text())
    result = {'scenes': {}, 'native_snapshots': []}
    for scene in dict.fromkeys(s['scene'] for s in samples):
        values = [s for s in samples if s['scene'] == scene]
        rotations = [s for s in values if s['phase'] == 'rotation']
        last_five = [s['rss'] / 1024**2 for s in rotations[-5:]]
        collected = [s for s in values if 'allocation_after_gc' in s]
        result['scenes'][scene] = {
            'cycles': len(rotations),
            'first_rss_mib': values[0]['rss'] / 1024**2,
            'last_rss_mib': values[-1]['rss'] / 1024**2,
            'peak_rss_mib': max(s['max_rss'] for s in values) / 1024**2,
            'last_five_rotation_rss_mib': last_five,
            'last_after_gc': collected[-1]['allocation_after_gc'] if collected else None,
        }
        gpu_samples = [s['gpu'] for s in values if 'gpu' in s]
        if gpu_samples:
            result['scenes'][scene]['rendered_workload_complete'] = all(
                s['failure'] == 'null' for s in gpu_samples)
            result['scenes'][scene]['completed_gpu_images'] = gpu_samples[-1]['completions']
    for sample in samples:
        path = pathlib.Path(f'{prefix}_{sample["scene"]}_{sample["phase"]}_{sample["cycle"]}_vmmap.txt')
        if path.exists() and sample.get('vmmap_exit_code') == 0:
            result['native_snapshots'].append({
                'scene': sample['scene'], 'phase': sample['phase'], 'cycle': sample['cycle'],
                **native_summary(path),
            })
    return result


if __name__ == '__main__':
    print(json.dumps({pathlib.Path(p).name: summarize(p) for p in sys.argv[1:]}, indent=2))
