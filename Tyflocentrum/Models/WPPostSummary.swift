//
//  WPPostSummary.swift
//  Tyflocentrum
//

import Foundation

struct WPPostSummary: Codable, Identifiable {
	var id: Int
	var date: String
	var title: Podcast.PodcastTitle
	var excerpt: Podcast.PodcastTitle?
	var link: String
	var modifiedGMT: String? = nil
	var tyflocentrum: ContentTimeMetadata? = nil
	var isMagazineIssue: Bool? = nil

	enum CodingKeys: String, CodingKey {
		case id, date, title, excerpt, link, tyflocentrum, isMagazineIssue
		case modifiedGMT = "modified_gmt"
	}

	var excerptOrEmpty: Podcast.PodcastTitle {
		excerpt ?? Podcast.PodcastTitle(rendered: "")
	}

	func asPodcastStub() -> Podcast {
		Podcast(
			id: id,
			date: date,
			title: title,
			excerpt: excerptOrEmpty,
			content: Podcast.PodcastTitle(rendered: ""),
			guid: Podcast.PodcastTitle(rendered: link),
			modifiedGMT: modifiedGMT,
			tyflocentrum: tyflocentrum,
			isMagazineIssue: isMagazineIssue
		)
	}
}

extension WPPostSummary {
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decode(Int.self, forKey: .id)
		date = try c.decode(String.self, forKey: .date)
		title = try c.decode(Podcast.PodcastTitle.self, forKey: .title)
		excerpt = try c.decodeIfPresent(Podcast.PodcastTitle.self, forKey: .excerpt)
		link = try c.decode(String.self, forKey: .link)
		modifiedGMT = try? c.decode(String.self, forKey: .modifiedGMT)
		tyflocentrum = try? c.decode(ContentTimeMetadata.self, forKey: .tyflocentrum)
		isMagazineIssue = try? c.decode(Bool.self, forKey: .isMagazineIssue)
	}
}
