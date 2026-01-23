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
	@State private var categories = [Category]()
	var body: some View {
		NavigationView {
			List {
				ForEach(categories) {item in
					NavigationLink {
						DetailedArticleCategoryView(category: item)
					} label: {
						ShortCategoryView(category: item)
					}
				}
			}
			.accessibilityIdentifier("articleCategories.list")
			.refreshable {
				categories.removeAll(keepingCapacity: true)
				categories = await api.getArticleCategories()
			}
			.task {
				categories = await api.getArticleCategories()
			}.navigationTitle("Artykuły")
		}
	}
}
