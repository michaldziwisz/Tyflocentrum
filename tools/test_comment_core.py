#!/usr/bin/env python3
"""Uruchamia rzeczywiste XCTest modelu komentarzy na Swift Linux, bez SwiftUI.
Wymaga --zapisz i katalogu wyników poza repo. Nie zastępuje testów iOS.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--zapisz', action='store_true', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=True)
swiftc = os.environ.get('SWIFTC', '/home/ubuntu/.local/opt/swift-6.2.1/usr/bin/swiftc')
sources = [root / 'Tyflocentrum/Models/Comment.swift', root / 'Tyflocentrum/CommentHTMLDocument.swift']
tests = root / 'TyflocentrumTests/CommentPresentationTests.swift'
methods = re.findall(r'func (test\w+)\(', tests.read_text())
assert len(methods) == len(set(methods)) and methods
(out / 'main.swift').write_text('import XCTest\nXCTMain([testCase([\n' + ',\n'.join(f'("{m}", CommentPresentationTests.{m})' for m in methods) + '\n])])\n')
commands = [
    [swiftc, '--version'],
    [swiftc, '-swift-version', '5', '-enable-testing', '-emit-library', '-emit-module', '-module-name', 'Tyflocentrum', *map(str, sources), '-emit-module-path', str(out / 'Tyflocentrum.swiftmodule'), '-o', str(out / 'libTyflocentrum.so')],
    [swiftc, '-swift-version', '5', str(tests), str(out / 'main.swift'), '-I', str(out), '-L', str(out), '-lTyflocentrum', '-Xlinker', '-rpath', '-Xlinker', str(out), '-o', str(out / 'comment-tests')],
    [str(out / 'comment-tests')],
]
results = []
for index, command in enumerate(commands):
    p = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (out / f'{index:02d}.log').write_text(p.stdout)
    print(p.stdout)
    results.append({'command': command, 'exit_code': p.returncode})
    if p.returncode:
        break
receipt = {'results': results, 'methods': methods, 'sources': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources + [tests]}, 'passed': len(results) == len(commands) and all(r['exit_code'] == 0 for r in results), 'scope': 'Swift Linux, model i generowanie HTML; bez WebKit, SwiftUI i VoiceOver'}
(out / 'receipt.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
raise SystemExit(0 if receipt['passed'] else 1)
