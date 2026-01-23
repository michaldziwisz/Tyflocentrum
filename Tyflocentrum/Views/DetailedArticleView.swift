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
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				VStack(alignment: .leading, spacing: 6) {
					Text(article.title.plainText)
						.font(.title3.weight(.semibold))
						.accessibilityAddTraits(.isHeader)

					Text(article.formattedDate)
						.font(.subheadline)
						.foregroundColor(.secondary)
				}

				Text(article.content.plainText)
					.font(.body)
					.textSelection(.enabled)
			}
			.padding()
		}
		.navigationTitle(article.title.plainText)
		.navigationBarTitleDisplayMode(.inline)
	}
}
