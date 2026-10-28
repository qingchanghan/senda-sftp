#!/usr/bin/env python3
"""Export only reviewed tracked files, never the entire working directory."""
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
paths = [p for p in paths if p]
if not paths:
    raise SystemExit('No tracked files. Review and stage the intended source files first.')
for name in paths:
    if name.startswith(('.build/', 'dist/', '.local-notes/', '.env')) or (root / name).is_symlink():
        raise SystemExit('Unexpected private/build/symlink path in source manifest: ' + name)
out = root / 'dist/Senda-1.6.0-source.zip'
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for name in sorted(paths):
        archive.write(root / name, 'senda-sftp/' + name)
print(f'Packaged {len(paths)} tracked files: {out}')
