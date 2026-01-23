//
//  ShortPodcastView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 25/10/2022.
//

import Foundation
import SwiftUI

struct ShortPodcastView: View {
	let podcast: Podcast
	var showsListenAction = true
	@EnvironmentObject var api: TyfloAPI
	@State private var isShowingPlayer = false
	var body: some View {
		let excerpt = podcast.excerpt.plainText
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
		.accessibilityHint(showsListenAction ? "Dwukrotnie stuknij, aby otworzyć szczegóły. Dostępna jest też akcja Słuchaj." : "Dwukrotnie stuknij, aby otworzyć szczegóły.")
		.accessibilityIdentifier("podcast.row.\(podcast.id)")

		Group {
			if showsListenAction {
				row
					.accessibilityAction(named: "Słuchaj") {
						isShowingPlayer = true
					}
					.sheet(isPresented: $isShowingPlayer) {
						NavigationStack {
							MediaPlayerView(
								podcast: api.getListenableURL(for: podcast),
								title: podcast.title.plainText,
								subtitle: podcast.formattedDate,
								canBeLive: false
							)
							.toolbar {
								ToolbarItem(placement: .cancellationAction) {
									Button("Zamknij") {
										isShowingPlayer = false
									}
								}
							}
						}
					}
			}
			else {
				row
			}
		}
	}
}
