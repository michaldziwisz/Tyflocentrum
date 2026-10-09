//
//  NewsView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 17/10/2022.
//

import Foundation
import SwiftUI
import UIKit

enum NewsItemKind: String {
	case podcast
	case article

	var label: String {
		switch self {
		case .podcast:
			return "Podcast"
		case .article:
			return "Artykuł"
		}
	}

	var systemImageName: String {
		switch self {
		case .podcast:
			return "mic.fill"
		case .article:
			return "doc.text.fill"
		}
	}

	var sortOrder: Int {
		switch self {
		case .podcast:
			return 0
		case .article:
			return 1
		}
	}
}

struct NewsItem: Identifiable {
	let kind: NewsItemKind
	let post: WPPostSummary

	var id: String {
		"\(kind.rawValue).\(post.id)"
	}

	static func isSortedBefore(_ lhs: NewsItem, _ rhs: NewsItem) -> Bool {
		if lhs.post.date != rhs.post.date {
			return lhs.post.date > rhs.post.date
		}
		if lhs.kind.sortOrder != rhs.kind.sortOrder {
			return lhs.kind.sortOrder < rhs.kind.sortOrder
		}
		return lhs.post.id > rhs.post.id
	}
}

@MainActor
final class AsyncListViewModel<Item>: ObservableObject {
	private var refreshTicket = UUID()
	@Published private(set) var items: [Item] = []
	@Published private(set) var hasLoaded = false
	@Published private(set) var contentTimeRevision = 0
	@Published private(set) var isLoading = false
	@Published private(set) var errorMessage: String?

	func seed(_ cachedItems: [Item]) {
		guard items.isEmpty else { return }
		guard !cachedItems.isEmpty else { return }
		items = cachedItems
	}

	func loadIfNeeded(_ fetch: @escaping () async throws -> [Item], timeoutSeconds: TimeInterval = 45) async {
		// Ta sama pułapka co w `PagedFeedViewModel` (patrz komentarz tam):
		// `load` wychodzi przez `Task.isCancelled` przed ustawieniem `hasLoaded`,
		// więc samo `guard !hasLoaded` zamykało widok w stanie „pusto i nic się
		// nie dzieje” na stałe. Ponowne wejście na ekran ma podjąć próbę.
		guard !hasLoaded || (items.isEmpty && errorMessage == nil && !isLoading) else { return }
		await load(fetch, timeoutSeconds: timeoutSeconds)
	}

	func refresh(_ fetch: @escaping () async throws -> [Item], timeoutSeconds: TimeInterval = 45) async {
		guard !Task.isCancelled else { return }
		let ticket = UUID()
		refreshTicket = ticket
		while isLoading {
			do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
		}
		guard refreshTicket == ticket, !Task.isCancelled else { return }
		let hadItems = !items.isEmpty
		hasLoaded = false
		errorMessage = nil
		await load(fetch, timeoutSeconds: timeoutSeconds)
		if hadItems, !Task.isCancelled { contentTimeRevision += 1 }
	}

	func load(_ fetch: @escaping () async throws -> [Item], timeoutSeconds: TimeInterval = 45) async {
		guard !isLoading else { return }
		isLoading = true

		let fallbackErrorMessage = "Nie udało się pobrać danych. Spróbuj ponownie."
		let timeoutErrorMessage = "Ładowanie trwa zbyt długo. Spróbuj ponownie."

		errorMessage = nil
		var pendingErrorMessage: String?
		defer {
			isLoading = false
			if let pendingErrorMessage {
				errorMessage = pendingErrorMessage
			}
		}

		do {
			let loadedItems = try await withTimeout(timeoutSeconds) { try await fetch() }

			guard !Task.isCancelled else { return }
			items = loadedItems
			hasLoaded = true
		} catch {
			guard !Task.isCancelled else { return }

			if error is AsyncTimeoutError {
				pendingErrorMessage = timeoutErrorMessage
			} else {
				pendingErrorMessage = fallbackErrorMessage
			}
			hasLoaded = true
		}
	}
}

@MainActor
final class NewsFeedViewModel: ObservableObject {
	private struct SourceState {
		let kind: NewsItemKind
		var nextPage: Int = 1
		var totalPages: Int?
		var nextIndex: Int = 0
		var hasMore: Bool = true
		var didFailLastFetch: Bool = false
		var buffer: [WPPostSummary] = []

		var nextItem: WPPostSummary? {
			guard nextIndex < buffer.count else { return nil }
			return buffer[nextIndex]
		}

		mutating func advance() {
			nextIndex += 1
		}

		mutating func reset() {
			nextPage = 1
			totalPages = nil
			nextIndex = 0
			hasMore = true
			didFailLastFetch = false
			buffer.removeAll(keepingCapacity: true)
		}

		mutating func trimConsumedIfNeeded(threshold: Int = 50) {
			guard nextIndex >= threshold else { return }
			buffer.removeFirst(nextIndex)
			nextIndex = 0
		}
	}

	@Published private(set) var items: [NewsItem] = []
	@Published private(set) var hasLoaded = false
	@Published private(set) var contentTimeRevision = 0
	@Published private(set) var isLoading = false
	@Published private(set) var isLoadingMore = false
	@Published private(set) var errorMessage: String?
	@Published private(set) var loadMoreErrorMessage: String?
	@Published private(set) var canLoadMore = false

	/// Komunikat do jednorazowego ogłoszenia czytnikowi ekranu po doklejeniu nowości.
	@Published private(set) var komunikatDostepnosci: String?
	/// Element, na którym trzeba zakotwiczyć przewijanie po doklejeniu wpisów na górę.
	@Published private(set) var kotwicaPrzewijania: String?

	private(set) var swiezosc = StanSwiezosci()
	private let strategia = StrategiaOdswiezania()

