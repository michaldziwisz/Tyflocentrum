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
			await viewModel.refresh { await api.getPodcast(for: category) }
		}
		.task {
			await viewModel.loadIfNeeded { await api.getPodcast(for: category) }
		}
		.navigationTitle(category.name)
		.navigationBarTitleDisplayMode(.inline)
	}
}
