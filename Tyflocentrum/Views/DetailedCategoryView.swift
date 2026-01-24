//
//  DetailedCategoryView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 10/11/2022.
//

import SwiftUI

struct DetailedCategoryView: View {
	let category: Category
	@EnvironmentObject var api: TyfloAPI
	@StateObject private var viewModel = AsyncListViewModel<Podcast>()
	var body: some View {
		List {
			if let errorMessage = viewModel.errorMessage {
				Section {
					Text(errorMessage)
						.foregroundColor(.secondary)

					Button("Spróbuj ponownie") {
						Task {
							await viewModel.refresh { try await api.fetchPodcasts(for: category) }
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
		.accessibilityIdentifier("categoryPodcasts.list")
		.refreshable {
			await viewModel.refresh { try await api.fetchPodcasts(for: category) }
		}
		.task {
			await viewModel.loadIfNeeded { try await api.fetchPodcasts(for: category) }
		}
		.navigationTitle(category.name)
		.navigationBarTitleDisplayMode(.inline)
	}
}
