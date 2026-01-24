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

struct NewsView: View {
	@EnvironmentObject var api: TyfloAPI
	@StateObject private var viewModel = AsyncListViewModel<Podcast>()
	var body: some View {
		NavigationView {
			List {
				if let errorMessage = viewModel.errorMessage {
					Section {
						Text(errorMessage)
							.foregroundColor(.secondary)

						Button("Spróbuj ponownie") {
							Task {
								await viewModel.refresh(api.fetchLatestPodcasts)
							}
						}
					}
				}

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
