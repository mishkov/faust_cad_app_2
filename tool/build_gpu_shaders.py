"""Build with the compiler shipped alongside the selected Flutter executable."""
import json
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
sdk = Path(shutil.which('flutter')).resolve().parent.parent
compiler = sdk / 'bin/cache/artifacts/engine/darwin-x64/impellerc'
bundle = {name: {'type': kind, 'file': f'shaders/{file}'} for name, kind, file in [
    ('CadBodyVertex', 'vertex', 'body.vert'),
    ('CadBodyFragment', 'fragment', 'body.frag'),
    ('CadEdgeVertex', 'vertex', 'edge.vert'),
    ('CadEdgeFragment', 'fragment', 'edge.frag'),
]}
subprocess.run([str(compiler), '--metal-desktop',
                '--shader-bundle=' + json.dumps(bundle), '--include=shaders',
                '--sl=shaders/cad.shaderbundle'], cwd=root, check=True)
print('Built shaders/cad.shaderbundle with', compiler)
