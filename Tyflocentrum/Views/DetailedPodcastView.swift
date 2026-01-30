//
//  DetailedPodcastView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 27/10/2022.
//

import Foundation
import SwiftUI
import UIKit

struct DetailedPodcastView: View {
	let podcast: Podcast

	@EnvironmentObject var api: TyfloAPI
	@EnvironmentObject private var favorites: FavoritesStore
	@State private var commentsCount: Int?
	@State private var isCommentsCountLoading = false
	@State private var commentsCountErrorMessage: String?
	@State private var shouldNavigateToComments = false

	private var favoriteItem: FavoriteItem {
		let summary = WPPostSummary(
			id: podcast.id,
			date: podcast.date,
			title: podcast.title,
			excerpt: podcast.excerpt,
			link: podcast.guid.plainText
		)
		return .podcast(summary)
	}

	private func announceIfVoiceOver(_ message: String) {
		guard UIAccessibility.isVoiceOverRunning else { return }
		UIAccessibility.post(notification: .announcement, argument: message)
	}

	private func toggleFavorite() {
		let willAdd = !favorites.isFavorite(favoriteItem)
		favorites.toggle(favoriteItem)
		announceIfVoiceOver(willAdd ? "Dodano do ulubionych." : "Usunięto z ulubionych.")
	}

	private var commentsSummaryText: String {
		if isCommentsCountLoading, commentsCount == nil {
			return "Ładowanie komentarzy…"
		}
		if let errorMessage = commentsCountErrorMessage, commentsCount == nil {
			return errorMessage
		}
		guard let count = commentsCount else { return "Komentarze" }
		guard count > 0 else { return "Brak komentarzy" }
		let noun = PolishPluralization.nounForm(for: count, singular: "komentarz", few: "komentarze", many: "komentarzy")
		return "\(count) \(noun)"
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				VStack(alignment: .leading, spacing: 6) {
					Text(podcast.title.plainText)
						.font(.title3.weight(.semibold))

					Text(podcast.formattedDate)
						.font(.subheadline)
						.foregroundColor(.secondary)
				}
				.accessibilityElement(children: .combine)
				.accessibilityAddTraits(.isHeader)
				.accessibilityIdentifier("podcastDetail.header")

				Text(podcast.content.plainText)
					.font(.body)
					.textSelection(.enabled)
					.accessibilityIdentifier("podcastDetail.content")

				Divider()

				Button {
					shouldNavigateToComments = true
				} label: {
					HStack(spacing: 8) {
						Text(commentsSummaryText)
							.foregroundColor(.secondary)
						Spacer(minLength: 0)
						Image(systemName: "chevron.right")
							.font(.caption.weight(.semibold))
							.foregroundColor(.secondary)
							.accessibilityHidden(true)
					}
					.accessibilityElement(children: .ignore)
					.accessibilityLabel(commentsSummaryText)
					.accessibilityHint("Dwukrotnie stuknij, aby przejrzeć komentarze.")
					.accessibilityIdentifier("podcastDetail.commentsSummary")
				}
				.buttonStyle(.plain)
				.onAppear {
					guard commentsCount == nil else { return }
					guard !isCommentsCountLoading else { return }
					Task { await loadCommentsCount() }
				}
			}
			.padding()
		}
		.navigationTitle(podcast.title.plainText)
		.navigationBarTitleDisplayMode(.inline)
		.navigationDestination(isPresented: $shouldNavigateToComments) {
			PodcastCommentsView(postID: podcast.id, postTitle: podcast.title.plainText)
		}
		.task(id: podcast.id) {
			await loadCommentsCount()
		}
		.toolbar {
			ToolbarItemGroup(placement: .navigationBarTrailing) {
				Button {
					toggleFavorite()
				} label: {
					Image(systemName: favorites.isFavorite(favoriteItem) ? "star.fill" : "star")
				}
				.accessibilityLabel(favorites.isFavorite(favoriteItem) ? "Usuń z ulubionych" : "Dodaj do ulubionych")
				.accessibilityIdentifier("podcastDetail.favorite")

				ShareLink(
					"Udostępnij",
					item: podcast.guid.plainText,
					message: Text(
						"Posłuchaj audycji \(podcast.title.plainText) w serwisie Tyflopodcast!\nUdostępnione przy pomocy aplikacji Tyflocentrum"
					)
				)

				NavigationLink {
					MediaPlayerView(
						podcast: api.getListenableURL(for: podcast),
						title: podcast.title.plainText,
						subtitle: podcast.formattedDate,
						canBeLive: false,
						podcastPostID: podcast.id
					)
				} label: {
					Text("Słuchaj")
						.accessibilityLabel("Słuchaj audycji")
						.accessibilityHint("Otwiera odtwarzacz audycji.")
						.accessibilityIdentifier("podcastDetail.listen")
				}
			}
		}
	}

	@MainActor
	private func loadCommentsCount() async {
		guard !isCommentsCountLoading else { return }

		isCommentsCountLoading = true
		commentsCountErrorMessage = nil
		defer { isCommentsCountLoading = false }

		do {
			let loaded = try await withTimeout(15) {
				try await api.fetchCommentsCount(forPostID: podcast.id)
			}
			commentsCount = loaded
		} catch {
			if Task.isCancelled || error is CancellationError {
				commentsCountErrorMessage = "Nie udało się pobrać komentarzy. Spróbuj ponownie."
				return
			}

			if error is AsyncTimeoutError {
				commentsCountErrorMessage = "Ładowanie trwa zbyt długo. Spróbuj ponownie."
			} else {
				commentsCountErrorMessage = "Nie udało się pobrać komentarzy. Spróbuj ponownie."
			}
		}
	}
}
