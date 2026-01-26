//
//  NewsView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 17/10/2022.
//

import Foundation
import SwiftUI

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
	@Published private(set) var items: [Item] = []
	@Published private(set) var hasLoaded = false
	@Published private(set) var isLoading = false
	@Published private(set) var errorMessage: String?

	func seed(_ cachedItems: [Item]) {
		guard items.isEmpty else { return }
		guard !cachedItems.isEmpty else { return }
		items = cachedItems
	}

	func loadIfNeeded(_ fetch: @escaping () async throws -> [Item], timeoutSeconds: TimeInterval = 45) async {
		guard !hasLoaded else { return }
		await load(fetch, timeoutSeconds: timeoutSeconds)
	}

	func refresh(_ fetch: @escaping () async throws -> [Item], timeoutSeconds: TimeInterval = 45) async {
		hasLoaded = false
		errorMessage = nil
		await load(fetch, timeoutSeconds: timeoutSeconds)
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
			}
			else {
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
		var hasMore: Bool = true

		mutating func reset() {
			nextPage = 1
			totalPages = nil
			hasMore = true
		}
	}

	@Published private(set) var items: [NewsItem] = []
	@Published private(set) var hasLoaded = false
	@Published private(set) var isLoading = false
	@Published private(set) var isLoadingMore = false
	@Published private(set) var errorMessage: String?
	@Published private(set) var loadMoreErrorMessage: String?
	@Published private(set) var canLoadMore = false

	private let requestTimeoutSeconds: TimeInterval
	private let perPage: Int = 20

	private var podcasts = SourceState(kind: .podcast)
	private var articles = SourceState(kind: .article)
	private var seenIDs = Set<String>()

	init(requestTimeoutSeconds: TimeInterval = 20) {
		if ProcessInfo.processInfo.arguments.contains("UI_TESTING_FAST_TIMEOUTS") {
			self.requestTimeoutSeconds = 2
		}
		else {
			self.requestTimeoutSeconds = requestTimeoutSeconds
		}
	}

	func loadIfNeeded(api: TyfloAPI) async {
		guard !hasLoaded else { return }
		await refresh(api: api)
	}

	func refresh(api: TyfloAPI) async {
		guard !isLoading else { return }
		reset()

		isLoading = true
		defer { isLoading = false }

		errorMessage = nil

		var didLoadAnything = false

		do {
			let page = try await fetchNextPage(api: api, source: &podcasts)
			let newItems = uniqueItems(from: page.items, kind: .podcast)
			if !newItems.isEmpty {
				items.append(contentsOf: newItems)
				didLoadAnything = true
			} else if !page.items.isEmpty {
				podcasts.hasMore = false
			}
		} catch {
			// Ignored: partial results are fine.
		}

		do {
			let page = try await fetchNextPage(api: api, source: &articles)
			let newItems = uniqueItems(from: page.items, kind: .article)
			if !newItems.isEmpty {
				items.append(contentsOf: newItems)
				didLoadAnything = true
			} else if !page.items.isEmpty {
				articles.hasMore = false
			}
		} catch {
			// Ignored: partial results are fine.
		}

		if !items.isEmpty {
			items.sort(by: NewsItem.isSortedBefore)
		}
		hasLoaded = true

		canLoadMore = podcasts.hasMore || articles.hasMore

		if items.isEmpty, !didLoadAnything {
			errorMessage = "Nie udało się pobrać danych. Spróbuj ponownie."
		}
	}

	func loadMore(api: TyfloAPI) async {
		guard hasLoaded else {
			await loadIfNeeded(api: api)
			return
		}
		guard canLoadMore else { return }
		guard !isLoadingMore else { return }

		isLoadingMore = true
		defer { isLoadingMore = false }

		loadMoreErrorMessage = nil

		let initialCount = items.count
		var didAppendAnything = false

		if podcasts.hasMore {
			do {
				let page = try await fetchNextPage(api: api, source: &podcasts)
				let newItems = uniqueItems(from: page.items, kind: .podcast)
				if !newItems.isEmpty {
					items.append(contentsOf: newItems)
					didAppendAnything = true
				} else if !page.items.isEmpty {
					podcasts.hasMore = false
				}
			} catch {
				// ignored
			}
		}

		if articles.hasMore {
			do {
				let page = try await fetchNextPage(api: api, source: &articles)
				let newItems = uniqueItems(from: page.items, kind: .article)
				if !newItems.isEmpty {
					items.append(contentsOf: newItems)
					didAppendAnything = true
				} else if !page.items.isEmpty {
					articles.hasMore = false
				}
			} catch {
				// ignored
			}
		}

		if didAppendAnything {
			items.sort(by: NewsItem.isSortedBefore)
		}

		canLoadMore = podcasts.hasMore || articles.hasMore

		if items.count == initialCount, canLoadMore {
			loadMoreErrorMessage = "Nie udało się pobrać kolejnych treści. Spróbuj ponownie."
		}
	}

	private func reset() {
		items.removeAll(keepingCapacity: true)
		seenIDs.removeAll(keepingCapacity: true)
		podcasts.reset()
		articles.reset()
		canLoadMore = false
		hasLoaded = false
		errorMessage = nil
		loadMoreErrorMessage = nil
	}

	private func fetchNextPage(api: TyfloAPI, source: inout SourceState) async throws -> TyfloAPI.WPPage<WPPostSummary> {
		guard source.hasMore else { return TyfloAPI.WPPage(items: [], total: nil, totalPages: nil) }

		let nextPage = source.nextPage
		let page: TyfloAPI.WPPage<WPPostSummary>
		switch source.kind {
		case .podcast:
			page = try await withTimeout(requestTimeoutSeconds) {
				try await api.fetchPodcastSummariesPage(page: nextPage, perPage: perPage)
			}
		case .article:
			page = try await withTimeout(requestTimeoutSeconds) {
				try await api.fetchArticleSummariesPage(page: nextPage, perPage: perPage)
			}
		}

		if let totalPages = page.totalPages {
			source.totalPages = totalPages
		}

		source.nextPage += 1

		if page.items.isEmpty {
			source.hasMore = false
		} else if let totalPages = source.totalPages {
			source.hasMore = source.nextPage <= totalPages
		} else {
			source.hasMore = page.items.count == perPage
		}

		return page
	}

	private func uniqueItems(from summaries: [WPPostSummary], kind: NewsItemKind) -> [NewsItem] {
		guard !summaries.isEmpty else { return [] }

		var newItems: [NewsItem] = []
		newItems.reserveCapacity(summaries.count)
		for summary in summaries {
			let item = NewsItem(kind: kind, post: summary)
			if seenIDs.insert(item.id).inserted {
				newItems.append(item)
			}
		}
		return newItems
	}
}

