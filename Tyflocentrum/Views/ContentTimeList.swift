import Foundation
import SwiftUI

struct ContentTimeRequest: Hashable {
	let key: ContentTimeKey
	let modifiedGMT: String?

	init(_ summary: WPPostSummary, kind: ContentTimeKey.Kind) {
		key = ContentTimeKey(kind: kind, id: summary.id)
		modifiedGMT = summary.modifiedGMT
	}
}

extension WPPostSummary {
	/// Starsze zapisane numery nie mają znacznika. Rozpoznajemy wyłącznie URL
	/// okładki numeru, nie tytuł artykułu ani sam rok w jego nazwie.
	var excludesReadingTime: Bool {
		if isMagazineIssue == true { return true }
		guard let url = URL(string: link) else { return false }
		let parts = url.path.split(separator: "/")
		return parts.count == 2 && parts.first == "czasopismo"
	}
}

extension FavoriteItem {
	var contentTimeRequest: ContentTimeRequest? {
		switch self {
		case let .podcast(summary): return ContentTimeRequest(summary, kind: .podcast)
		case let .article(summary, origin):
			guard !summary.excludesReadingTime else { return nil }
			return ContentTimeRequest(summary, kind: origin == .post ? .posts : .pages)
		default: return nil
		}
	}
}

private struct ContentTimeValuesKey: EnvironmentKey {
	static let defaultValue: [ContentTimeKey: ContentTimeLabel] = [:]
}

extension EnvironmentValues {
	var contentTimeValues: [ContentTimeKey: ContentTimeLabel] {
		get { self[ContentTimeValuesKey.self] }
		set { self[ContentTimeValuesKey.self] = newValue }
	}
}

/// Jedna instancja na listę, nigdy zadanie sieciowe na każdy wiersz.
@MainActor
final class ContentTimeListState: ObservableObject {
	@Published private(set) var records: [ContentTimeKey: ContentTimeRecord] = [:]
	private var generation = UUID()
	private var previousKeys: [ContentTimeKey] = []

	func load(_ requests: [ContentTimeRequest], refreshing: Bool, client: ContentTimeClient) async {
		let token = UUID()
		generation = token
		if refreshing {
			records = [:]
			await client.invalidate(previousKeys + requests.map(\.key))
			previousKeys = []
			return
		}
		previousKeys = requests.map(\.key)
		let allowed = Set(previousKeys)
		records = records.filter { allowed.contains($0.key) }
		let fetched = await client.fetch(requests.map(\.key))
		guard !Task.isCancelled, generation == token else { return }
		records = fetched
	}

	func values(_ requests: [ContentTimeRequest], now: Date) -> [ContentTimeKey: ContentTimeLabel] {
		var result: [ContentTimeKey: ContentTimeLabel] = [:]
		for request in requests {
			let record = records[request.key]
			result[request.key] = request.key.kind == .podcast
				? record?.tyflocentrum?.audioTime ?? .unavailable
				: record?.readingTime(now: now, sourceModified: request.modifiedGMT) ?? .unavailable
		}
		return result
	}
}

private struct ContentTimeListModifier: ViewModifier {
	let requests: [ContentTimeRequest]
	let refreshing: Bool
	@EnvironmentObject private var api: TyfloAPI
	@Environment(\.scenePhase) private var scenePhase
	@StateObject private var state = ContentTimeListState()
	@State private var now = Date()

	private struct Identity: Equatable {
		let requests: [ContentTimeRequest]
		let refreshing: Bool
	}

	func body(content: Content) -> some View {
		content
			.environment(\.contentTimeValues, state.values(requests, now: now))
			.task(id: Identity(requests: requests, refreshing: refreshing)) {
				now = Date()
				await state.load(requests, refreshing: refreshing, client: api.contentTimes)
			}
			// Dokładne wygaśnięcie także przy godzinami otwartym ekranie.
			.task(id: state.records) {
				now = Date()
				while let expiry = state.records.values.compactMap(\.expiresAt).filter({ $0 >= now && $0 <= now.addingTimeInterval(86401) }).min() {
					let delay = max(0.01, expiry.timeIntervalSinceNow + 0.01)
					do {
						try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
						now = Date()
					} catch { return }
				}
			}
			.onChange(of: scenePhase) { _, phase in
				if phase == .active { now = Date() }
			}
	}
}

extension View {
	func contentTimes(_ requests: [ContentTimeRequest], refreshing: Bool = false) -> some View {
		// Limit cache nie może odcinać pozycji istniejącej listy. Klient dzieli
		// pełny zestaw kluczy na paczki i osobno ogranicza pamięć współdzieloną.
		modifier(ContentTimeListModifier(requests: requests, refreshing: refreshing))
	}
}
