//
//  TyfloAPI.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 19/10/2022.
//

import Foundation

final class TyfloAPI: ObservableObject {
	private let session: URLSession
	private let tyfloPodcastBaseURL = URL(string: "https://tyflopodcast.net/wp-json")!
	private let tyfloWorldBaseURL = URL(string: "https://tyfloswiat.pl/wp-json")!
	private let tyfloPodcastAPIURL = URL(string: "https://kontakt.tyflopodcast.net/json.php")!
	static let shared = TyfloAPI()
	private init(session: URLSession = .shared) {
		self.session = session
	}

	private func makeWPURL(baseURL: URL, path: String, queryItems: [URLQueryItem]) -> URL? {
		guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { return nil }
		components.queryItems = queryItems.isEmpty ? nil : queryItems
		return components.url
	}

	private func fetch<T: Decodable>(_ url: URL, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
		let (data, response) = try await session.data(from: url)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			throw URLError(.badServerResponse)
		}
		return try decoder.decode(T.self, from: data)
	}

	func getLatestPodcasts() async -> [Podcast] {
		guard let url = makeWPURL(
			baseURL: tyfloPodcastBaseURL,
			path: "wp/v2/posts",
			queryItems: [URLQueryItem(name: "per_page", value: "100")]
		) else {
			print("Failed to create URL for latest podcasts")
			return [Podcast]()
		}
		do {
			return try await fetch(url)
		}
		catch {
			print("Failed to fetch latest podcasts.\n\(error.localizedDescription)\n\(url.absoluteString)")
			return [Podcast]()
		}
		
	}
	func getCategories() async -> [Category] {
		guard let url = makeWPURL(
			baseURL: tyfloPodcastBaseURL,
			path: "wp/v2/categories",
			queryItems: [URLQueryItem(name: "per_page", value: "100")]
		) else {
			print("Failed to create URL for categories")
			return [Category]()
		}
		do {
			return try await fetch(url)
		}
		catch {
			print("Failed to fetch categories.\n\(error.localizedDescription)\n\(url.absoluteString)")
			return [Category]()
		}
	}
	func getPodcast(for category: Category) async -> [Podcast] {
		guard let url = makeWPURL(
			baseURL: tyfloPodcastBaseURL,
			path: "wp/v2/posts",
			queryItems: [
				URLQueryItem(name: "categories", value: "\(category.id)"),
				URLQueryItem(name: "per_page", value: "100"),
			]
		) else {
			print("Failed to create URL for podcasts in category \(category.id)")
			return [Podcast]()
		}
		do {
			return try await fetch(url)
		}
		catch {
			print("Failed to fetch podcasts in category \(category.id).\n\(error.localizedDescription)\n\(url.absoluteString)")
			return [Podcast]()
		}
	}
	func getArticleCategories() async -> [Category] {
		guard let url = makeWPURL(
			baseURL: tyfloWorldBaseURL,
			path: "wp/v2/categories",
			queryItems: [URLQueryItem(name: "per_page", value: "100")]
		) else {
			print("Failed to create URL for article categories")
			return [Category]()
		}
		do {
			return try await fetch(url)
		}
		catch {
			print("Failed to fetch article categories.\n\(error.localizedDescription)\n\(url.absoluteString)")
			return [Category]()
		}
	}
	func getArticles(for category: Category) async -> [Podcast] {
		guard let url = makeWPURL(
			baseURL: tyfloWorldBaseURL,
			path: "wp/v2/posts",
			queryItems: [
				URLQueryItem(name: "categories", value: "\(category.id)"),
				URLQueryItem(name: "per_page", value: "100"),
			]
		) else {
			print("Failed to create URL for articles in category \(category.id)")
			return [Podcast]()
		}
		do {
			return try await fetch(url)
		}
		catch {
			print("Failed to fetch articles in category \(category.id).\n\(error.localizedDescription)\n\(url.absoluteString)")
			return [Podcast]()
		}
	}
	func getListenableURL(for podcast: Podcast) -> URL {
		guard var components = URLComponents(string: "https://tyflopodcast.net/pobierz.php") else {
			return URL(string: "https://tyflopodcast.net")!
		}
		components.queryItems = [
			URLQueryItem(name: "id", value: "\(podcast.id)"),
			URLQueryItem(name: "plik", value: "0"),
		]
		return components.url ?? URL(string: "https://tyflopodcast.net")!
	}
	func getPodcasts(for searchString: String) async -> [Podcast] {
		let trimmed = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let url = makeWPURL(
			baseURL: tyfloPodcastBaseURL,
			path: "wp/v2/posts",
			queryItems: [
				URLQueryItem(name: "per_page", value: "100"),
				URLQueryItem(name: "search", value: trimmed.lowercased()),
			]
		) else {
			print("Failed to create URL for search")
			return [Podcast]()
		}
		do {
			return try await fetch(url)
		}
		catch {
			print("Failed to search podcasts.\n\(error.localizedDescription)\n\(url.absoluteString)")
			return [Podcast]()
		}
		
	}
	func getComments(for podcast: Podcast) async -> [Comment] {
		guard let url = makeWPURL(
			baseURL: tyfloPodcastBaseURL,
			path: "wp/v2/comments",
			queryItems: [
				URLQueryItem(name: "post", value: "\(podcast.id)"),
				URLQueryItem(name: "per_page", value: "100"),
			]
		) else {
			print("Failed to create URL for comments")
			return [Comment]()
		}
		do {
			let decoder = JSONDecoder()
			decoder.keyDecodingStrategy = .convertFromSnakeCase
			return try await fetch(url, decoder: decoder)
		}
		catch {
			print("Failed to fetch comments for post \(podcast.id).\n\(error.localizedDescription)\n\(url.absoluteString)")
			return [Comment]()
		}
	}
	func isTPAvailable() async -> (Bool, Availability) {
		guard var components = URLComponents(url: tyfloPodcastAPIURL, resolvingAgainstBaseURL: false) else {
			return (false, Availability(available: false, title: nil))
		}
		components.queryItems = [URLQueryItem(name: "ac", value: "current")]
		guard let url = components.url else {
			return (false, Availability(available: false, title: nil))
		}
		do {
			let decoder = JSONDecoder()
			decoder.keyDecodingStrategy = .convertFromSnakeCase
			let decodedResponse: Availability = try await fetch(url, decoder: decoder)
			return (decodedResponse.available, decodedResponse)
		}
		catch {
			print("\(error.localizedDescription)\n\(url.absoluteString)")
			return (false, Availability(available: false, title: nil))
		}
	}
	func contactRadio(as name: String, with message: String) async -> (Bool, String?) {
		guard var components = URLComponents(url: tyfloPodcastAPIURL, resolvingAgainstBaseURL: false) else {
			return (false, nil)
		}
		components.queryItems = [URLQueryItem(name: "ac", value: "add")]
		guard let url = components.url else {
			return (false, nil)
		}
		let contact = ContactResponse(author: name, comment: message, error: nil)
		var request = URLRequest(url: url)
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpMethod = "POST"
		do {
			let encoded = try JSONEncoder().encode(contact)
			let (data, response) = try await session.upload(for: request, from: encoded)
			guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
				return (false, nil)
			}
			let decodedResponse = try JSONDecoder().decode(ContactResponse.self, from: data)
			if let error = decodedResponse.error {
				return (false, error)
			}
			return (true, nil)
		}
		catch {
			print("\(error.localizedDescription)\n\(url.absoluteString)")
			return (false, nil)
		}
	}
}
