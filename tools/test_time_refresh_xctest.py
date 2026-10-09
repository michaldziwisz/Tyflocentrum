#!/usr/bin/env python3
"""Wykonaj dokładną klasę XCTest klienta/stanu na Linuxie; bez SwiftUI/AX."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--zapisz', action='store_true')
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
if not a.zapisz:
    print(f'Plan: XCTest bez SwiftUI, katalog {a.out}; wymagane --zapisz.')
    sys.exit(0)
a.out.mkdir(parents=True, exist_ok=False)
def declaration(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth = 0
    for end in range(opening, len(text)):
        if text[end] == '{': depth += 1
        elif text[end] == '}':
            depth -= 1
            if depth == 0: return text[start:end+1]
    raise ValueError(marker)
state = (root/'Tyflocentrum/Views/ContentTimeList.swift').read_text()
tests = declaration((root/'TyflocentrumTests/ContentTimeIntegrationTests.swift').read_text(), '@MainActor\nfinal class ContentTimeRefreshTests:')
names = re.findall(r'func (test\w+)\(\) async(?: throws)?', tests)
paged_tests = declaration((root/'TyflocentrumTests/PagedFeedViewModelTests.swift').read_text(), '@MainActor\nfinal class PagedFeedViewModelTests:')
paged_model = declaration((root/'Tyflocentrum/Views/NewsView.swift').read_text(), '@MainActor\nfinal class PagedFeedViewModel')
paged_names = re.findall(r'func (test\w+)\(\) async(?: throws)?', paged_tests)
adapter = '''import Foundation
import FoundationNetworking
import XCTest
struct TyfloAPI { struct WPPage<T> { let items: [T]; let total: Int?; let totalPages: Int? } }
protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
struct WPPostSummary {
    struct Title { let rendered: String }
    let id: Int
    let date: String
    let title: Title
    let link: String
    var modifiedGMT: String? = nil
}
'''
main = '\n@main struct Run { @MainActor static func main() {\nXCTMain([testCase([\n' + ',\n'.join(f'("{n}", asyncTest(ContentTimeRefreshTests.{n}))' for n in names) + '\n]), testCase([\n' + ',\n'.join(f'("{n}", asyncTest(PagedFeedViewModelTests.{n}))' for n in paged_names) + '\n])])\n} }'
source = a.out/'tests.swift'
source.write_text(adapter + declaration(state,'struct ContentTimeRequest:') + '\n' + declaration(state,'@MainActor\nfinal class ContentTimeListState:') + '\n' + tests + '\n' + paged_model + '\n' + paged_tests + main)
cmd = [os.environ.get('SWIFTC','/home/ubuntu/.local/opt/swift-6.2.1/usr/bin/swiftc'), '-swift-version','5','-module-cache-path',str(a.out/'module-cache'), *[str(root/'Tyflocentrum'/f) for f in ['Models/ContentTime.swift','ContentTimeClient.swift','AsyncTimeout.swift','StrategiaOdswiezania.swift']],str(source),'-o',str(a.out/'tests')]
(a.out/'command.json').write_text(json.dumps(cmd,indent=2))
r = subprocess.run(cmd,capture_output=True,text=True,timeout=120)
(a.out/'compile.log').write_text(r.stdout+r.stderr)
if r.returncode:
    print(r.stdout+r.stderr); sys.exit(r.returncode)
r = subprocess.run([str(a.out/'tests')],capture_output=True,text=True,timeout=120)
(a.out/'result.log').write_text(r.stdout+r.stderr)
print(r.stdout+r.stderr)
sys.exit(r.returncode)