	private let requestTimeoutSeconds: TimeInterval
	private let sourcePerPage: Int
	private let initialBatchSize: Int
	private let loadMoreBatchSize: Int
	private var requestGeneration = UUID()
	private var refreshTicket = UUID()

	private var podcasts = SourceState(kind: .podcast)
	private var articles = SourceState(kind: .article)
	private var seenIDs = Set<String>()

	init(
		requestTimeoutSeconds: TimeInterval = 20,
		sourcePerPage: Int = 20,
		initialBatchSize: Int = 40,
		loadMoreBatchSize: Int = 20
	) {
		if ProcessInfo.processInfo.arguments.contains("UI_TESTING_FAST_TIMEOUTS") {
			self.requestTimeoutSeconds = 2
		} else {
			self.requestTimeoutSeconds = requestTimeoutSeconds
		}
		self.sourcePerPage = max(1, sourcePerPage)
		self.initialBatchSize = max(1, initialBatchSize)
		self.loadMoreBatchSize = max(1, loadMoreBatchSize)
	}

	func loadIfNeeded(api: TyfloAPI) async {
		while isLoading {
			do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
		}
		guard !hasLoaded, !Task.isCancelled else { return }
		await refresh(api: api)
	}

	/// Odświeżenie, które NIE psuje pozycji czytania ani fokusu czytnika ekranu.
	///
	/// Znane ID otrzymują świeże wartości bez zmiany kolejności i kotwicy.
	/// Nowe wpisy są dokładane na górze. Pełny ręczny refresh także zachowuje
	/// istniejącą listę, gdy zmieniły się wyłącznie wartości znanych wpisów. Wywołuje ją powrót
	/// aplikacji z tła i wejście na zakładkę, czyli sytuacje, w których użytkownik
	/// NIE prosił o przebudowę ekranu — a osoba czytająca listę czytnikiem straciłaby
	/// wtedy miejsce, w którym była.
	///
	/// Pobieramy tylko PIERWSZĄ stronę każdego źródła. Odtwarzanie całej paginacji
	/// przy każdym powrocie do aplikacji byłoby kilkunastoma żądaniami po to, żeby
	/// niemal zawsze dostać dane, które już mamy.
	func odswiezPoPowrocie(api: TyfloAPI, powod: PowodOdswiezenia = .powrotZTla) async {
		guard strategia.czyOdswiezyc(
			powod: powod,
			ostatniSukces: swiezosc.ostatniSukces,
			ostatniaProba: swiezosc.ostatniaProba,
			trwaPobieranie: isLoading || isLoadingMore
		) else { return }

		// Bez danych nie ma czego scalać — wtedy zwykłe pełne wczytanie jest właściwe.
		guard !items.isEmpty else {
			await refresh(api: api)
			return
		}

		let generation = UUID()
		requestGeneration = generation
		isLoading = true
		swiezosc.zanotujProbe()

		var udaneScalenie = false
		defer {
			if requestGeneration == generation {
				isLoading = false
				if udaneScalenie {
					swiezosc.zanotujSukces()
				}
			}
		}

		let porcja = NewsFeedViewModel(
			requestTimeoutSeconds: requestTimeoutSeconds,
			sourcePerPage: sourcePerPage,
			initialBatchSize: sourcePerPage,
			loadMoreBatchSize: loadMoreBatchSize
		)
		traceRefresh("resume.await.before", generation: generation, scratch: porcja)
		await porcja.performRefreshInPlace(api: api)
		traceRefresh("resume.await.after", generation: generation, scratch: porcja)

		guard requestGeneration == generation, !Task.isCancelled else { return }

		// Nieudane pobranie w tym trybie jest CICHE. Użytkownik o nic nie prosił,
		// więc nie zabieramy mu listy, którą czyta, i nie zamieniamy jej na komunikat
		// o błędzie — zostaje karencja z `StrategiaOdswiezania`, a lista bez zmian.
		guard !porcja.items.isEmpty else { return }
		udaneScalenie = true

		let wynik = ScalanieNowosci.scal(
			biezace: items,
			swieze: porcja.items,
			identyfikator: { $0.id },
			czyNowszy: NewsItem.isSortedBefore
		)

		// ROZŁĄCZENIE LISTY OD SERWERA: gdy ŻADEN ze świeżo pobranych wpisów nie jest
		// nam znany, to nie jest „kilka nowości” — to znaczy, że nowych treści jest
		// więcej niż jedna strona i scalanie zrobiłoby DZIURĘ w ciągłości listy
		// (najnowsze wpisy, potem brak, potem stare). Wtedy uczciwiej przebudować
		// listę od nowa, mimo kosztu utraty pozycji: pokazanie niepełnej historii
		// jako ciągłej jest gorsze niż jednorazowy skok na początek.
		if wynik.liczbaNowych == porcja.items.count {
			isLoading = false
			await refresh(api: api)
			return
		}

		// Znane ID też niosą świeże audio inline. Aktualizacja wartości nie jest
		// nowym wpisem: kolejność i kotwica zostają, nie ogłaszamy nowości.
		let fresh = Dictionary(porcja.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		items = wynik.elementy.map { fresh[$0.id] ?? $0 }
		contentTimeRevision += 1
		guard wynik.maNowe else { return }
		// Kursory paginacji odnoszą się do stanu sprzed scalenia, więc kolejne
		// „załaduj starsze” mogłoby zwrócić wpisy, które właśnie doklejiliśmy.
		// Dopisanie ich do `seenIDs` sprawia, że zostaną odfiltrowane.
		for element in wynik.elementy.prefix(wynik.liczbaNowych) {
			seenIDs.insert(element.id)
		}
		kotwicaPrzewijania = wynik.kotwica
		komunikatDostepnosci = ScalanieNowosci.komunikatONowych(wynik.liczbaNowych)
	}

	/// Kasowanie komunikatu po ogłoszeniu — inaczej ten sam tekst mógłby zostać
	/// odczytany drugi raz przy kolejnym przerysowaniu widoku.
	func komunikatOdczytany() {
		komunikatDostepnosci = nil
	}

	func traceRefresh(_ phase: String, generation: UUID? = nil, ticket: UUID? = nil, scratch: NewsFeedViewModel? = nil, hadItems: Bool? = nil) {
		#if DEBUG
			guard ProcessInfo.processInfo.arguments.contains("UI_TESTING_TIME_REFRESH") else { return }
			let data: [String: Any] = ["phase": phase, "model": String(describing: ObjectIdentifier(self)),
			                           "cancelled": Task.isCancelled, "requestGeneration": requestGeneration.uuidString,
			                           "generation": generation?.uuidString ?? "nil", "refreshTicket": refreshTicket.uuidString,
			                           "ticket": ticket?.uuidString ?? "nil", "loading": isLoading, "loaded": hasLoaded,
			                           "hadItems": hadItems.map(String.init) ?? "nil", "revision": contentTimeRevision, "count": items.count, "scratchCount": scratch?.items.count ?? 0,
			                           "items": items.prefix(4).map { "\($0.id):\(String(describing: $0.post.tyflocentrum?.audioSeconds))" },
			                           "scratch": scratch.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
			                           "scratchItems": scratch?.items.prefix(4).map { "\($0.id):\(String(describing: $0.post.tyflocentrum?.audioSeconds))" } ?? []]
			if let bytes = try? JSONSerialization.data(withJSONObject: data, options: .sortedKeys), let text = String(data: bytes, encoding: .utf8) {
				NSLog("TIME_NEWS %@", text)
			}
		#endif
	}

	func refresh(api: TyfloAPI) async {
		traceRefresh("refresh.enter")
		guard !Task.isCancelled else { return }
		let ticket = UUID()
		refreshTicket = ticket
		if isLoading {
			while isLoading {
				do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
			}
			guard !Task.isCancelled else { return }
		}
		guard refreshTicket == ticket else { return }

		let generation = UUID()
		requestGeneration = generation

		isLoading = true
		isLoadingMore = false
		errorMessage = nil
		loadMoreErrorMessage = nil

		let previousHasLoaded = hasLoaded
		let hadItemsBeforeRefresh = !items.isEmpty
		traceRefresh("refresh.owned", generation: generation, ticket: ticket, hadItems: hadItemsBeforeRefresh)
		defer {
			traceRefresh("refresh.defer.before", generation: generation, ticket: ticket, hadItems: hadItemsBeforeRefresh)
			if requestGeneration == generation {
				hasLoaded = previousHasLoaded || hasLoaded
				isLoading = false
				if hadItemsBeforeRefresh, !Task.isCancelled { contentTimeRevision += 1 }

				// Never leave the user on an empty state without a retry path – in practice, the feed should never
				// be truly empty, and cancellations/errors would otherwise surface as “Brak nowych treści.”
				if items.isEmpty, errorMessage == nil, hasLoaded, !Task.isCancelled {
					errorMessage = "Nie udało się pobrać danych. Spróbuj ponownie."
				}
			}
		}

		let scratch = NewsFeedViewModel(
			requestTimeoutSeconds: requestTimeoutSeconds,
			sourcePerPage: sourcePerPage,
			initialBatchSize: initialBatchSize,
			loadMoreBatchSize: loadMoreBatchSize
		)
		traceRefresh("refresh.await.before", generation: generation, ticket: ticket, scratch: scratch, hadItems: hadItemsBeforeRefresh)
		await scratch.performRefreshInPlace(api: api)
		traceRefresh("refresh.await.after", generation: generation, ticket: ticket, scratch: scratch, hadItems: hadItemsBeforeRefresh)

		guard requestGeneration == generation else { return }
		if Task.isCancelled {
			if !hadItemsBeforeRefresh {
				errorMessage = "Nie udało się pobrać danych. Spróbuj ponownie."
				hasLoaded = true
			}
			return
		}

		if scratch.items.isEmpty {
			errorMessage = scratch.errorMessage ?? "Nie udało się pobrać danych. Spróbuj ponownie."
			hasLoaded = true
		} else {
			let onlyKnown = !items.isEmpty && scratch.items.allSatisfy { seenIDs.contains($0.id) }
			let fresh = Dictionary(scratch.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
			items = onlyKnown ? items.map { fresh[$0.id] ?? $0 } : scratch.items
			hasLoaded = true
			if !onlyKnown { canLoadMore = scratch.canLoadMore }
			loadMoreErrorMessage = scratch.loadMoreErrorMessage
			// Znacznik świeżości aktualizuje TAKŻE pełne odświeżenie, inaczej próg
			// z `StrategiaOdswiezania` liczyłby wiek od zimnego startu i strzelał
			// zaraz po tym, jak użytkownik sam odświeżył listę.
			swiezosc.zanotujSukces()

			if !onlyKnown {
				podcasts = scratch.podcasts
				articles = scratch.articles
				seenIDs = scratch.seenIDs
			}
		}

		traceRefresh("refresh.published", generation: generation, ticket: ticket, scratch: scratch, hadItems: hadItemsBeforeRefresh)

		// If the user triggers "load more" during refresh, `loadMore(api:)` will wait for `isLoading` to clear
		// instead of scheduling a separate follow-up task here. This avoids flakey overlaps and keeps the state
		// transitions deterministic (important for accessibility and tests).
	}

	func loadMore(api: TyfloAPI) async {
		while isLoading {
			guard !Task.isCancelled else { return }
			await Task.yield()
		}
		guard hasLoaded else {
			await loadIfNeeded(api: api)
			return
		}
		guard canLoadMore else { return }
		guard !isLoadingMore else { return }
		let generation = requestGeneration

		isLoadingMore = true
		defer { isLoadingMore = false }

		loadMoreErrorMessage = nil

		let initialCount = items.count
		await appendNextBatch(api: api, batchSize: loadMoreBatchSize, generation: generation)
		guard requestGeneration == generation else { return }

		if items.count == initialCount, canLoadMore {
			loadMoreErrorMessage = "Nie udało się pobrać kolejnych treści. Spróbuj ponownie."
		}
	}

	private func performRefreshInPlace(api: TyfloAPI) async {
		guard !isLoading else { return }
		resetForNewRequest()
		let generation = requestGeneration

		isLoading = true

		errorMessage = nil
		defer {
			if requestGeneration == generation {
				hasLoaded = true
				isLoading = false

				if items.isEmpty, !Task.isCancelled {
					errorMessage = "Nie udało się pobrać danych. Spróbuj ponownie."
				}
			}
		}

		await appendNextBatch(api: api, batchSize: initialBatchSize, generation: generation)
		guard requestGeneration == generation else { return }

		if items.isEmpty {
			// The initial merge fetch may fail transiently (e.g. timeouts/cancelled requests). Retry once to
			// avoid forcing the user to hit “Spróbuj ponownie” in common cases.
			try? await Task.sleep(nanoseconds: 250_000_000)
			guard requestGeneration == generation else { return }
			await appendNextBatch(api: api, batchSize: initialBatchSize, generation: generation)
		}
	}

	private func resetForNewRequest() {
		requestGeneration = UUID()
		items.removeAll(keepingCapacity: true)
		seenIDs.removeAll(keepingCapacity: true)
		podcasts.reset()
		articles.reset()
		canLoadMore = false
		hasLoaded = false
		isLoadingMore = false
		errorMessage = nil
		loadMoreErrorMessage = nil
	}

	private func fetchNextPage(api: TyfloAPI, source: inout SourceState) async -> Bool {
		guard source.hasMore else { return true }
		guard !source.didFailLastFetch else { return false }

		do {
			let nextPage = source.nextPage
			let perPage = sourcePerPage

			// Pierwszą stronę pobieramy Z POMINIĘCIEM lokalnych cache'ów.
			// Powód jest konkretny: `NoStoreInMemoryCache` trzyma odpowiedzi
			// tyfloswiat.pl przez 5 minut i był sprawdzany także wtedy, gdy
			// użytkownik sam pociągnął listę w dół — czyli ręczne odświeżenie
			// mogło oddać dane z pamięci i wyglądać jak „nie dociąga nowych treści”.
			// Dalsze strony to historia, która się nie zmienia, więc tam cache
			// jest pożądany i zostaje.
			let politykaCache: URLRequest.CachePolicy = nextPage == 1
				? .reloadIgnoringLocalCacheData
				: .useProtocolCachePolicy

			let page: TyfloAPI.WPPage<WPPostSummary>
			switch source.kind {
			case .podcast:
				page = try await withTimeout(requestTimeoutSeconds) {
					try await api.fetchPodcastSummariesPage(
						page: nextPage,
						perPage: perPage,
						cachePolicy: politykaCache
					)
				}
			case .article:
				page = try await withTimeout(requestTimeoutSeconds) {
					try await api.fetchArticleSummariesPage(
						page: nextPage,
						perPage: perPage,
						cachePolicy: politykaCache
					)
				}
			}

			if let totalPages = page.totalPages {
				source.totalPages = totalPages
			}

			source.didFailLastFetch = false
			source.nextPage += 1

			let pageItems = page.items
			if pageItems.isEmpty {
				source.hasMore = false
				return true
			}

			source.buffer.append(contentsOf: pageItems)

			if let totalPages = source.totalPages {
				source.hasMore = source.nextPage <= totalPages
			} else if pageItems.count < perPage {
				source.hasMore = false
			}
			return true
		} catch {
			source.didFailLastFetch = true
			return false
		}
	}

	private func fetchNextPodcastPage(api: TyfloAPI, generation: UUID) async -> Bool {
		guard requestGeneration == generation else { return false }
		var source = podcasts
		let result = await fetchNextPage(api: api, source: &source)
		guard requestGeneration == generation else { return false }
		podcasts = source
		return result
	}

	private func fetchNextArticlePage(api: TyfloAPI, generation: UUID) async -> Bool {
		guard requestGeneration == generation else { return false }
		var source = articles
		let result = await fetchNextPage(api: api, source: &source)
		guard requestGeneration == generation else { return false }
		articles = source
		return result
	}

	private func appendNextBatch(api: TyfloAPI, batchSize: Int, generation: UUID) async {
		guard requestGeneration == generation else { return }
		podcasts.didFailLastFetch = false
		articles.didFailLastFetch = false

		var added = 0
		var newItems: [NewsItem] = []
		newItems.reserveCapacity(batchSize)
		var iterations = 0
		let maxIterations = max(250, batchSize * 50)

		while added < batchSize {
			guard !Task.isCancelled else { return }
			guard requestGeneration == generation else { return }

			iterations += 1
			if iterations > maxIterations { break }

			let podcastNext = podcasts.nextItem
			let articleNext = articles.nextItem

			if podcastNext == nil, podcasts.hasMore {
				_ = await fetchNextPodcastPage(api: api, generation: generation)
				guard requestGeneration == generation else { return }
			}
			if articleNext == nil, articles.hasMore {
				_ = await fetchNextArticlePage(api: api, generation: generation)
				guard requestGeneration == generation else { return }
			}

			guard requestGeneration == generation else { return }
			guard let selected = selectNextItem() else { break }

			let item = NewsItem(kind: selected.kind, post: selected.post)
			if seenIDs.insert(item.id).inserted {
				newItems.append(item)
				added += 1
			}

			guard requestGeneration == generation else { return }
			podcasts.trimConsumedIfNeeded()
			articles.trimConsumedIfNeeded()
		}

		guard requestGeneration == generation else { return }
		if !newItems.isEmpty {
			items.append(contentsOf: newItems)
		}
		canLoadMore = podcasts.nextItem != nil || articles.nextItem != nil || podcasts.hasMore || articles.hasMore
	}

	private func selectNextItem() -> (kind: NewsItemKind, post: WPPostSummary)? {
		let p = podcasts.nextItem
		let a = articles.nextItem

		switch (p, a) {
		case (nil, nil):
			return nil
		case let (podcast?, nil):
			podcasts.advance()
			return (.podcast, podcast)
		case let (nil, article?):
			articles.advance()
			return (.article, article)
		case let (podcast?, article?):
			if podcast.date != article.date {
				if podcast.date > article.date {
					podcasts.advance()
					return (.podcast, podcast)
				}
				articles.advance()
				return (.article, article)
			}

			podcasts.advance()
			return (.podcast, podcast)
		}
	}
}

@MainActor
final class PagedFeedViewModel<Item: Identifiable & Decodable>: ObservableObject where Item.ID: Hashable {
	@Published private(set) var items: [Item] = []
	@Published private(set) var hasLoaded = false
	@Published private(set) var contentTimeRevision = 0
	@Published private(set) var isLoading = false
	@Published private(set) var isLoadingMore = false
	@Published private(set) var errorMessage: String?
	@Published private(set) var loadMoreErrorMessage: String?
	@Published private(set) var canLoadMore = false

	private let perPage: Int
	private var nextPage = 1
	private var totalPages: Int?
	private var seenIDs = Set<Item.ID>()
	private var requestGeneration = UUID()
	private var refreshTicket = UUID()
	private var refreshWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

	init(perPage: Int = 50) {
		self.perPage = perPage
	}

	func loadIfNeeded(fetchPage: @escaping (Int, Int) async throws -> TyfloAPI.WPPage<Item>) async {
		guard !Task.isCancelled else { return }
		// Nowe zadanie widoku musi doczekać końca starego, także anulowanego.
		// Po wznowieniu ponownie sprawdzamy stan, aby nie dublować udanego pobrania.
		while isLoading {
			await waitForCurrentRefresh()
			guard !Task.isCancelled else { return }
		}
		// Warunek celowo NIE jest samym `!hasLoaded`: gdy poprzednie zadanie
		// zostało anulowane po drodze, `hasLoaded` zostawało fałszywe, a lista
		// pusta bez komunikatu (zobaczone na zrzucie z run 33800599777). Wejście
		// na zakładkę ponownie ma wtedy podjąć próbę, a nie utknąć w pustce.
		guard !hasLoaded || (items.isEmpty && errorMessage == nil && !isLoading) else { return }
		await refresh(fetchPage: fetchPage)
	}

	private func waitForCurrentRefresh() async {
		let id = UUID()
		await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				guard isLoading, !Task.isCancelled else {
					continuation.resume()
					return
				}
				refreshWaiters[id] = continuation
			}
		} onCancel: {
			Task { @MainActor [weak self] in
				// Usunięcie przed resume daje jednego właściciela kontynuacji,
				// także gdy anulowanie zbiegnie się z końcem pobierania.
				self?.refreshWaiters.removeValue(forKey: id)?.resume()
			}
		}
	}

