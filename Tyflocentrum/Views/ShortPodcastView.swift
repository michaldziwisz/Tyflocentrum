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

	var body: some View {
		let excerpt = podcast.excerpt.plainText
		let hint = showsListenAction
			? "Dwukrotnie stuknij, aby otworzyć szczegóły. Akcje: Słuchaj, Skopiuj link."
			: "Dwukrotnie stuknij, aby otworzyć szczegóły. Akcja: Skopiuj link."
		let row = VStack(alignment: .leading, spacing: 6) {
			Text(podcast.title.plainText)
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
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(podcast.title.plainText)
		.accessibilityValue(podcast.formattedDate)
		.accessibilityHint(hint)
		.accessibilityIdentifier("podcast.row.\(podcast.id)")

		Group {
			if showsListenAction {
				row
					.accessibilityAction(named: "Słuchaj") {
						onListen?()
					}
					.accessibilityAction(named: "Skopiuj link") {
						copyPodcastLink()
					}
			}
			else {
				row
					.accessibilityAction(named: "Skopiuj link") {
						copyPodcastLink()
					}
			}
		}
	}
}
