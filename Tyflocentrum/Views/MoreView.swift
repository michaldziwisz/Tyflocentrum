//
//  LibraryView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 19/10/2022.
//

import Foundation
import SwiftUI

struct MoreView: View {
	var body: some View {
		NavigationView {
			VStack {
				NavigationLink {
					MediaPlayerView(
						podcast: URL(string: "https://radio.tyflopodcast.net/hls/stream.m3u8")!,
						title: "Tyfloradio",
						subtitle: nil,
						canBeLive: true
					)
				} label: {
					Text("Posłuchaj Tyfloradia")
				}
				.accessibilityIdentifier("more.tyfloradio")
			}.navigationTitle("Więcej")
		}
	}
}
