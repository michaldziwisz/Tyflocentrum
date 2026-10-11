//
//  Comment.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 22/11/2022.
//

import Foundation

struct Comment: Codable, Identifiable {
	struct CommentContent: Codable {
		let rendered: String
	}

	let id: Int
	let post: Int
	let parent: Int
	let authorName: String
	let date: String?
	let content: CommentContent

	init(id: Int, post: Int, parent: Int, authorName: String, content: CommentContent, date: String? = nil) {
		self.id = id
		self.post = post
		self.parent = parent
		self.authorName = authorName
		self.content = content
		self.date = date
	}

	var formattedDate: String? {
		guard let date else { return nil }
		// WordPress „date” to lokalny czas serwisu, bez offsetu. Nie przesuwamy
		// go do strefy telefonu; GMT służy wyłącznie do zachowania tych samych pól.
		let parser = DateFormatter()
		parser.locale = Locale(identifier: "en_US_POSIX")
		parser.timeZone = TimeZone(secondsFromGMT: 0)
		parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
		parser.isLenient = false
		guard let parsed = parser.date(from: date), parser.string(from: parsed) == date else { return nil }
		let output = DateFormatter()
		output.locale = Locale(identifier: "pl_PL")
		output.timeZone = TimeZone(secondsFromGMT: 0)
		output.dateFormat = "d MMMM yyyy, HH:mm"
		return output.string(from: parsed)
	}
}
