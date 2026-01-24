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
	let post: Podcast

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
	@StateObject private var viewModel = AsyncListViewModel<NewsItem>()
	@State private var playerPodcast: Podcast?

	private func fetchLatestItems() async throws -> [NewsItem] {
		async let podcastPosts: [Podcast] = api.fetchLatestPodcasts()
		async let articlePosts: [Podcast] = api.fetchLatestArticles()

		var combined: [NewsItem] = []
		var lastError: Error?

		do {
			let podcasts = try await podcastPosts
			combined.append(contentsOf: podcasts.map { NewsItem(kind: .podcast, post: $0) })
		} catch {
			lastError = error
		}

		do {
			let articles = try await articlePosts
			combined.append(contentsOf: articles.map { NewsItem(kind: .article, post: $0) })
		} catch {
			lastError = error
		}

		guard !combined.isEmpty else {
			throw lastError ?? URLError(.badServerResponse)
		}

		return combined.sorted(by: NewsItem.isSortedBefore)
	}

	var body: some View {
		NavigationView {
			List {
				AsyncListStatusSection(
					errorMessage: viewModel.errorMessage,
					isLoading: viewModel.isLoading,
					hasLoaded: viewModel.hasLoaded,
					isEmpty: viewModel.items.isEmpty,
					emptyMessage: "Brak nowych treści.",
					retryAction: { await viewModel.refresh(fetchLatestItems) },
					retryIdentifier: "news.retry",
					isRetryDisabled: viewModel.isLoading
				)

				ForEach(viewModel.items) { item in
					NavigationLink {
						switch item.kind {
						case .podcast:
							DetailedPodcastView(podcast: item.post)
						case .article:
							DetailedArticleView(article: item.post)
						}
					} label: {
						ShortPodcastView(
							podcast: item.post,
							showsListenAction: item.kind == .podcast,
							onListen: item.kind == .podcast
								? { playerPodcast = item.post }
								: nil,
							leadingSystemImageName: item.kind.systemImageName,
							accessibilityKindLabel: item.kind.label,
							accessibilityIdentifierOverride: item.kind == .podcast
								? nil
								: "article.row.\(item.post.id)"
						)
					}
					.accessibilityRemoveTraits(.isButton)
				}
			}
			.accessibilityIdentifier("news.list")
			.refreshable {
				await viewModel.refresh(fetchLatestItems)
			}
			.task {
				await viewModel.loadIfNeeded(fetchLatestItems)
			}
			.navigationTitle("Nowości")
		}
		.sheet(item: $playerPodcast) { podcast in
			PodcastPlayerSheet(podcast: podcast)
		}
	}
}
