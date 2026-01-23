//
//  NewsView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 17/10/2022.
//

import Foundation
import SwiftUI

struct NewsView: View {
	@EnvironmentObject var api: TyfloAPI
	@State private var podcasts = [Podcast]()
	var body: some View {
		NavigationView {
			List {
				ForEach(podcasts) { item in
					NavigationLink {
						DetailedPodcastView(podcast: item)
					} label: {
						ShortPodcastView(podcast: item)
					}
				}
			}
			.accessibilityIdentifier("news.list")
			.refreshable {
				podcasts.removeAll(keepingCapacity: true)
				podcasts = await api.getLatestPodcasts()
			}
			.task {
				podcasts = await api.getLatestPodcasts()
			}
			.navigationTitle("Nowości")
		}
	}
}
