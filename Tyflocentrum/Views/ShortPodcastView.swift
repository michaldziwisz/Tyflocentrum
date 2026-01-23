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
	@EnvironmentObject var api: TyfloAPI
	@State private var isShowingPlayer = false
	var body: some View {
		let excerpt = podcast.excerpt.plainText
		VStack(alignment: .leading, spacing: 6) {
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
		.accessibilityElement(children: .combine)
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
}
