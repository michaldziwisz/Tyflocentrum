//
//  DetailedArticleView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 13/11/2022.
//

import Foundation
import SwiftUI
struct DetailedArticleView: View {
	let article: Podcast
	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			VStack(alignment: .leading, spacing: 6) {
				Text(article.title.plainText)
					.font(.title3.weight(.semibold))

				Text(article.formattedDate)
					.font(.subheadline)
					.foregroundColor(.secondary)
			}
			.accessibilityElement(children: .combine)
			.accessibilityAddTraits(.isHeader)
			.accessibilityIdentifier("articleDetail.header")
			.padding([.horizontal, .top])

			SafeHTMLView(
				htmlBody: article.content.rendered,
				baseURL: URL(string: "https://tyfloswiat.pl"),
				accessibilityIdentifier: "articleDetail.content"
			)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.navigationTitle(article.title.plainText)
		.navigationBarTitleDisplayMode(.inline)
	}
}
