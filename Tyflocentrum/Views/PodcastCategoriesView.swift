//
//  PodcastCategoriesView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 19/10/2022.
//

import Foundation
import SwiftUI

struct PodcastCategoriesView: View {
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
					emptyMessage: "Brak kategorii podcastów.",
					retryAction: { await viewModel.refresh(api.fetchCategories) },
					retryIdentifier: "podcastCategories.retry",
					isRetryDisabled: viewModel.isLoading
				)

				ForEach(viewModel.items) { item in
					NavigationLink {
						DetailedCategoryView(category: item)
					} label: {
						ShortCategoryView(category: item)
					}
					.accessibilityRemoveTraits(.isButton)
				}
			}
			.accessibilityIdentifier("podcastCategories.list")
			.refreshable {
				await viewModel.refresh(api.fetchCategories)
			}
			.task {
				await viewModel.loadIfNeeded(api.fetchCategories)
			}
			.navigationTitle("Podcasty")
		}
	}
}
