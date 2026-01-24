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
				if let errorMessage = viewModel.errorMessage {
					Section {
						Text(errorMessage)
							.foregroundColor(.secondary)

						Button("Spróbuj ponownie") {
							Task {
								await viewModel.refresh(api.fetchCategories)
							}
						}
					}
				}

				ForEach(viewModel.items) { item in
					NavigationLink {
						DetailedCategoryView(category: item)
					} label: {
						ShortCategoryView(category: item)
					}
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
