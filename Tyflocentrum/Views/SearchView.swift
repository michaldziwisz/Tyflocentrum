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
	@StateObject private var viewModel = AsyncListViewModel<Podcast>()
	private func performSearch() {
		let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		Task {
			await viewModel.refresh { try await api.fetchPodcasts(matching: trimmed) }
			let announcement = viewModel.errorMessage
				?? (viewModel.items.isEmpty ? "Brak wyników wyszukiwania." : "Znaleziono \(viewModel.items.count) wyników.")
			UIAccessibility.post(
				notification: .announcement,
				argument: announcement
			)
		}
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
			.navigationTitle("Szukaj")
		}
	}
}
