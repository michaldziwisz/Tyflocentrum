//
//  NewsView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 17/10/2022.
//

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

	func loadIfNeeded(_ fetch: @escaping () async throws -> [Item]) async {
		guard !hasLoaded else { return }
		await load(fetch)
	}

	func refresh(_ fetch: @escaping () async throws -> [Item]) async {
		items.removeAll(keepingCapacity: true)
		hasLoaded = false
		errorMessage = nil
		await load(fetch)
	}

	func load(_ fetch: @escaping () async throws -> [Item]) async {
		guard !isLoading else { return }
		isLoading = true
		defer { isLoading = false }

		errorMessage = nil
		do {
			let loadedItems = try await fetch()
			guard !Task.isCancelled else { return }

			items = loadedItems
			hasLoaded = true
		} catch {
			guard !Task.isCancelled else { return }
			errorMessage = "Nie udało się pobrać danych. Spróbuj ponownie."
			hasLoaded = true
		}
	}
}

@MainActor
final class NewsFeedViewModel: ObservableObject {
	private struct SourceState {
		var kind: NewsItemKind
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
	@Published private(set) var isLoading = false
	@Published private(set) var isLoadingMore = false
	@Published private(set) var errorMessage: String?
	@Published private(set) var loadMoreErrorMessage: String?
	@Published private(set) var canLoadMore = false

	private let sourcePerPage = 20
	private let feedBatchSize = 20

	private var podcasts = SourceState(kind: .podcast)
	private var articles = SourceState(kind: .article)
	private var seenIDs = Set<String>()

	func loadIfNeeded(api: TyfloAPI) async {
		guard !hasLoaded else { return }
		await refresh(api: api)
	}

	func refresh(api: TyfloAPI) async {
		reset()

		guard !isLoading else { return }
		isLoading = true
		defer { isLoading = false }

		errorMessage = nil

		await appendNextBatch(api: api, batchSize: feedBatchSize)
		hasLoaded = true

		if items.isEmpty {
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
		await appendNextBatch(api: api, batchSize: feedBatchSize)

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

	private func fetchNextPage(api: TyfloAPI, source: inout SourceState) async -> Bool {
		guard source.hasMore else { return true }
		guard !source.didFailLastFetch else { return false }

		do {
			let page: TyfloAPI.WPPage<WPPostSummary>
			switch source.kind {
			case .podcast:
				page = try await api.fetchPodcastSummariesPage(page: source.nextPage, perPage: sourcePerPage)
			case .article:
				page = try await api.fetchArticleSummariesPage(page: source.nextPage, perPage: sourcePerPage)
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
			} else if pageItems.count < sourcePerPage {
				source.hasMore = false
			}
			return true
		} catch {
			source.didFailLastFetch = true
			return false
		}
	}

	private func fetchNextPodcastPage(api: TyfloAPI) async -> Bool {
		var source = podcasts
		let result = await fetchNextPage(api: api, source: &source)
		podcasts = source
		return result
	}

	private func fetchNextArticlePage(api: TyfloAPI) async -> Bool {
		var source = articles
		let result = await fetchNextPage(api: api, source: &source)
		articles = source
		return result
	}

	private func appendNextBatch(api: TyfloAPI, batchSize: Int) async {
		podcasts.didFailLastFetch = false
		articles.didFailLastFetch = false

		var added = 0
		while added < batchSize {
			guard !Task.isCancelled else { return }

			let podcastNext = podcasts.nextItem
			let articleNext = articles.nextItem

			if podcastNext == nil, podcasts.hasMore, articleNext == nil, articles.hasMore {
				async let podcastsFetched = fetchNextPodcastPage(api: api)
				async let articlesFetched = fetchNextArticlePage(api: api)
				_ = await (podcastsFetched, articlesFetched)
			}
			else {
				if podcastNext == nil && podcasts.hasMore {
					_ = await fetchNextPodcastPage(api: api)
				}
				if articleNext == nil && articles.hasMore {
					_ = await fetchNextArticlePage(api: api)
				}
			}

			guard let selected = selectNextItem() else { break }

			let item = NewsItem(kind: selected.kind, post: selected.post)
			if seenIDs.insert(item.id).inserted {
				items.append(item)
				added += 1
			}

			podcasts.trimConsumedIfNeeded()
			articles.trimConsumedIfNeeded()
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
	@State private var didPostAccessibilityLayoutChange = false
	@State private var accessibilityLayoutChangeTask: Task<Void, Never>?

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
					if let loadMoreErrorMessage = viewModel.loadMoreErrorMessage {
						Section {
							Text(loadMoreErrorMessage)
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
			.scrollIndicators(.visible)
			.refreshable {
				await viewModel.refresh(api: api)
			}
			.onChange(of: viewModel.items.count) { newCount in
				if newCount == 0 {
					didPostAccessibilityLayoutChange = false
					accessibilityLayoutChangeTask?.cancel()
					accessibilityLayoutChangeTask = nil
					return
				}
				guard !didPostAccessibilityLayoutChange else { return }
				didPostAccessibilityLayoutChange = true
				accessibilityLayoutChangeTask?.cancel()
				accessibilityLayoutChangeTask = Task {
					try? await Task.sleep(nanoseconds: 250_000_000)
					guard !Task.isCancelled else { return }
					UIAccessibility.post(notification: .layoutChanged, argument: nil)
				}
			}
			.accessibilityIdentifier("news.list")
			.task {
				await viewModel.loadIfNeeded(api: api)
			}
			.navigationTitle("Nowości")
		}
		.sheet(item: $playerPodcast) { podcast in
			PodcastPlayerSheet(podcast: podcast)
		}
	}
}
