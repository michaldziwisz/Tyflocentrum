//
//  TyflocentrumApp.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 02/10/2022.
//

import Foundation
import SwiftUI

@main
struct TyflocentrumApp: App {
	@StateObject private var dataController: DataController
	@StateObject private var api: TyfloAPI
	@StateObject private var audioPlayer: AudioPlayer

	init() {
		let isUITesting = ProcessInfo.processInfo.arguments.contains("UI_TESTING")
		_dataController = StateObject(wrappedValue: DataController(inMemory: isUITesting))
		_api = StateObject(wrappedValue: isUITesting ? TyfloAPI(session: Self.makeUITestSession()) : TyfloAPI.shared)
		_audioPlayer = StateObject(wrappedValue: AudioPlayer())
	}

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environment(\.managedObjectContext, dataController.container.viewContext)
				.environmentObject(api)
				.environmentObject(audioPlayer)
		}
	}

	private static func makeUITestSession() -> URLSession {
		let config = URLSessionConfiguration.ephemeral
		config.protocolClasses = [UITestURLProtocol.self]
		return URLSession(configuration: config)
	}
}

private final class UITestURLProtocol: URLProtocol {
	private static let stateLock = NSLock()
	private static var tyflopodcastLatestPostsRequestCount = 0
	private static var tyflopodcastCategoryPostsRequestCount = 0
	private static var tyflopodcastCategoriesRequestCount = 0
	private static var tyfloswiatCategoriesRequestCount = 0
	private static var tyfloswiatCategoryPostsRequestCount = 0

	override class func canInit(with request: URLRequest) -> Bool {
		true
	}

	override class func canonicalRequest(for request: URLRequest) -> URLRequest {
		request
	}

	override func startLoading() {
		guard let url = request.url else {
			client?.urlProtocol(self, didFailWithError: URLError(.badURL))
			return
		}

		let data = Self.responseData(for: request)
		let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: data)
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}

	private static func responseData(for request: URLRequest) -> Data {
		guard let url = request.url else {
			return Data()
		}

		if url.host == "tyflopodcast.net", url.path.contains("/wp-json/wp/v2/categories") {
			let requestIndex = nextRequestIndex(for: &tyflopodcastCategoriesRequestCount)
			if requestIndex <= 1 {
				return #"[{"id":10,"name":"Test podcasty","count":1}]"#.data(using: .utf8) ?? Data("[]".utf8)
			}
			return #"[{"id":10,"name":"Test podcasty","count":1},{"id":11,"name":"Test podcasty 2","count":1}]"#.data(using: .utf8) ?? Data("[]".utf8)
		}

		if url.host == "tyfloswiat.pl", url.path.contains("/wp-json/wp/v2/categories") {
			let requestIndex = nextRequestIndex(for: &tyfloswiatCategoriesRequestCount)
			if requestIndex <= 1 {
				return #"[{"id":20,"name":"Test artykuły","count":1}]"#.data(using: .utf8) ?? Data("[]".utf8)
			}
			return #"[{"id":20,"name":"Test artykuły","count":1},{"id":21,"name":"Test artykuły 2","count":1}]"#.data(using: .utf8) ?? Data("[]".utf8)
		}

		if url.host == "tyflopodcast.net", url.path.contains("/wp-json/wp/v2/posts") {
			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
			let queryItems = components?.queryItems ?? []

			if queryItems.contains(where: { $0.name == "search" }) {
				return #"[{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test podcast"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=1"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
			}

			if queryItems.contains(where: { $0.name == "categories" }) {
				let requestIndex = nextRequestIndex(for: &tyflopodcastCategoryPostsRequestCount)
				if requestIndex <= 1 {
					return #"[{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test podcast"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=1"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
				}

				return #"[{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test podcast"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=1"}},{"id":4,"date":"2026-01-21T00:59:40","title":{"rendered":"Test podcast w kategorii 2"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=4"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
			}

			let requestIndex = nextRequestIndex(for: &tyflopodcastLatestPostsRequestCount)
			if requestIndex <= 1 {
				return #"[{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test podcast"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=1"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
			}

			return #"[{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test podcast"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=1"}},{"id":3,"date":"2026-01-21T00:59:40","title":{"rendered":"Test podcast 2"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=3"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
		}

		if url.host == "tyfloswiat.pl", url.path.contains("/wp-json/wp/v2/posts") {
			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
			let queryItems = components?.queryItems ?? []

			if queryItems.contains(where: { $0.name == "categories" }) {
				let requestIndex = nextRequestIndex(for: &tyfloswiatCategoryPostsRequestCount)
				if requestIndex <= 1 {
					return #"[{"id":2,"date":"2026-01-20T00:59:40","title":{"rendered":"Test artykuł"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyfloswiat.pl/?p=2"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
				}

				return #"[{"id":2,"date":"2026-01-20T00:59:40","title":{"rendered":"Test artykuł"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyfloswiat.pl/?p=2"}},{"id":5,"date":"2026-01-21T00:59:40","title":{"rendered":"Test artykuł 2"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyfloswiat.pl/?p=5"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
			}

			return #"[{"id":2,"date":"2026-01-20T00:59:40","title":{"rendered":"Test artykuł"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyfloswiat.pl/?p=2"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
		}

		if url.host == "kontakt.tyflopodcast.net" {
			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
			let action = components?.queryItems?.first(where: { $0.name == "ac" })?.value

			if action == "current" {
				return #"{"available":false,"title":null}"#.data(using: .utf8) ?? Data()
			}

			if action == "add" {
				return #"{"author":"UI","comment":"Test","error":null}"#.data(using: .utf8) ?? Data()
			}
		}

		return Data("[]".utf8)
	}

	private static func nextRequestIndex(for counter: inout Int) -> Int {
		stateLock.lock()
		defer { stateLock.unlock() }
		counter += 1
		return counter
	}
}
