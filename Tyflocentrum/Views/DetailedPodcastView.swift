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
	@AccessibilityFocusState private var focusedElement: FocusedElement?

	private enum FocusedElement: Hashable {
		case favorite
		case commentsSummary
	}

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

	private func refreshVoiceOverFocusIfNeeded(_ element: FocusedElement) {
		guard UIAccessibility.isVoiceOverRunning else { return }
		guard focusedElement == element else { return }
		Task { @MainActor in
			focusedElement = nil
			await Task.yield()
			focusedElement = element
		}
	}

	private var commentsCountValueText: String {
		if let errorMessage = commentsCountErrorMessage {
			return errorMessage
		}
		if isCommentsCountLoading, commentsCount == nil {
			return "Ładowanie…"
		}
		guard let count = commentsCount else {
			return "Ładowanie…"
		}
		let noun = PolishPluralization.nounForm(
			for: count,
			singular: "komentarz",
			few: "komentarze",
			many: "komentarzy"
		)
		return "\(count) \(noun)"
	}

	private var commentsSummaryText: String {
		"Komentarze: \(commentsCountValueText)"
	}

	private var headerSection: some View {
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
	}

	private var commentsSection: some View {
		return NavigationLink {
			PodcastCommentsView(postID: podcast.id, postTitle: podcast.title.plainText)
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
			.frame(maxWidth: .infinity, alignment: .leading)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(commentsSummaryText)
		.accessibilityHint("Dwukrotnie stuknij, aby przejrzeć komentarze.")
		.accessibilityIdentifier("podcastDetail.commentsSummary")
		.accessibilityFocused($focusedElement, equals: .commentsSummary)
		.id(commentsSummaryText)
	}

	private func toggleFavorite() {
		let willAdd = !favorites.isFavorite(favoriteItem)
		favorites.toggle(favoriteItem)
		announceIfVoiceOver(willAdd ? "Dodano do ulubionych." : "Usunięto z ulubionych.")
		refreshVoiceOverFocusIfNeeded(.favorite)
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				headerSection

				Text(podcast.content.plainText)
					.font(.body)
					.accessibilityIdentifier("podcastDetail.content")

				Divider()

				commentsSection
			}
			.padding()
		}
		.navigationTitle(podcast.title.plainText)
		.navigationBarTitleDisplayMode(.inline)
		.task(id: podcast.id) { @MainActor in
			commentsCount = nil
			commentsCountErrorMessage = nil
			await loadCommentsCount()
		}
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
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

			ToolbarItem(placement: .navigationBarTrailing) {
				ShareLink(
					"Udostępnij",
					item: podcast.guid.plainText,
					message: Text(
						"Posłuchaj audycji \(podcast.title.plainText) w serwisie Tyflopodcast!\nUdostępnione przy pomocy aplikacji Tyflocentrum"
					)
				)
			}

			ToolbarItem(placement: .navigationBarTrailing) {
				Button {
					toggleFavorite()
				} label: {
					Image(systemName: favorites.isFavorite(favoriteItem) ? "star.fill" : "star")
				}
				.accessibilityLabel(favorites.isFavorite(favoriteItem) ? "Usuń z ulubionych" : "Dodaj do ulubionych")
				.accessibilityHint("Dodaje lub usuwa podcast z ulubionych.")
				.accessibilityIdentifier("podcastDetail.favorite")
				.accessibilityFocused($focusedElement, equals: .favorite)
			}
		}
	}

	@MainActor
	private func loadCommentsCount() async {
		guard !isCommentsCountLoading else { return }

		isCommentsCountLoading = true
		commentsCountErrorMessage = nil
		defer { isCommentsCountLoading = false }

		let timeoutSeconds: TimeInterval = 15
		let maxAttempts = 2

		for attempt in 1 ... maxAttempts {
			do {
				let loaded = try await withTimeout(timeoutSeconds) {
					try await api.fetchCommentsCount(forPostID: podcast.id)
				}
				commentsCount = loaded
				refreshVoiceOverFocusIfNeeded(.commentsSummary)
				return
			} catch {
				if Task.isCancelled || error is CancellationError {
					commentsCountErrorMessage = "Nie udało się pobrać komentarzy. Spróbuj ponownie."
					refreshVoiceOverFocusIfNeeded(.commentsSummary)
					return
				}

				if attempt < maxAttempts {
					try? await Task.sleep(nanoseconds: 250_000_000)
					continue
				}

				if error is AsyncTimeoutError {
					commentsCountErrorMessage = "Ładowanie trwa zbyt długo. Spróbuj ponownie."
				} else {
					commentsCountErrorMessage = "Nie udało się pobrać komentarzy. Spróbuj ponownie."
				}
				refreshVoiceOverFocusIfNeeded(.commentsSummary)
			}
		}
	}
}
