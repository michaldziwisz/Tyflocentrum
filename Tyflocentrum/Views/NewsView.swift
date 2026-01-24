//
//  NewsView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 17/10/2022.
//

import Foundation
import SwiftUI

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
	@StateObject private var viewModel = AsyncListViewModel<Podcast>()
	var body: some View {
		NavigationView {
			List {
				AsyncListStatusSection(
					errorMessage: viewModel.errorMessage,
					isLoading: viewModel.isLoading,
					hasLoaded: viewModel.hasLoaded,
					isEmpty: viewModel.items.isEmpty,
					emptyMessage: "Brak nowych audycji.",
					retryAction: { await viewModel.refresh(api.fetchLatestPodcasts) },
					retryIdentifier: "news.retry",
					isRetryDisabled: viewModel.isLoading
				)

				ForEach(viewModel.items) { item in
					NavigationLink {
						DetailedPodcastView(podcast: item)
					} label: {
						ShortPodcastView(podcast: item)
					}
				}
			}
			.accessibilityIdentifier("news.list")
			.refreshable {
				await viewModel.refresh(api.fetchLatestPodcasts)
			}
			.task {
				await viewModel.loadIfNeeded(api.fetchLatestPodcasts)
			}
			.navigationTitle("Nowości")
		}
	}
}
