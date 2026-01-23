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
	@State private var podcasts = [Podcast]()
	@State private var searchText = ""
	@State private var performedSearch = false
	private func performSearch() {
		let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		Task {
			podcasts = await api.getPodcasts(for: trimmed)
			performedSearch = true
		}
	}
	var body: some View {
		NavigationView {
			List {
				Section {
					TextField("Podaj frazę do wyszukania", text: $searchText)
						.submitLabel(.search)
						.onSubmit {
							performSearch()
						}

					Button("Szukaj") {
						performSearch()
					}
					.disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}

				Section {
					if performedSearch && podcasts.isEmpty {
						Text("Brak wyników wyszukiwania dla podanej frazy. Spróbuj użyć innych słów kluczowych.")
							.foregroundColor(.secondary)
					}
					else {
						ForEach(podcasts) { item in
							NavigationLink {
								DetailedPodcastView(podcast: item)
							} label: {
								ShortPodcastView(podcast: item)
							}
						}
					}
				}
			}
			.navigationTitle("Szukaj")
		}
	}
}
