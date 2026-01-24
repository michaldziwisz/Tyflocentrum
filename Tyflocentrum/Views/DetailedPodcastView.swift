//
//  DetailedPodcastView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 27/10/2022.
//

import Foundation
import SwiftUI

struct DetailedPodcastView: View {
	let podcast: Podcast
	@EnvironmentObject var api: TyfloAPI
	@State private var comments = [Comment]()
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

				if comments.isEmpty {
					Text("Brak komentarzy")
						.foregroundColor(.secondary)
						.accessibilityIdentifier("podcastDetail.commentsSummary")
				}
				else {
					Text("\(comments.count) komentarzy")
						.foregroundColor(.secondary)
						.accessibilityIdentifier("podcastDetail.commentsSummary")
				}
			}
			.padding()
		}
		.navigationTitle(podcast.title.plainText)
		.navigationBarTitleDisplayMode(.inline)
		.task {
			comments = await api.getComments(for: podcast)
		}
		.toolbar {
			ShareLink(
				"Udostępnij",
				item: podcast.guid.plainText,
				message: Text("Posłuchaj audycji \(podcast.title.plainText) w serwisie Tyflopodcast!\nUdostępnione przy pomocy aplikacji Tyflocentrum")
			)
			.accessibilityLabel("Udostępnij audycję")
			.accessibilityHint("Otwiera systemowe udostępnianie linku do audycji.")
			.accessibilityIdentifier("podcastDetail.share")
			NavigationLink {
				MediaPlayerView(
					podcast: api.getListenableURL(for: podcast),
					title: podcast.title.plainText,
					subtitle: podcast.formattedDate,
					canBeLive: false
				)
			} label: {
				Text("Słuchaj")
			}
			.accessibilityLabel("Słuchaj audycji")
			.accessibilityHint("Otwiera odtwarzacz audycji.")
			.accessibilityIdentifier("podcastDetail.listen")
		}
	}
}
