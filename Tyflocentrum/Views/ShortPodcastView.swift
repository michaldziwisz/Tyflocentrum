//
//  ShortPodcastView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 25/10/2022.
//

import Foundation
import SwiftUI
import UIKit

struct ShortPodcastView: View {
	let podcast: Podcast
	var showsListenAction = true
	var onListen: (() -> Void)? = nil
	var leadingSystemImageName: String? = nil
	var accessibilityKindLabel: String? = nil
	var accessibilityIdentifierOverride: String? = nil
	var favoriteItem: FavoriteItem? = nil

	@EnvironmentObject private var favorites: FavoritesStore

	private func announceIfVoiceOver(_ message: String) {
		guard UIAccessibility.isVoiceOverRunning else { return }
		UIAccessibility.post(notification: .announcement, argument: message)
	}

	private func copyPodcastLink() {
		let urlString = podcast.guid.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !urlString.isEmpty else { return }
		UIPasteboard.general.string = urlString
		announceIfVoiceOver("Skopiowano link.")
	}

	private func toggleFavorite(_ item: FavoriteItem) {
		let willAdd = !favorites.isFavorite(item)
		favorites.toggle(item)
		announceIfVoiceOver(willAdd ? "Dodano do ulubionych." : "Usunięto z ulubionych.")
	}

	var body: some View {
		let excerpt = podcast.excerpt.plainText
		let title = podcast.title.plainText
		let accessibilityTitle = {
			let prefix = accessibilityKindLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			guard !prefix.isEmpty else { return title }
			return "\(prefix). \(title)"
		}()
		let hint = showsListenAction
			? "Dwukrotnie stuknij, aby otworzyć szczegóły. Akcje: Słuchaj, Skopiuj link."
			: "Dwukrotnie stuknij, aby otworzyć szczegóły. Akcja: Skopiuj link."
		let rowContent = VStack(alignment: .leading, spacing: 6) {
			Text(title)
				.font(.headline)
				.foregroundColor(.primary)
				.multilineTextAlignment(.leading)

			if !excerpt.isEmpty {
				Text(excerpt)
					.font(.subheadline)
					.foregroundColor(.secondary)
					.multilineTextAlignment(.leading)
					.lineLimit(3)
			}

			Text(podcast.formattedDate)
				.font(.caption)
				.foregroundColor(.secondary)
		}
		let row = HStack(alignment: .top, spacing: 12) {
			if let leadingSystemImageName {
				Image(systemName: leadingSystemImageName)
					.font(.title3)
					.foregroundColor(.secondary)
					.accessibilityHidden(true)
			}

			rowContent
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityTitle)
		.accessibilityValue(podcast.formattedDate)
		.accessibilityHint(hint)
		.accessibilityIdentifier(accessibilityIdentifierOverride ?? "podcast.row.\(podcast.id)")

		let favoriteActions = { (content: AnyView) -> AnyView in
			guard let favoriteItem else { return content }

			let isFavorite = favorites.isFavorite(favoriteItem)
			let title = isFavorite ? "Usuń z ulubionych" : "Dodaj do ulubionych"

			return AnyView(
				content
					.accessibilityAction(named: title) {
						toggleFavorite(favoriteItem)
					}
					.contextMenu {
						Button(title) {
							toggleFavorite(favoriteItem)
						}
					}
			)
		}

		Group {
			if showsListenAction {
				favoriteActions(AnyView(row))
					.accessibilityAction(named: "Słuchaj") {
						onListen?()
					}
					.accessibilityAction(named: "Skopiuj link") {
						copyPodcastLink()
					}
			}
			else {
				favoriteActions(AnyView(row))
					.accessibilityAction(named: "Skopiuj link") {
						copyPodcastLink()
					}
			}
		}
	}
}
