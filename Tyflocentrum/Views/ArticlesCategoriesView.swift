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
				if let errorMessage = viewModel.errorMessage {
					Section {
						Text(errorMessage)
							.foregroundColor(.secondary)

						Button("Spróbuj ponownie") {
							Task {
								await viewModel.refresh(api.fetchArticleCategories)
							}
						}
					}
				}

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
