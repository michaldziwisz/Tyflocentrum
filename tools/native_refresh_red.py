#!/usr/bin/env python3
"""Natywny RED na niezmienionej bazie, ze współczesną atrapą stałych ID.

Tylko macOS/Xcode. Kopiuje wyłącznie aparaturę DEBUG i testy UI, nie modele,
klienta metadanych ani widoki list. Wymaga nowego katalogu wyjściowego.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile

BASE = 'eb1561fa008abb9427b1de332acd841da37e0c56'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
out = a.out.resolve()
out.mkdir(parents=True, exist_ok=False)
repo = Path(__file__).resolve().parents[1]
source = out / 'base'
source.mkdir()
archive = out / 'base.tar'
with archive.open('wb') as f:
    subprocess.run(['git', 'archive', BASE], cwd=repo, stdout=f, check=True)
with tarfile.open(archive) as tar:
    tar.extractall(source, filter='data')
# App zmienia tylko przygotowanie danych i kontrole DEBUG, nie modele/widoki.
fixtures = ['Tyflocentrum/ContentTimeUITestData.swift',
            'Tyflocentrum/TyflocentrumApp.swift',
            'TyflocentrumUITests/TyflocentrumSmokeTests.swift']
manifest = []
for relative in fixtures:
    data = (repo / relative).read_bytes()
    (source / relative).write_bytes(data)
    manifest.append({'path': relative, 'sha256': hashlib.sha256(data).hexdigest()})
(out / 'fixture-manifest.json').write_text(json.dumps({'base': BASE, 'copied': manifest}, indent=2))
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
candidates = [(tuple(map(int, re.findall(r'\d+', runtime))), device['udid'])
              for runtime, entries in devices.items() if 'iOS' in runtime
              for device in entries if device.get('isAvailable') and 'iPhone' in device['name']]
_, udid = max(candidates, key=lambda pair: pair[0])
subprocess.run(['xcrun','simctl','boot',udid],check=False)
subprocess.run(['xcrun','simctl','bootstatus',udid,'-b'],check=True,timeout=180)
command = ['xcodebuild', '-project', 'Tyflocentrum.xcodeproj', '-scheme', 'Tyflocentrum',
           '-configuration', 'Debug', '-sdk', 'iphonesimulator',
           '-destination', f'platform=iOS Simulator,id={udid}',
           '-derivedDataPath', str(out/'DerivedData'), '-resultBundlePath', str(out/'red.xcresult'),
           '-parallel-testing-enabled', 'NO', '-parallel-testing-worker-count', '1',
           '-only-testing:TyflocentrumUITests/TyflocentrumSmokeTests/testTimeRefreshNewsSameProcess', 'test']
(out / 'command.json').write_text(json.dumps(command, indent=2))
with (out/'xcodebuild.log').open('wb') as log:
    result = subprocess.run(command, cwd=source, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
for mode in ['summary', 'tests']:
    with (out/f'{mode}.json').open('wb') as f:
        subprocess.run(['xcrun','xcresulttool','get','test-results',mode,'--path',str(out/'red.xcresult')],stdout=f,check=True)
for kind in ['attachments', 'diagnostics']:
    subprocess.run(['xcrun','xcresulttool','export',kind,'--path',str(out/'red.xcresult'),'--output-path',str(out/kind)],check=True)
summary = json.loads((out/'summary.json').read_text())
failures = summary.get('testFailures', [])
attachments = json.loads((out/'attachments/manifest.json').read_text())
labels = []
for test in attachments:
    for item in test.get('attachments', []):
        if 'czas-news-missing-etykieta' in item.get('suggestedHumanReadableName', ''):
            labels.append((out/'attachments'/item['exportedFileName']).read_text())
valid = (result.returncode != 0 and summary.get('totalTestCount') == 1
         and summary.get('failedTests') == 1 and len(failures) == 1
         and 'XCTWaiterResult(rawValue: 2)' in failures[0].get('failureText', '')
         and len(labels) == 2 and all('Czas niedostępny' in label for label in labels))
verdict = {'base': BASE, 'expected_red': valid, 'xcode_exit': result.returncode,
           'initial_row_labels': labels, 'failures': failures,
           'limitation': 'RED wymaga także odczytu screenshotu i śladu gestu; nie zalicza błędu uruchomienia.'}
(out/'verdict.json').write_text(json.dumps(verdict, ensure_ascii=False, indent=2))
print(json.dumps(verdict, ensure_ascii=False))
raise SystemExit(0 if valid else 1)
