#!/usr/bin/env python3
"""Enforce the project's global color/spacing contract in custom UI sources."""
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent / 'Sources/Senda'
files = ['ContentView.swift', 'HostSidebar.swift', 'FileTable.swift', 'SendaTheme.swift',
         'TransferRow.swift', 'TransferDetailsView.swift', 'SendaApp.swift']
patterns = [r'(?:Color|NSColor)\((?:red|white|calibratedRed|srgbRed):',
            r'\.padding\((?:\.[a-zA-Z]+,\s*)?\d',
            r'(?:spacing|cornerRadius|minLength|minWidth|minHeight|width|height):\s*\d',
            r'\.foregroundStyle\(\.(?:primary|secondary|tertiary|red|blue|green|white|black)',
            r'\.fill\(\.(?:primary|secondary|red|blue|green|white|black)',
            r'(?:HStack|VStack)\s*\{']
failures = []
for name in files:
    for number, line in enumerate((root / name).read_text().splitlines(), 1):
        if any(re.search(pattern, line) for pattern in patterns):
            failures.append(f'{name}:{number}: {line.strip()}')
if failures:
    raise SystemExit('Use global design tokens:\n' + '\n'.join(failures))
print('Custom UI colors and spacing use global tokens.')
