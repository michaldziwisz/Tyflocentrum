//
//  LazyDetailedPodcastView.swift
//  Tyflocentrum
//

import SwiftUI

struct LazyDetailedPodcastView: View {
	let summary: WPPostSummary

	@EnvironmentObject private var api: TyfloAPI
	@State private var podcast: Podcast?
	@State private var isLoading = false
	@State private var errorMessage: String?

	var body: some View {
		Group {
			if let podcast {
				DetailedPodcastView(podcast: podcast)
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
		guard podcast == nil else { return }
		await load()
	}

	private func load() async {
		guard !isLoading else { return }
		isLoading = true
		defer { isLoading = false }

		errorMessage = nil
		do {
			let loaded = try await api.fetchPodcast(id: summary.id)
			guard !Task.isCancelled else { return }
			podcast = loaded
		} catch {
			guard !Task.isCancelled else { return }
			errorMessage = "Nie udało się pobrać danych. Spróbuj ponownie."
		}
	}
}

