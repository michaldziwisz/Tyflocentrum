//
//  LazyDetailedArticleView.swift
//  Tyflocentrum
//

import SwiftUI

struct LazyDetailedArticleView: View {
	let summary: WPPostSummary

	@EnvironmentObject private var api: TyfloAPI
	@State private var article: Podcast?
	@State private var isLoading = false
	@State private var errorMessage: String?

	var body: some View {
		Group {
			if let article {
				DetailedArticleView(article: article)
			}
			else if let errorMessage {
				AsyncListStatusSection(
					errorMessage: errorMessage,
					isLoading: isLoading,
					hasLoaded: true,
					isEmpty: true,
					emptyMessage: "",
					retryAction: { await load() }
				)
			}
			else {
				AsyncListStatusSection(
					errorMessage: nil,
					isLoading: true,
					hasLoaded: false,
					isEmpty: true,
					emptyMessage: ""
				)
			}
		}
		.navigationTitle(summary.title.plainText)
		.navigationBarTitleDisplayMode(.inline)
		.task {
			await loadIfNeeded()
		}
	}

	private func loadIfNeeded() async {
		guard article == nil else { return }
		await load()
	}

	private func load() async {
		guard !isLoading else { return }
		isLoading = true
		defer { isLoading = false }

		errorMessage = nil
		do {
			let loaded = try await api.fetchArticle(id: summary.id)
			guard !Task.isCancelled else { return }
			article = loaded
		} catch {
			guard !Task.isCancelled else { return }
			errorMessage = "Nie udało się pobrać danych. Spróbuj ponownie."
		}
	}
}

