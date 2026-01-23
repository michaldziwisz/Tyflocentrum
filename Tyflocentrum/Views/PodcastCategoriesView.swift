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
				await viewModel.refresh(api.getCategories)
			}
			.task {
				await viewModel.loadIfNeeded(api.getCategories)
			}
			.navigationTitle("Podcasty")
		}
	}
}
