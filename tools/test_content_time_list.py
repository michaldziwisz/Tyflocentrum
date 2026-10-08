#!/usr/bin/env python3
"""Sprawdź rzeczywisty wybór żądań i stan listy bez deklarowania testu SwiftUI.

Adapter View tylko przechwytuje argument modyfikatora. Nie renderuje ekranu.
Kod contentTimes oraz ContentTimeListState jest wycinany bez zmian z aplikacji.
Pełne XCTest/SwiftUI wymagają osobnego przebiegu Xcode.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--zapisz', action='store_true')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
compiler = Path(os.environ.get('SWIFTC') or shutil.which('swiftc') or '/home/ubuntu/.local/opt/swift-6.2.1/usr/bin/swiftc')
source_path = repo / 'Tyflocentrum/Views/ContentTimeList.swift'
source = source_path.read_text()


def declaration(marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 0
    for end in range(opening, len(source)):
        if source[end] == '{':
            depth += 1
        elif source[end] == '}':
            depth -= 1
            if depth == 0:
                return source[start:end + 1]
    raise ValueError('Niezamknięta deklaracja: ' + marker)


blocks = [declaration('struct ContentTimeRequest:'),
          declaration('@MainActor\nfinal class ContentTimeListState:'),
          declaration('extension View {')]
adapters = r'''
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
struct WPPostSummary { let id: Int; let modifiedGMT: String? }
protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
struct ContentTimeListModifier { let requests: [ContentTimeRequest]; let refreshing: Bool }
protocol View { var measured: ContentTimeListModifier { get } }
struct ProbeView: View { let measured = ContentTimeListModifier(requests: [], refreshing: false) }
struct ModifiedProbeView: View { let measured: ContentTimeListModifier }
extension View {
    func modifier(_ value: ContentTimeListModifier) -> ModifiedProbeView { ModifiedProbeView(measured: value) }
}
'''
program = r'''
actor Server {
    var urls: [URL] = []
    var hold = false
    var waiting = false
    var continuation: CheckedContinuation<Void, Never>?
    func block() { hold = true }
    func release() { hold = false; continuation?.resume(); continuation = nil }
    func receive(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        urls.append(url)
        if hold {
            waiting = true
            await withCheckedContinuation { continuation = $0 }
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let ids = query.first { $0.name == "ids" }!.value!.split(separator: ",").map { Int($0)! }
        let now = ISO8601DateFormatter().string(from: Date())
        let items: [[String: Any]] = ids.map { ["id": $0, "freshness": "fresh", "checked_at": now,
            "modified_gmt": "2026-01-20T00:00:00", "tyflocentrum": ["schema_version": 1,
            "text_status": "ready", "word_count": 1001, "reading_minutes": 6]] }
        let data = try JSONSerialization.data(withJSONObject: ["schema_version": 1, "source": "tyfloswiat.pl",
            "type": "posts", "items": items])
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
@main struct Probe {
    @MainActor static func main() async {
        var failures = 0
        func check(_ success: Bool, _ name: String) {
            print("\(success ? "PASS" : "FAIL") \(name)")
            if !success { failures += 1 }
        }
        // Oba końce i środek, w kolejności malejącej, jak na rzeczywistej liście.
        let input = (1...600).reversed().map { ContentTimeRequest(WPPostSummary(id: $0, modifiedGMT: nil), kind: .posts) }
        let actual = ProbeView().contentTimes(input).measured
        check(actual.requests == input, "modyfikator zachowuje wszystkie 600 żądań i ich kolejność (otrzymano \(actual.requests.count))")
        let server = Server()
        let client = ContentTimeClient(transport: { try await server.receive($0) })
        let state = ContentTimeListState()
        await state.load(actual.requests, refreshing: false, client: client)
        let values = state.values(input, now: Date())
        check(values.values.filter { $0 == .reading(6) }.count == input.count, "600 rzeczywistych czasów, nie etykiet niedostępności")
        check(input.allSatisfy { values[$0.key] == .reading(6) }, "czas każdego wpisu, także obu końców listy")
        let cached = await client.cachedCount
        check(cached <= 512, "cache współdzielony nadal ograniczony do 512 (\(cached))")
        let urls = await server.urls
        check(urls.allSatisfy { url in
            let ids = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "ids" }!.value!.split(separator: ",")
            return ids.count <= 50 && url.path == "/v1/metadata"
        }, "każda paczka najwyżej 50 ID, bez żądań tekstów lub audio")

        let pagedServer = Server()
        let pagedClient = ContentTimeClient(transport: { try await pagedServer.receive($0) })
        let paged = ContentTimeListState()
        let first = Array(input.prefix(50)); let twoPages = Array(input.prefix(100))
        await paged.load(first, refreshing: false, client: pagedClient)
        await pagedServer.block()
        let pending = Task { await paged.load(twoPages, refreshing: false, client: pagedClient) }
        for _ in 0..<1000 {
            if await pagedServer.waiting { break }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let waiting = await pagedServer.waiting
        check(waiting, "druga strona rzeczywiście czeka na transport")
        let during = paged.values(first, now: Date())
        check(first.allSatisfy { during[$0.key] == .reading(6) }, "doładowanie nie usuwa już widocznych czasów pierwszej strony")
        await pagedServer.release(); await pending.value
        let completed = paged.values(twoPages, now: Date())
        check(twoPages.allSatisfy { completed[$0.key] == .reading(6) }, "obie strony mają rzeczywiste czasy po zakończeniu transportu")

        let before = await pagedServer.urls.count
        let newScreen = ContentTimeListState()
        await newScreen.load([], refreshing: true, client: pagedClient)
        await newScreen.load(first, refreshing: false, client: pagedClient)
        let after = await pagedServer.urls.count
        check(before == after, "pusty zimny ekran nie unieważnia cache innego ekranu")
        print("RESULT failures=\(failures), list=\(input.count), batches=\(urls.count), cache=\(cached)")
        exit(failures == 0 ? 0 : 1)
    }
}
'''
if not args.zapisz:
    print(json.dumps({'mode': 'plan', 'compiler': str(compiler), 'out': str(args.out),
                      'source_sha256': hashlib.sha256(source.encode()).hexdigest()}, ensure_ascii=False))
    sys.exit(0)
args.out.mkdir(parents=True, exist_ok=True)
probe = args.out / 'probe.swift'
probe.write_text(adapters + '\n'.join(blocks) + program)
exe = args.out / 'probe'
command = [str(compiler), '-swift-version', '5', '-module-cache-path', str(args.out / 'module-cache'),
           str(repo / 'Tyflocentrum/Models/ContentTime.swift'),
           str(repo / 'Tyflocentrum/ContentTimeClient.swift'),
           str(repo / 'Tyflocentrum/AsyncTimeout.swift'), str(probe), '-o', str(exe)]
if sys.platform == 'darwin':
    # Uruchamiamy sondę na hoście macOS, nie w symulatorze iOS. Sama ścieżka
    # z xcrun --find swiftc nie przekazuje SDK do bezpośredniego wywołania.
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    command += ['-sdk', sdk]
(args.out / 'compile-command.json').write_text(json.dumps(command, ensure_ascii=False, indent=2))
print('Kompilacja sondy:', json.dumps(command, ensure_ascii=False), flush=True)
build = subprocess.run(command, capture_output=True, text=True, timeout=120)
(args.out / 'compile.log').write_text(build.stdout + build.stderr)
if build.returncode:
    print(build.stdout + build.stderr)
    sys.exit(build.returncode)
result = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
(args.out / 'result.log').write_text(result.stdout + result.stderr)
(args.out / 'source.json').write_text(json.dumps({'source': str(source_path),
    'sha256': hashlib.sha256(source.encode()).hexdigest(), 'returncode': result.returncode,
    'scope': 'Rzeczywiste przetwarzanie żądań i stan, nie renderowanie SwiftUI.'}, ensure_ascii=False, indent=2))
print(result.stdout + result.stderr)
sys.exit(result.returncode)
