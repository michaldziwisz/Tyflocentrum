//
//  PodcastPlayerSheet.swift
//  Tyflocentrum
//

import SwiftUI

struct PodcastPlayerSheet: View {
	let podcast: Podcast
	@EnvironmentObject var api: TyfloAPI
	@Environment(\.dismiss) private var dismiss

	var body: some View {
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
						dismiss()
					}
				}
			}
		}
	}
}

