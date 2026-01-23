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
			await viewModel.refresh { await api.getArticles(for: category) }
		}
		.task {
			await viewModel.loadIfNeeded { await api.getArticles(for: category) }
		}
		.navigationTitle(category.name)
		.navigationBarTitleDisplayMode(.inline)
	}
}
