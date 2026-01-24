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
