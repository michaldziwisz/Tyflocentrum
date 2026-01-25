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
	@State private var playerPodcast: Podcast?
	var body: some View {
		List {
			AsyncListStatusSection(
				errorMessage: viewModel.errorMessage,
				isLoading: viewModel.isLoading,
				hasLoaded: viewModel.hasLoaded,
				isEmpty: viewModel.items.isEmpty,
				emptyMessage: "Brak audycji w tej kategorii.",
				retryAction: { await viewModel.refresh { try await api.fetchPodcasts(for: category) } },
				retryIdentifier: "categoryPodcasts.retry",
				isRetryDisabled: viewModel.isLoading
			)

			ForEach(viewModel.items) { item in
				NavigationLink {
					DetailedPodcastView(podcast: item)
				} label: {
					ShortPodcastView(
						podcast: item,
						onListen: {
							playerPodcast = item
						}
					)
				}
				.accessibilityRemoveTraits(.isButton)
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