	func refresh(fetchPage: @escaping (Int, Int) async throws -> TyfloAPI.WPPage<Item>) async {
		guard !Task.isCancelled else { return }
		let ticket = UUID()
		refreshTicket = ticket
		while isLoading {
			await waitForCurrentRefresh()
			guard !Task.isCancelled else { return }
		}
		guard refreshTicket == ticket else { return }
		if !items.isEmpty {
			let token = UUID()
			requestGeneration = token
			isLoading = true
			defer {
				isLoading = false
				let waiters = Array(refreshWaiters.values)
				refreshWaiters.removeAll()
				for waiter in waiters {
					waiter.resume()
				}
			}
			let scratch = PagedFeedViewModel<Item>(perPage: perPage)
			await scratch.refresh(fetchPage: fetchPage)
			guard !Task.isCancelled, requestGeneration == token else { return }
			contentTimeRevision += 1
			guard !scratch.items.isEmpty else {
				errorMessage = scratch.errorMessage
				return
			}
			let onlyKnown = scratch.items.allSatisfy { seenIDs.contains($0.id) }
			let fresh = Dictionary(scratch.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
			items = onlyKnown ? items.map { fresh[$0.id] ?? $0 } : scratch.items
			if !onlyKnown {
				seenIDs = scratch.seenIDs
				nextPage = scratch.nextPage
				totalPages = scratch.totalPages
				canLoadMore = scratch.canLoadMore
			}
			errorMessage = nil
			loadMoreErrorMessage = nil
			return
		}
		reset()

		isLoading = true
		defer {
			isLoading = false
			let waiters = Array(refreshWaiters.values)
			refreshWaiters.removeAll()
			for waiter in waiters {
				waiter.resume()
			}
		}

		errorMessage = nil
		loadMoreErrorMessage = nil

		do {
			_ = try await appendNextPage(fetchPage: fetchPage)
			guard !Task.isCancelled else { return }

			if items.isEmpty {
				// PONOWIENIE PO NIEUDANYM PIERWSZYM ŻĄDANIU.
				// Wcześniej ta gałąź od razu pokazywała komunikat o błędzie
				// i czekała, aż użytkownik znajdzie przycisk „Spróbuj ponownie”.
				// Lista Nowości (`NewsFeedViewModel`) ponawiała w tej sytuacji
				// sama, a listy kategorii nie — czyli ta sama awaria sieci dawała
				// dwa różne zachowania, zależnie od zakładki.
				//
				// Dla osoby korzystającej z czytnika ekranu każdy dodatkowy krok
				// po nieudanym starcie to realny koszt: trzeba znaleźć przycisk,
				// który pojawił się gdzieś na ekranie. Jedno ciche ponowienie
				// załatwia typowy przypadek (chwilowy timeout przy starcie),
				// a przycisk zostaje na wypadek, gdyby i ono nie pomogło.
				try? await Task.sleep(nanoseconds: 250_000_000)
				guard !Task.isCancelled else { return }
				_ = try await appendNextPage(fetchPage: fetchPage)
				guard !Task.isCancelled else { return }
			}

			hasLoaded = true

			if items.isEmpty {
				errorMessage = "Nie udało się pobrać danych. Spróbuj ponownie."
			}
		} catch {
			guard !Task.isCancelled else { return }
			// Ta sama logika w gałęzi błędu: pierwszy nieudany strzał to najczęściej
			// chwilowy timeout, więc dajemy jedną cichą próbę, zamiast od razu
			// odsyłać użytkownika do przycisku.
			try? await Task.sleep(nanoseconds: 250_000_000)
			if !Task.isCancelled {
				do {
					_ = try await appendNextPage(fetchPage: fetchPage)
				} catch {
					// Druga próba też padła — dalej idziemy ścieżką komunikatu.
				}
			}
			guard !Task.isCancelled else { return }
			hasLoaded = true
			if items.isEmpty {
				errorMessage = "Nie udało się pobrać danych. Spróbuj ponownie."
			}
		}
	}

	func loadMore(fetchPage: @escaping (Int, Int) async throws -> TyfloAPI.WPPage<Item>) async {
		guard hasLoaded else {
			await loadIfNeeded(fetchPage: fetchPage)
			return
		}
		guard canLoadMore, !isLoading else { return }
		guard !isLoadingMore else { return }

		isLoadingMore = true
		defer { isLoadingMore = false }

		loadMoreErrorMessage = nil

		let initialCount = items.count
		let generation = requestGeneration
		do {
			_ = try await appendNextPage(fetchPage: fetchPage)
			guard !Task.isCancelled, generation == requestGeneration else { return }
			if items.count == initialCount, canLoadMore {
				loadMoreErrorMessage = "Nie udało się pobrać kolejnych treści. Spróbuj ponownie."
			}
		} catch {
			guard !Task.isCancelled, generation == requestGeneration else { return }
			loadMoreErrorMessage = "Nie udało się pobrać kolejnych treści. Spróbuj ponownie."
		}
	}

	private func reset() {
		items.removeAll(keepingCapacity: true)
		seenIDs.removeAll(keepingCapacity: true)
		nextPage = 1
		totalPages = nil
		canLoadMore = false
		hasLoaded = false
		errorMessage = nil
		loadMoreErrorMessage = nil
	}

	private func appendNextPage(fetchPage: @escaping (Int, Int) async throws -> TyfloAPI.WPPage<Item>) async throws -> Int {
		guard nextPage > 0 else {
			canLoadMore = false
			return 0
		}

		let generation = requestGeneration
		let page = try await fetchPage(nextPage, perPage)
		guard generation == requestGeneration else { return 0 }
		// Transport może oddać dane mimo anulowania. Nie publikujemy ich
		// ani nie przesuwamy numeru strony opuszczonego zadania.
		try Task.checkCancellation()

		if let totalPages = page.totalPages {
			self.totalPages = totalPages
		}

		nextPage += 1

		var insertedCount = 0
		if !page.items.isEmpty {
			var newItems: [Item] = []
			newItems.reserveCapacity(page.items.count)
			for item in page.items {
				if seenIDs.insert(item.id).inserted {
					newItems.append(item)
					insertedCount += 1
				}
			}
			items.append(contentsOf: newItems)
		}

		if page.items.isEmpty {
			canLoadMore = false
		} else if let totalPages = totalPages {
			canLoadMore = nextPage <= totalPages
		} else {
			canLoadMore = page.items.count == perPage
		}

		return insertedCount
	}
}

typealias PostSummariesFeedViewModel = PagedFeedViewModel<WPPostSummary>

struct AsyncListStatusSection: View {
	let errorMessage: String?
	let isLoading: Bool
	let hasLoaded: Bool
	let isEmpty: Bool
	let emptyMessage: String
	let loadingMessage: String
	let retryAction: (() async -> Void)?
	let retryIdentifier: String?
	let isRetryDisabled: Bool
	let retryHint: String

