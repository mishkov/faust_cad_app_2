"""Native profile memory cycles with an external VM client and optional vmmap.

Usage: python3 tool/profile_viewport_memory.py OUTPUT_PREFIX [--baseline] [--cycles=20]
Run independently of the FrameTiming benchmark; GC requests interrupt the VM.
"""
import json
import pathlib
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

prefix = pathlib.Path(sys.argv[1])
prefix.parent.mkdir(parents=True, exist_ok=True)
command = ['flutter', 'drive', '--profile', '-d', 'macos', '--enable-impeller',
           '--driver=test_driver/integration_test.dart',
           '--target=integration_test/viewport_memory_test.dart']
cycles=next((int(arg.split('=',1)[1]) for arg in sys.argv if arg.startswith('--cycles=')),10)
command.append(f'--dart-define=MEMORY_CYCLES={cycles}')
if '--baseline' in sys.argv:
    command.append('--dart-define=VIEWPORT_BASELINE=true')
records = []
service = None
isolate = None
app_pid = None


def rpc(method, **params):
    url = service + method + '?' + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=10) as response:
        result = json.load(response)
    if 'error' in result:
        raise RuntimeError(result['error'])
    return result['result']


with prefix.with_suffix('.log').open('w') as log:
    process = subprocess.Popen(command, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, bufsize=1)
    test_failed = False
    for line in process.stdout:
        test_failed |= "Some tests failed." in line
        log.write(line)
        log.flush()
        match = re.search(r'Connecting to Flutter application at (http://\S+)', line)
        if match:
            service = match[1].rstrip('/') + '/'
        if 'MEMORY_SAMPLE ' not in line:
            continue
        sample = json.loads(line.split('MEMORY_SAMPLE ', 1)[1])
        probe_start=time.perf_counter()
        try:
            if isolate is None:
                vm = rpc('getVM')
                isolate = next((i['id'] for i in vm['isolates'] if i['name'] == 'main'),vm['isolates'][0]['id'])
                app_pid = vm['pid']
            sample['heap_before_gc'] = rpc('getMemoryUsage', isolateId=isolate)
            # Rotation cycles run without forced collection, exposing the natural
            # plateau. Initial/rest samples separate live data from capacity.
            if sample['phase'] in ('idle', 'rest'):
                try:
                    allocation = rpc('getAllocationProfile', isolateId=isolate, gc='true')
                    sample['allocation_after_gc'] = allocation['memoryUsage']
                    sample['live_renderer_classes'] = [
                        {'name': member['class']['name'],
                         'instances': member['instancesCurrent'],
                         'bytes': member['bytesCurrent']}
                        for member in allocation.get('members', [])
                        if any(token in member['class']['name'] for token in
                               ['ProjectedFace', 'ShadedSceneRenderer', 'Vertices', 'Vector3',
                                'CurvedTriangleVisibility', 'ProjectedMeshBatch'])
                    ]
                    sample['heap_after_gc'] = rpc('getMemoryUsage', isolateId=isolate)
                except Exception as error:
                    sample['gc_probe_error'] = str(error)
            sample['rss_after_probe_kib'] = int(subprocess.check_output(['ps', '-o', 'rss=', '-p', str(app_pid)], text=True).strip())
            if sample['phase'] in ('idle', 'rest') or sample['cycle'] in (1, 10, cycles):
                native = subprocess.run(['vmmap', '-summary', str(app_pid)], capture_output=True, text=True, timeout=15)
                native_path = pathlib.Path(f'{prefix}_{sample["scene"]}_{sample["phase"]}_{sample["cycle"]}_vmmap.txt')
                native_path.write_text(native.stdout + native.stderr)
                sample['vmmap_exit_code'] = native.returncode
        except Exception as error:
            sample['probe_error'] = str(error)
        finally:
            sample['probe_seconds']=time.perf_counter()-probe_start
            if isolate is not None:
                try:
                    rpc('ext.cad.memoryProbeComplete',isolateId=isolate)
                except Exception as error:
                    sample['resume_error']=str(error)
        records.append(sample)
        prefix.with_suffix('.json').write_text(json.dumps(records, indent=2))
        print(json.dumps(sample), flush=True)
    code = process.wait()
    if code or test_failed:
        raise SystemExit(code or 1)
    if len(records) != cycles * 2 + 6:
        raise RuntimeError(f"Incomplete memory run: {len(records)} samples")
    if any(any(key in sample for key in ('probe_error', 'gc_probe_error', 'resume_error'))
           for sample in records):
        raise RuntimeError("Memory probe failed; inspect the saved samples")
