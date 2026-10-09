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

	private var lastRevision = 0
	private var lastActivation = 0
	private var freshness = StanSwiezosci()
	private var loading = false

	func shouldResume(now: Date = Date()) -> Bool {
		StrategiaOdswiezania().czyOdswiezyc(powod: .powrotZTla,
		                                    ostatniSukces: freshness.ostatniSukces, ostatniaProba: freshness.ostatniaProba,
		                                    trwaPobieranie: loading, teraz: now)
	}

	func update(_ requests: [ContentTimeRequest], revision: Int, activation: Int,
	            client: ContentTimeClient, now: Date = Date()) async
	{
		let manual = revision != lastRevision
		let resumed = activation != lastActivation
		lastActivation = activation
		if resumed, !manual, !StrategiaOdswiezania().czyOdswiezyc(
			powod: .powrotZTla, ostatniSukces: freshness.ostatniSukces,
			ostatniaProba: freshness.ostatniaProba, trwaPobieranie: loading, teraz: now
		) { return }
		if await load(requests, refreshing: manual || resumed, client: client, now: now) {
			lastRevision = revision
		}
	}

	@discardableResult
	func load(_ requests: [ContentTimeRequest], refreshing: Bool, client: ContentTimeClient, now: Date = Date()) async -> Bool {
		guard !Task.isCancelled else { return false }
		let token = UUID()
		generation = token
		loading = true
		freshness.zanotujProbe(teraz: now)
		defer { if generation == token { loading = false } }
		#if DEBUG
			if ProcessInfo.processInfo.arguments.contains("UI_TESTING_TIME_REFRESH") {
				NSLog("TIME_STATE instance=%@ client=%@ force=%d keys=%@",
				      String(describing: ObjectIdentifier(self)), String(describing: ObjectIdentifier(client)),
				      refreshing ? 1 : 0, requests.map { "\($0.key.kind.rawValue).\($0.key.id)" }.joined(separator: ","))
			}
		#endif
		let oldKeys = previousKeys
		previousKeys = requests.map(\.key)
		let allowed = Set(previousKeys)
		// Zachowujemy dobre dane podczas oczekiwania, nie wyzerowujemy wierszy.
		records = records.filter { allowed.contains($0.key) }
		if refreshing { await client.invalidate(oldKeys + previousKeys) }
		guard !Task.isCancelled, generation == token else { return false }
		let fetched = await client.fetch(previousKeys)
		guard !Task.isCancelled, generation == token else { return false }
		if records != fetched { records = fetched }
		if !fetched.isEmpty { freshness.zanotujSukces(teraz: now) }
		return true
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
	let revision: Int
	let automatic: Bool
	@EnvironmentObject private var api: TyfloAPI
	@Environment(\.scenePhase) private var scenePhase
	@StateObject private var state = ContentTimeListState()
	@State private var now = Date()
	@State private var activation = 0
	@State private var visible = false

	private struct Identity: Equatable {
		let requests: [ContentTimeRequest]
		let refreshing: Bool
		let revision: Int
		let activation: Int
	}

	func body(content: Content) -> some View {
		content
			.environment(\.contentTimeValues, state.values(requests, now: now))
			.background {
				// Zadania metadanych mają własny węzeł cyklu życia. Zmiana
				// ich identyfikatora nie może anulować gestu samej listy.
				Color.clear
					.frame(width: 0, height: 0)
					.accessibilityHidden(true)
					.task(id: Identity(requests: requests, refreshing: refreshing, revision: revision, activation: activation)) {
						now = Date()
						guard !refreshing else { return }
						await state.update(requests, revision: revision, activation: activation, client: api.contentTimes)
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
			}
			.onAppear { visible = true }
			.onDisappear { visible = false }
			.onChange(of: scenePhase) { old, phase in
				guard phase == .active, old != .active, visible, automatic else { return }
				now = Date()
				guard state.shouldResume(now: now) else { return }
				activation += 1
			}
	}
}

private struct ContentListResumeModifier: ViewModifier {
	let revision: Int
	let action: () async -> Void
	let succeeded: Bool
	@Environment(\.scenePhase) private var scenePhase
	@State private var freshness = StanSwiezosci()
	@State private var visible = false
	@State private var running = false

	func body(content: Content) -> some View {
		content
			.onAppear {
				visible = true
				if freshness.ostatniaProba == nil {
					if succeeded { freshness.zanotujSukces() }
					else { freshness.zanotujProbe() }
				}
			}
			.onDisappear { visible = false }
			.onChange(of: succeeded) { _, success in
				if success { freshness.zanotujSukces() }
			}
			.onChange(of: revision) { _, _ in
				if succeeded { freshness.zanotujSukces() }
				else { freshness.zanotujProbe() }
			}
			.onChange(of: scenePhase) { old, phase in
				guard phase == .active, old != .active, visible,
				      StrategiaOdswiezania().czyOdswiezyc(powod: .powrotZTla,
				                                          ostatniSukces: freshness.ostatniSukces, ostatniaProba: freshness.ostatniaProba,
				                                          trwaPobieranie: running) else { return }
				running = true
				freshness.zanotujProbe()
				Task {
					await action()
					running = false
				}
			}
	}
}

extension View {
	func contentListResume(revision: Int, succeeded: Bool, action: @escaping () async -> Void) -> some View {
		modifier(ContentListResumeModifier(revision: revision, action: action, succeeded: succeeded))
	}

	func contentTimes(_ requests: [ContentTimeRequest], refreshing: Bool = false, revision: Int = 0, automatic: Bool = true) -> some View {
		// Limit cache nie może odcinać pozycji istniejącej listy. Klient dzieli
		// pełny zestaw kluczy na paczki i osobno ogranicza pamięć współdzieloną.
		modifier(ContentTimeListModifier(requests: requests, refreshing: refreshing, revision: revision, automatic: automatic))
	}
}