	init(
		errorMessage: String?,
		isLoading: Bool,
		hasLoaded: Bool,
		isEmpty: Bool,
		emptyMessage: String,
		loadingMessage: String = "Ładowanie…",
		retryAction: (() async -> Void)? = nil,
		retryIdentifier: String? = nil,
		isRetryDisabled: Bool = false,
		retryHint: String = "Ponawia pobieranie danych."
	) {
		self.errorMessage = errorMessage
		self.isLoading = isLoading
		self.hasLoaded = hasLoaded
		self.isEmpty = isEmpty
		self.emptyMessage = emptyMessage
		self.loadingMessage = loadingMessage
		self.retryAction = retryAction
		self.retryIdentifier = retryIdentifier
		self.isRetryDisabled = isRetryDisabled
		self.retryHint = retryHint
	}

	@ViewBuilder
	var body: some View {
		if let errorMessage {
			Section {
				Text(errorMessage)
					.foregroundColor(.secondary)

				if let retryAction {
					if let retryIdentifier {
						Button("Spróbuj ponownie") {
							Task { await retryAction() }
						}
						.accessibilityHint(retryHint)
						.accessibilityIdentifier(retryIdentifier)
						.disabled(isRetryDisabled)
						.accessibilityHidden(isRetryDisabled)
					} else {
						Button("Spróbuj ponownie") {
							Task { await retryAction() }
						}
						.accessibilityHint(retryHint)
						.disabled(isRetryDisabled)
						.accessibilityHidden(isRetryDisabled)
					}
				}
			}
		} else if isLoading && isEmpty {
			Section {
				ProgressView(loadingMessage)
			}
		} else if hasLoaded && isEmpty {
			Section {
				Text(emptyMessage)
					.foregroundColor(.secondary)
			}
		} else if isEmpty {
			// MARTWY STAN: brak błędu, nic się nie ładuje, a `hasLoaded` jest
			// fałszywe. Wcześniej NIE BYŁO tu żadnej gałęzi, więc lista
			// pokazywała PUSTY EKRAN bez komunikatu, bez kręciołka i bez drogi
			// wyjścia — użytkownik nie miał nawet informacji, że coś się nie udało.
			//
			// ZOBACZONE NA ZRZUCIE (run 33800599777, ekran Podcasty): pod
			// wierszem „Wszystkie kategorie” zupełna pustka. To nie był problem
			// samego testu — tak wyglądała aplikacja dla użytkownika, a osoba
			// niewidoma dostawała po prostu ekran, na którym nie ma nic do
			// przeczytania.
			//
			// Jak się tu trafia: `refresh` wychodzi przez `Task.isCancelled`
			// zanim ustawi `hasLoaded` (SwiftUI anuluje zadanie `.task`, gdy widok
			// zniknie na moment). `loadIfNeeded` też już nie pomoże, bo `.task`
			// nie odpala się ponownie bez przemontowania widoku.
			Section {
				Text("Nie udało się pobrać danych. Spróbuj ponownie.")
					.foregroundColor(.secondary)

				if let retryAction {
					Button("Spróbuj ponownie") {
						Task { await retryAction() }
					}
					.accessibilityHint(retryHint)
					.accessibilityIdentifier(retryIdentifier ?? "asyncList.retry")
					.disabled(isRetryDisabled)
					.accessibilityHidden(isRetryDisabled)
				}
			}
		}
	}
}

struct NewsView: View {
	@EnvironmentObject var api: TyfloAPI
	@EnvironmentObject private var settings: SettingsStore
	@StateObject private var viewModel = NewsFeedViewModel()
	@State private var playerPodcast: Podcast?