@MainActor
final class PostSummariesFeedViewModel: ObservableObject {
	@Published private(set) var items: [WPPostSummary] = []
	@Published private(set) var hasLoaded = false
	@Published private(set) var isLoading = false
	@Published private(set) var isLoadingMore = false
	@Published private(set) var errorMessage: String?
	@Published private(set) var loadMoreErrorMessage: String?
	@Published private(set) var canLoadMore = false

	private let perPage: Int
	private var nextPage = 1
	private var totalPages: Int?
	private var seenIDs = Set<Int>()

	init(perPage: Int = 50) {
		self.perPage = perPage
	}

	func loadIfNeeded(fetchPage: @escaping (Int, Int) async throws -> TyfloAPI.WPPage<WPPostSummary>) async {
		guard !hasLoaded else { return }
		await refresh(fetchPage: fetchPage)
	}

	func refresh(fetchPage: @escaping (Int, Int) async throws -> TyfloAPI.WPPage<WPPostSummary>) async {
		guard !isLoading else { return }
		reset()

		isLoading = true
		defer { isLoading = false }

		errorMessage = nil
		loadMoreErrorMessage = nil

		do {
			_ = try await appendNextPage(fetchPage: fetchPage)
			guard !Task.isCancelled else { return }
			hasLoaded = true

			if items.isEmpty {
				errorMessage = "Nie udało się pobrać danych. Spróbuj ponownie."
			}
		} catch {
			guard !Task.isCancelled else { return }
			hasLoaded = true
			errorMessage = "Nie udało się pobrać danych. Spróbuj ponownie."
		}
	}

