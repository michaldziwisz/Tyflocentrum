#!/usr/bin/env python3
"""Wykonaj niezmienione modele Swift w Linux/macOS, nie emuluj SwiftUI.

--source pozwala uruchomić identyczne asercje na archiwum bazy.
--out musi być nowym katalogiem. Bez --zapisz nie zapisuje niczego.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
p.add_argument('--out', type=Path, required=True)
p.add_argument('--zapisz', action='store_true')
a = p.parse_args()
if not a.zapisz:
    print(f'Plan: źródło {a.source}, dowody {a.out}. Wymagane --zapisz.')
    sys.exit(0)
a.out.mkdir(parents=True, exist_ok=False)

def block(text, marker):
    start = text.index(marker)
    opened = text.index('{', start)
    depth = 0
    for end in range(opened, len(text)):
        if text[end] == '{':
            depth += 1
        elif text[end] == '}':
            depth -= 1
            if depth == 0:
                return text[start:end + 1]
    raise ValueError(marker)

news = (a.source / 'Tyflocentrum/Views/NewsView.swift').read_text()
state = (a.source / 'Tyflocentrum/Views/ContentTimeList.swift').read_text()
adapter = r'''
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
struct WPPostSummary: Identifiable, Codable {
    let id: Int
    let date: String
    let title: String
    let modifiedGMT: String?
    let tyflocentrum: ContentTimeMetadata?
}
@MainActor final class TyfloAPI {
    struct WPPage<T> { let items: [T]; let total: Int?; let totalPages: Int? }
    var audio = 0
    var calls = 0
    func fetchPodcastSummariesPage(page: Int, perPage: Int, cachePolicy: URLRequest.CachePolicy) async throws -> WPPage<WPPostSummary> {
        calls += 1
        return WPPage(items: page == 1 ? [summary(1, audio)] : [], total: 1, totalPages: 1)
    }
    func fetchArticleSummariesPage(page: Int, perPage: Int, cachePolicy: URLRequest.CachePolicy) async throws -> WPPage<WPPostSummary> {
        calls += 1
        return WPPage(items: [], total: 0, totalPages: 1)
    }
}
func summary(_ id: Int, _ seconds: Int) -> WPPostSummary {
    let raw = "{\"schema_version\":1,\"audio_status\":\"\(seconds > 0 ? "ready" : "missing")\",\"duration_seconds\":\(seconds)}"
    let metadata = try! JSONDecoder().decode(ContentTimeMetadata.self, from: Data(raw.utf8))
    return WPPostSummary(id: id, date: "2026-01-20T00:00:00", title: "Stały tytuł", modifiedGMT: "2026-01-20T00:00:00", tyflocentrum: metadata)
}
actor Server {
    var stage = 0
    var calls = 0
    var held: CheckedContinuation<Void, Never>?
    var holdNext = false
    func set(_ stage: Int) { self.stage = stage }
    func hold() { holdNext = true }
    func release() { held?.resume(); held = nil }
    func receive(_ request: URLRequest) async throws -> (Data, URLResponse) {
        calls += 1
        let captured = stage
        if holdNext { holdNext = false; await withCheckedContinuation { held = $0 } }
        let url = request.url!
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let podcast = url.host == "tyflopodcast.net"
        let ids = q.first { $0.name == (podcast ? "include" : "ids") }!.value!.split(separator: ",").map { Int($0)! }
        let ready = captured == 1 || captured == 2
        let metadata: [String: Any] = ["schema_version":1, "audio_status":ready ? "ready" : "missing", "text_status":ready ? "ready" : "missing", "duration_seconds":captured == 2 ? 60 : 4984, "word_count":captured == 2 ? 1201 : 1001, "reading_minutes":captured == 2 ? 7 : 6]
        let items: [[String: Any]] = ids.map { ["id":$0, "freshness":"fresh", "checked_at":ISO8601DateFormatter().string(from: Date()), "modified_gmt":"2026-01-20T00:00:00", "tyflocentrum":metadata] }
        let object: Any = podcast ? items : ["schema_version":1, "source":"tyfloswiat.pl", "type":q.first { $0.name == "type" }!.value!, "items":items]
        return (try JSONSerialization.data(withJSONObject:object), HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:nil)!)
    }
}
@main struct Probe {
    @MainActor static func main() async {
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            print("\(value ? "PASS" : "FAIL") \(label)")
            if !value { failures += 1 }
        }
        print("PID \(ProcessInfo.processInfo.processIdentifier)")
        let api = TyfloAPI()
        let feed = NewsFeedViewModel()
        await feed.loadIfNeeded(api: api)
        let ids = feed.items.map(\.id)
        check(feed.items.first?.post.tyflocentrum?.audioSeconds == nil, "news początkowo missing")
        api.audio = 60 // jawna zmiana serwera, nie licznik żądań
        await feed.odswiezPoPowrocie(api: api, powod: .zadanieUzytkownika)
        check(feed.items.first?.post.tyflocentrum?.audioSeconds == 60, "news scalenie istniejącego ID odbiera świeże audio")
        check(feed.items.map(\.id) == ids, "news te same ID i kolejność")
        check(feed.komunikatDostepnosci == nil && feed.kotwicaPrzewijania == nil, "news zmiana czasu nie ogłasza nowych wpisów ani kotwicy")
        let before = api.calls
        await feed.odswiezPoPowrocie(api: api)
        check(api.calls == before, "powrót przed progiem nie robi ruchu")
        api.audio = 120
        await feed.refresh(api: api)
        check(feed.items.first?.post.tyflocentrum?.audioSeconds == 120, "news ręczny refresh ready do ready")

        let paged = PagedFeedViewModel<WPPostSummary>(perPage: 1)
        await paged.loadIfNeeded { page, _ in TyfloAPI.WPPage(items:[summary(page, 0)], total:3, totalPages:3) }
        await paged.loadMore { page, _ in TyfloAPI.WPPage(items:[summary(page, 0)], total:3, totalPages:3) }
        check(paged.items.map(\.id) == [1,2], "paginacja kontrola początkowa")
        var during: [Int] = []
        await paged.refresh { page, _ in
            during = paged.items.map(\.id)
            return TyfloAPI.WPPage(items:[summary(page,60)],total:3,totalPages:3)
        }
        check(during == [1,2], "refresh nie usuwa wierszy podczas await")
        check(paged.items.map(\.id) == [1,2], "refresh tych samych ID zachowuje starszą stronę")
        check(paged.items.first?.tyflocentrum?.audioSeconds == 60, "refresh aktualizuje inline bez zmiany tożsamości")
        await paged.loadMore { page, _ in TyfloAPI.WPPage(items:[summary(page, 0)], total:3, totalPages:3) }
        check(paged.items.map(\.id) == [1,2,3], "refresh zachował kursor paginacji")

        for kind in ContentTimeKey.Kind.allCases {
            let server = Server()
            let client = ContentTimeClient(transport: { try await server.receive($0) })
            let state = ContentTimeListState()
            let input = [ContentTimeRequest(summary(1,0), kind:kind)]
            _ = await state.load(input, refreshing:false, client:client)
            check(state.values(input, now:Date())[input[0].key] == .unavailable, "\(kind) missing")
            await server.set(1)
            _ = await state.load(input, refreshing:true, client:client)
            check(state.values(input, now:Date())[input[0].key] == (kind == .podcast ? .audio(4984) : .reading(6)), "\(kind) wymuszenie omija negatywny cache")
            await server.set(2)
            _ = await state.load(input, refreshing:true, client:client)
            check(state.values(input, now:Date())[input[0].key] == (kind == .podcast ? .audio(60) : .reading(7)), "\(kind) ready do nowszego ready")
            await server.set(3)
            _ = await state.load(input, refreshing:true, client:client)
            check(state.values(input, now:Date())[input[0].key] == .unavailable, "\(kind) wycofane metadane")
        }
        print("RESULT failures=\(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
'''
# Wstaw dokładne deklaracje aplikacji przed program testowy.
pre, program = adapter.split('@main struct Probe', 1)
blocks = [block(news, 'enum NewsItemKind:'), block(news, 'struct NewsItem:'),
          block(news, '@MainActor\nfinal class NewsFeedViewModel:'),
          block(news, '@MainActor\nfinal class PagedFeedViewModel'),
          block(state, 'struct ContentTimeRequest:'),
          block(state, '@MainActor\nfinal class ContentTimeListState:')]
probe = a.out / 'probe.swift'
probe.write_text(pre + '\n'.join(blocks) + '\n@main struct Probe' + program)
source_files = [a.source / ('Tyflocentrum/' + s) for s in ['Models/ContentTime.swift', 'ContentTimeClient.swift', 'AsyncTimeout.swift', 'StrategiaOdswiezania.swift', 'ScalanieNowosci.swift', 'PolishPluralization.swift']]
command = [os.environ.get('SWIFTC','/home/ubuntu/.local/opt/swift-6.2.1/usr/bin/swiftc'), '-swift-version','5','-module-cache-path',str(a.out/'module-cache'), *map(str,source_files), str(probe), '-o',str(a.out/'probe')]
if sys.platform == 'darwin':
    command += ['-sdk', subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()]
(a.out/'command.json').write_text(json.dumps(command,indent=2))
result = subprocess.run(command,capture_output=True,text=True,timeout=120)
(a.out/'compile.log').write_text(result.stdout+result.stderr)
if result.returncode:
    print(result.stdout+result.stderr)
    sys.exit(result.returncode)
result = subprocess.run([str(a.out/'probe')],capture_output=True,text=True,timeout=90)
(a.out/'result.log').write_text(result.stdout+result.stderr)
(a.out/'sources.json').write_text(json.dumps({str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in source_files + [a.source/'Tyflocentrum/Views/NewsView.swift',a.source/'Tyflocentrum/Views/ContentTimeList.swift']},indent=2))
print(result.stdout+result.stderr)
sys.exit(result.returncode)