	/// Bramka na zakładkę: `TabView` trzyma odwiedzone widoki zamontowane, więc bez
	/// tego warunku powrót z tła odpalałby pobranie w KAŻDEJ odwiedzonej zakładce
	/// naraz — pięć razy więcej ruchu po to, żeby zobaczyć jeden ekran.
	@Environment(\.aktywnaZakladka) private var aktywnaZakladka
	@Environment(\.scenePhase) private var scenePhase

	/// Identyfikator wpisu, na którym trzymamy widok. Bez tego doklejenie nowości
	/// na górę przesunęłoby treść pod palcem czytającego.
	@State private var pozycjaListy: String?
	@State private var visible = false

	var body: some View {
		NavigationStack {
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 0) {
					NewsStatusView(
						errorMessage: viewModel.errorMessage,
						isLoading: viewModel.isLoading,
						hasLoaded: viewModel.hasLoaded,
						isEmpty: viewModel.items.isEmpty,
						emptyMessage: "Brak nowych treści.",
						retryAction: { await viewModel.refresh(api: api) },
						retryIdentifier: "news.retry",
						isRetryDisabled: viewModel.isLoading
					)

					ForEach(viewModel.items) { item in
						let stubPodcast = item.post.asPodcastStub()

						// Wiersz i separator w JEDNYM kontenerze ze stabilnym `.id`.
						// `scrollPosition(id:)` kotwiczy widok po tożsamości elementu w
						// `scrollTargetLayout`, więc bez tego identyfikatora doklejenie
						// nowości na górę przesunęłoby treść pod palcem czytającego.
						VStack(alignment: .leading, spacing: 0) {
							NavigationLink {
								switch item.kind {
								case .podcast:
									LazyDetailedPodcastView(summary: item.post)
								case .article:
									LazyDetailedArticleView(summary: item.post)
								}
							} label: {
								ShortPodcastView(
									podcast: stubPodcast,
									showsListenAction: item.kind == .podcast,
									onListen: item.kind == .podcast
										? { playerPodcast = stubPodcast }
										: nil,
									leadingSystemImageName: item.kind.systemImageName,
									accessibilityKindLabel: item.kind.label,
									accessibilityIdentifierOverride: item.kind == .podcast
										? nil
										: "article.row.\(item.post.id)",
									favoriteItem: item.kind == .podcast
										? .podcast(item.post)
										: .article(summary: item.post, origin: .post)
								)
								.padding(.horizontal)
								.padding(.vertical, 12)
								.frame(maxWidth: .infinity, alignment: .leading)
							}
							.buttonStyle(.plain)
							.accessibilityRemoveTraits(.isButton)
							.onAppear {
								guard item.id == viewModel.items.last?.id else { return }
								Task { await viewModel.loadMore(api: api) }
							}

							Divider()
								.padding(.leading, 16)
						}
						.id(item.id)
					}

					if viewModel.errorMessage == nil, viewModel.hasLoaded {
						NewsLoadMoreStatusView(
							errorMessage: viewModel.loadMoreErrorMessage,
							isLoadingMore: viewModel.isLoadingMore,
							retryAction: { await viewModel.loadMore(api: api) },
							isRetryDisabled: viewModel.isLoadingMore
						)
					}
				}
			}
			.accessibilityIdentifier("news.list")
			.scrollIndicators(.visible)
			.scrollTargetLayout()
			.scrollPosition(id: $pozycjaListy, anchor: .top)
			.refreshable {
				viewModel.traceRefresh("gesture.enter")
				await viewModel.refresh(api: api)
				viewModel.traceRefresh("gesture.exit")
			}
			.contentTimes(viewModel.items.filter { $0.kind == .article }.map { ContentTimeRequest($0.post, kind: .posts) }, refreshing: viewModel.isLoading, revision: viewModel.contentTimeRevision, automatic: false)
			.task {
				viewModel.traceRefresh("view.task.enter")
				await viewModel.loadIfNeeded(api: api)
				viewModel.traceRefresh("view.task.exit")
			}
			// POWRÓT APLIKACJI DO PIERWSZEGO PLANU. To jest sedno naprawy: bez tego
			// `.task` powyżej nie odpala się ponownie (widok nie został odmontowany),
			// a strażnik `hasLoaded` i tak by nic nie pobrał.
			//
			// Reagujemy na PRZEJŚCIE do `.active`, nie na sam fakt bycia aktywnym, i
			// tylko na widocznej zakładce. Próg czasu pilnuje `StrategiaOdswiezania`.
			.onAppear {
				visible = true
				guard viewModel.hasLoaded else { return }
				Task { await viewModel.odswiezPoPowrocie(api: api, powod: .wejscieNaEkran) }
			}
			.onDisappear { visible = false }
			.onChange(of: scenePhase) { staraFaza, nowaFaza in
				guard nowaFaza == .active, staraFaza != .active, visible else { return }
				guard aktywnaZakladka == ZakladkaAplikacji.nowosci else { return }
				Task { await viewModel.odswiezPoPowrocie(api: api, powod: .powrotZTla) }
			}
			// WEJŚCIE NA ZAKŁADKĘ. Osobny przypadek od powrotu z tła: aplikacja może
			// być na wierzchu godzinami, a użytkownik wraca na Nowości z innej zakładki
			// — wtedy scenePhase się nie zmienia i bez tego warunku dane zostałyby stare.
			.onChange(of: aktywnaZakladka) { _, nowa in
				guard nowa == ZakladkaAplikacji.nowosci, visible else { return }
				Task { await viewModel.odswiezPoPowrocie(api: api, powod: .wejscieNaEkran) }
			}
			// Zakotwiczenie widoku na wpisie, który był pierwszy przed doklejeniem.
			.onChange(of: viewModel.kotwicaPrzewijania) { _, kotwica in
				guard let kotwica else { return }
				pozycjaListy = kotwica
			}
			// OGŁOSZENIE DLA CZYTNIKA. Wysyłane PO scaleniu i z opóźnieniem, bo w chwili
			// powrotu do aplikacji VoiceOver mówi swoje (nazwa aplikacji, element z
			// fokusem) i natychmiastowy komunikat zostałby zagłuszony. Liczba nowych
			// wpisów jest dodatkowo w nagłówku listy, więc informacja nie znika razem
			// z wypowiedzią.
			.onChange(of: viewModel.komunikatDostepnosci) { _, komunikat in
				guard let komunikat else { return }
				Task {
					try? await Task.sleep(nanoseconds: 1_200_000_000)
					guard !Task.isCancelled else { return }
					UIAccessibility.post(notification: .announcement, argument: komunikat)
					viewModel.komunikatOdczytany()
				}
			}
			.id(settings.contentKindLabelPosition)
			.withAppMenu()
			.navigationTitle("Nowości")
			.navigationBarTitleDisplayMode(.inline)
			.navigationDestination(item: $playerPodcast) { podcast in
				PodcastPlayerView(podcast: podcast)
			}
		}
	}

	private struct NewsStatusView: View {
		let errorMessage: String?
		let isLoading: Bool
		let hasLoaded: Bool
		let isEmpty: Bool
		let emptyMessage: String
		let retryAction: (() async -> Void)?
		let retryIdentifier: String?
		let isRetryDisabled: Bool

		var body: some View {
			if let errorMessage {
				VStack(alignment: .leading, spacing: 12) {
					Text(errorMessage)
						.foregroundColor(.secondary)

					if let retryAction {
						if let retryIdentifier {
							Button("Spróbuj ponownie") {
								Task { await retryAction() }
							}
							.accessibilityHint("Ponawia pobieranie danych.")
							.accessibilityIdentifier(retryIdentifier)
							.disabled(isRetryDisabled)
							.accessibilityHidden(isRetryDisabled)
						} else {
							Button("Spróbuj ponownie") {
								Task { await retryAction() }
							}
							.accessibilityHint("Ponawia pobieranie danych.")
							.disabled(isRetryDisabled)
							.accessibilityHidden(isRetryDisabled)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal)
				.padding(.vertical, 16)
			} else if isLoading, isEmpty {
				ProgressView("Ładowanie…")
					.frame(maxWidth: .infinity)
					.padding(.vertical, 24)
			} else if hasLoaded, isEmpty {
				Text(emptyMessage)
					.foregroundColor(.secondary)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 24)
			}
		}
	}

	private struct NewsLoadMoreStatusView: View {
		let errorMessage: String?
		let isLoadingMore: Bool
		let retryAction: (() async -> Void)?
		let isRetryDisabled: Bool

		var body: some View {
			if let errorMessage {
				VStack(alignment: .leading, spacing: 12) {
					Text(errorMessage)
						.foregroundColor(.secondary)

					if let retryAction {
						Button("Spróbuj ponownie") {
							Task { await retryAction() }
						}
						.disabled(isRetryDisabled)
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal)
				.padding(.vertical, 16)
			} else if isLoadingMore {
				ProgressView("Ładowanie starszych treści…")
					.frame(maxWidth: .infinity)
					.padding(.vertical, 24)
			}
		}
	}
}
