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

	private var isFavorite: Bool {
		favorites.isFavorite(favoriteItem)
	}

	private func announceIfVoiceOver(_ message: String) {
		guard UIAccessibility.isVoiceOverRunning else { return }
		UIAccessibility.post(notification: .announcement, argument: message)
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

	private var actionsSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			NavigationLink {
				MediaPlayerView(
					podcast: api.getListenableURL(for: podcast),
					title: podcast.title.plainText,
					subtitle: podcast.formattedDate,
					canBeLive: false,
					podcastPostID: podcast.id
				)
			} label: {
				Label("Słuchaj", systemImage: "play.circle.fill")
			}
			.accessibilityLabel("Słuchaj audycji")
			.accessibilityHint("Otwiera odtwarzacz audycji.")
			.accessibilityIdentifier("podcastDetail.listen")

			ShareLink(
				item: podcast.guid.plainText,
				subject: Text(podcast.title.plainText),
				message: Text(
					"Posłuchaj audycji \(podcast.title.plainText) w serwisie Tyflopodcast!\nUdostępnione przy pomocy aplikacji Tyflocentrum"
				)
			) {
				Label("Udostępnij", systemImage: "square.and.arrow.up")
			}

			Button {
				toggleFavorite()
			} label: {
				Label(
					isFavorite ? "Usuń z ulubionych" : "Dodaj do ulubionych",
					systemImage: isFavorite ? "star.fill" : "star"
				)
			}
			.accessibilityLabel(isFavorite ? "Usuń z ulubionych" : "Dodaj do ulubionych")
			.accessibilityValue(isFavorite ? "W ulubionych" : "Poza ulubionymi")
			.accessibilityHint("Dodaje lub usuwa podcast z ulubionych.")
			.accessibilityIdentifier("podcastDetail.favorite")
		}
	}

	private var commentsSection: some View {
		return NavigationLink {
			PodcastCommentsView(postID: podcast.id, postTitle: podcast.title.plainText)
		} label: {
			HStack(spacing: 8) {
				Text("Komentarze")
					.foregroundColor(.secondary)
				Spacer(minLength: 0)
				Text(commentsCountValueText)
					.foregroundColor(.secondary)
				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundColor(.secondary)
					.accessibilityHidden(true)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Komentarze")
		.accessibilityValue(commentsCountValueText)
		.accessibilityHint("Dwukrotnie stuknij, aby przejrzeć komentarze.")
		.accessibilityIdentifier("podcastDetail.commentsSummary")
	}

	private func toggleFavorite() {
		let willAdd = !favorites.isFavorite(favoriteItem)
		favorites.toggle(favoriteItem)
		announceIfVoiceOver(willAdd ? "Dodano do ulubionych." : "Usunięto z ulubionych.")
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				headerSection
				actionsSection
				commentsSection

				Divider()

				Text(podcast.content.plainText)
					.font(.body)
					.accessibilityIdentifier("podcastDetail.content")
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
				return
			} catch {
				if Task.isCancelled || error is CancellationError {
					commentsCountErrorMessage = "Nie udało się pobrać komentarzy. Spróbuj ponownie."
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
			}
		}
	}
}
