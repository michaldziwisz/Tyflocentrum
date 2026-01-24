//
//  SearchView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 19/10/2022.
//

import Foundation
import SwiftUI

struct SearchView: View {
	@EnvironmentObject var api: TyfloAPI
	@State private var searchText = ""
	@State private var lastSearchQuery = ""
	@StateObject private var viewModel = AsyncListViewModel<Podcast>()

	@MainActor
	private func search(query: String) async {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		lastSearchQuery = trimmed

		await viewModel.refresh { try await api.fetchPodcasts(matching: trimmed) }
		let announcement = viewModel.errorMessage
			?? (viewModel.items.isEmpty ? "Brak wyników wyszukiwania." : "Znaleziono \(viewModel.items.count) wyników.")
		UIAccessibility.post(
			notification: .announcement,
			argument: announcement
		)
	}

	private func performSearch() {
		Task { await search(query: searchText) }
	}

	private func retryLastSearch() {
		Task { await search(query: lastSearchQuery) }
	}

	var body: some View {
		NavigationView {
			List {
				Section {
					TextField("Podaj frazę do wyszukania", text: $searchText)
						.accessibilityIdentifier("search.field")
						.accessibilityHint("Wpisz tekst, a następnie użyj przycisku Szukaj.")
						.submitLabel(.search)
						.onSubmit {
							performSearch()
						}

					Button("Szukaj") {
						performSearch()
					}
					.accessibilityIdentifier("search.button")
					.accessibilityHint("Wyszukuje audycje po podanej frazie.")
					.disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
				}

				Section {
					if let errorMessage = viewModel.errorMessage {
						Text(errorMessage)
							.foregroundColor(.secondary)

						Button("Spróbuj ponownie") {
							retryLastSearch()
						}
						.accessibilityIdentifier("search.retry")
						.accessibilityHint("Ponawia ostatnie wyszukiwanie.")
						.disabled(lastSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
					}
					else if viewModel.hasLoaded && viewModel.items.isEmpty {
						Text("Brak wyników wyszukiwania dla podanej frazy. Spróbuj użyć innych słów kluczowych.")
							.foregroundColor(.secondary)
					}
					else {
						ForEach(viewModel.items) { item in
							NavigationLink {
								DetailedPodcastView(podcast: item)
							} label: {
								ShortPodcastView(podcast: item)
							}
						}
					}
				}
			}
			.accessibilityIdentifier("search.list")
			.refreshable {
				let query = lastSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !query.isEmpty else { return }
				await search(query: query)
			}
			.navigationTitle("Szukaj")
		}
	}
}
