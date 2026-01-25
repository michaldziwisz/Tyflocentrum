//
//  ArticlesView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 19/10/2022.
//

import Foundation
import SwiftUI

struct ArticlesCategoriesView: View {
	@EnvironmentObject var api: TyfloAPI
	@StateObject private var viewModel = AsyncListViewModel<Category>()
	var body: some View {
		NavigationView {
			List {
				Section {
					NavigationLink {
						AllArticlesView()
					} label: {
						AllCategoriesRowView(title: "Wszystkie kategorie", accessibilityIdentifier: "articleCategories.all")
					}
					.accessibilityRemoveTraits(.isButton)
				}

				AsyncListStatusSection(
					errorMessage: viewModel.errorMessage,
					isLoading: viewModel.isLoading,
					hasLoaded: viewModel.hasLoaded,
					isEmpty: viewModel.items.isEmpty,
					emptyMessage: "Brak kategorii artykułów.",
					retryAction: { await viewModel.refresh(api.fetchArticleCategories) },
					retryIdentifier: "articleCategories.retry",
					isRetryDisabled: viewModel.isLoading
				)

				ForEach(viewModel.items) { item in
					NavigationLink {
						DetailedArticleCategoryView(category: item)
					} label: {
						ShortCategoryView(category: item)
					}
					.accessibilityRemoveTraits(.isButton)
				}
			}
			.accessibilityIdentifier("articleCategories.list")
			.refreshable {
				await viewModel.refresh(api.fetchArticleCategories)
			}
			.task {
				await viewModel.loadIfNeeded(api.fetchArticleCategories)
			}
			.navigationTitle("Artykuły")
		}
	}
}

struct AllArticlesView: View {
	@EnvironmentObject private var api: TyfloAPI
	@StateObject private var viewModel = PostSummariesFeedViewModel()

	var body: some View {
		List {
			AsyncListStatusSection(
				errorMessage: viewModel.errorMessage,
				isLoading: viewModel.isLoading,
				hasLoaded: viewModel.hasLoaded,
				isEmpty: viewModel.items.isEmpty,
				emptyMessage: "Brak artykułów.",
				retryAction: { await viewModel.refresh(fetchPage: fetchPage) },
				retryIdentifier: "allArticles.retry",
				isRetryDisabled: viewModel.isLoading
			)

			ForEach(viewModel.items) { summary in
				NavigationLink {
					LazyDetailedArticleView(summary: summary)
				} label: {
					ShortPodcastView(podcast: summary.asPodcastStub(), showsListenAction: false)
				}
				.accessibilityRemoveTraits(.isButton)
				.onAppear {
					guard summary.id == viewModel.items.last?.id else { return }
					Task { await viewModel.loadMore(fetchPage: fetchPage) }
				}
			}

			if viewModel.errorMessage == nil, viewModel.hasLoaded {
				if let loadMoreError = viewModel.loadMoreErrorMessage {
					Section {
						Text(loadMoreError)
							.foregroundColor(.secondary)

						Button("Spróbuj ponownie") {
							Task { await viewModel.loadMore(fetchPage: fetchPage) }
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
		.refreshable {
			await viewModel.refresh(fetchPage: fetchPage)
		}
		.task {
			await viewModel.loadIfNeeded(fetchPage: fetchPage)
		}
		.navigationTitle("Wszystkie artykuły")
		.navigationBarTitleDisplayMode(.inline)
	}

	private func fetchPage(page: Int, perPage: Int) async throws -> TyfloAPI.WPPage<WPPostSummary> {
		try await api.fetchArticleSummariesPage(page: page, perPage: perPage)
	}
}
