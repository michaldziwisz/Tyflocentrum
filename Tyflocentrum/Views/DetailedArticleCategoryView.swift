//
//  DetailedArticleCategoryView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 12/11/2022.
//

import Foundation
import SwiftUI
struct DetailedArticleCategoryView: View {
	let category: Category
	@EnvironmentObject var api: TyfloAPI
	@StateObject private var viewModel = AsyncListViewModel<Podcast>()
	var body: some View {
		List {
			AsyncListStatusSection(
				errorMessage: viewModel.errorMessage,
				isLoading: viewModel.isLoading,
				hasLoaded: viewModel.hasLoaded,
				isEmpty: viewModel.items.isEmpty,
				emptyMessage: "Brak artykułów w tej kategorii.",
				retryAction: { await viewModel.refresh { try await api.fetchArticles(for: category) } },
				retryIdentifier: "categoryArticles.retry",
				isRetryDisabled: viewModel.isLoading
			)

			ForEach(viewModel.items) { item in
				NavigationLink {
					DetailedArticleView(article: item)
				} label: {
					ShortPodcastView(podcast: item, showsListenAction: false)
				}
			}
		}
		.accessibilityIdentifier("categoryArticles.list")
		.refreshable {
			await viewModel.refresh { try await api.fetchArticles(for: category) }
		}
		.task {
			await viewModel.loadIfNeeded { try await api.fetchArticles(for: category) }
		}
		.navigationTitle(category.name)
		.navigationBarTitleDisplayMode(.inline)
	}
}
