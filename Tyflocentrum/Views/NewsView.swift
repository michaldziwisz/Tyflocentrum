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

	func loadIfNeeded(_ fetch: @escaping () async -> [Item]) async {
		guard !hasLoaded else { return }
		await load(fetch)
	}

	func refresh(_ fetch: @escaping () async -> [Item]) async {
		items.removeAll(keepingCapacity: true)
		hasLoaded = false
		await load(fetch)
	}

	func load(_ fetch: @escaping () async -> [Item]) async {
		guard !isLoading else { return }
		isLoading = true
		defer { isLoading = false }

		let loadedItems = await fetch()
		guard !Task.isCancelled else { return }

		items = loadedItems
		hasLoaded = true
	}
}

struct NewsView: View {
	@EnvironmentObject var api: TyfloAPI
	@StateObject private var viewModel = AsyncListViewModel<Podcast>()
	var body: some View {
		NavigationView {
			List {
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
				await viewModel.refresh(api.getLatestPodcasts)
			}
			.task {
				await viewModel.loadIfNeeded(api.getLatestPodcasts)
			}
			.navigationTitle("Nowości")
		}
	}
}