	func loadMore(fetchPage: @escaping (Int, Int) async throws -> TyfloAPI.WPPage<WPPostSummary>) async {
		guard hasLoaded else {
			await loadIfNeeded(fetchPage: fetchPage)
			return
		}
		guard canLoadMore else { return }
		guard !isLoadingMore else { return }

		isLoadingMore = true
		defer { isLoadingMore = false }

		loadMoreErrorMessage = nil

		let initialCount = items.count
		do {
			_ = try await appendNextPage(fetchPage: fetchPage)
			guard !Task.isCancelled else { return }
			if items.count == initialCount, canLoadMore {
				loadMoreErrorMessage = "Nie udało się pobrać kolejnych treści. Spróbuj ponownie."
			}
		} catch {
			guard !Task.isCancelled else { return }
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

	private func appendNextPage(fetchPage: @escaping (Int, Int) async throws -> TyfloAPI.WPPage<WPPostSummary>) async throws -> Int {
		guard nextPage > 0 else {
			canLoadMore = false
			return 0
		}

		let page = try await fetchPage(nextPage, perPage)

		if let totalPages = page.totalPages {
			self.totalPages = totalPages
		}

		nextPage += 1

		var insertedCount = 0
		if !page.items.isEmpty {
			var newItems: [WPPostSummary] = []
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
					}
					else {
						Button("Spróbuj ponownie") {
							Task { await retryAction() }
						}
						.accessibilityHint(retryHint)
						.disabled(isRetryDisabled)
					}
				}
			}
		}
		else if isLoading && isEmpty {
			Section {
				ProgressView(loadingMessage)
			}
		}
		else if hasLoaded && isEmpty {
			Section {
				Text(emptyMessage)
					.foregroundColor(.secondary)
			}
		}
	}
}

struct NewsView: View {
	@EnvironmentObject var api: TyfloAPI
	@StateObject private var viewModel = NewsFeedViewModel()
	@State private var playerPodcast: Podcast?

	var body: some View {
		NavigationView {
			List {
				AsyncListStatusSection(
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
								: "article.row.\(item.post.id)"
						)
					}
					.accessibilityRemoveTraits(.isButton)
					.onAppear {
						guard item.id == viewModel.items.last?.id else { return }
						Task { await viewModel.loadMore(api: api) }
					}
				}

				if viewModel.errorMessage == nil, viewModel.hasLoaded {
					if let loadMoreError = viewModel.loadMoreErrorMessage {
						Section {
							Text(loadMoreError)
								.foregroundColor(.secondary)

							Button("Spróbuj ponownie") {
								Task { await viewModel.loadMore(api: api) }
							}
							.disabled(viewModel.isLoadingMore)
						}
					}
					else if viewModel.isLoadingMore {
						Section {
							ProgressView("Ładowanie starszych treści…")
						}
					}
				}
			}
			.accessibilityIdentifier("news.list")
			.refreshable {
				await viewModel.refresh(api: api)
			}
			.task {
				await viewModel.loadIfNeeded(api: api)
			}
			.navigationTitle("Nowości")
			.navigationBarTitleDisplayMode(.inline)
			.background(
				NavigationLink(
					destination: Group {
						if let podcast = playerPodcast {
							PodcastPlayerView(podcast: podcast)
						}
						else {
							EmptyView()
						}
					},
					isActive: Binding(
						get: { playerPodcast != nil },
						set: { isActive in
							if !isActive {
								playerPodcast = nil
							}
						}
					)
				) {
					EmptyView()
				}
				.hidden()
			)
		}
	}
}
