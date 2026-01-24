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
	private static var tyflopodcastSearchPostsRequestCount = 0
	private static var tyfloswiatCategoriesRequestCount = 0
	private static var tyfloswiatCategoryPostsRequestCount = 0

	private static var didFailTyflopodcastLatestPosts = false
	private static var didFailTyflopodcastCategoryPosts = false
	private static var didFailTyflopodcastCategories = false
	private static var didFailTyflopodcastSearchPosts = false
	private static var didFailTyfloswiatCategories = false
	private static var didFailTyfloswiatCategoryPosts = false

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

		let (statusCode, data) = Self.response(for: request)
		let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: data)
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}

	private static func response(for request: URLRequest) -> (Int, Data) {
		guard let url = request.url else { return (400, Data()) }

		if url.host == "tyflopodcast.net", url.path.contains("/wp-json/wp/v2/categories") {
			if shouldFailOnce(&didFailTyflopodcastCategories) {
				return (500, Data("[]".utf8))
			}
			let requestIndex = nextRequestIndex(for: &tyflopodcastCategoriesRequestCount)
			if requestIndex <= 1 {
				return (200, #"[{"id":10,"name":"Test podcasty","count":1}]"#.data(using: .utf8) ?? Data("[]".utf8))
			}
			return (
				200,
				#"[{"id":10,"name":"Test podcasty","count":1},{"id":11,"name":"Test podcasty 2","count":1}]"#.data(using: .utf8) ?? Data("[]".utf8)
			)
		}

		if url.host == "tyfloswiat.pl", url.path.contains("/wp-json/wp/v2/categories") {
			if shouldFailOnce(&didFailTyfloswiatCategories) {
				return (500, Data("[]".utf8))
			}
			let requestIndex = nextRequestIndex(for: &tyfloswiatCategoriesRequestCount)
			if requestIndex <= 1 {
				return (200, #"[{"id":20,"name":"Test artykuły","count":1}]"#.data(using: .utf8) ?? Data("[]".utf8))
			}
			return (
				200,
				#"[{"id":20,"name":"Test artykuły","count":1},{"id":21,"name":"Test artykuły 2","count":1}]"#.data(using: .utf8) ?? Data("[]".utf8)
			)
		}

		if url.host == "tyflopodcast.net", url.path.contains("/wp-json/wp/v2/posts") {
			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
			let queryItems = components?.queryItems ?? []

			if queryItems.contains(where: { $0.name == "search" }) {
				if shouldFailOnce(&didFailTyflopodcastSearchPosts) {
					return (500, Data("[]".utf8))
				}
				let requestIndex = nextRequestIndex(for: &tyflopodcastSearchPostsRequestCount)
				if requestIndex <= 1 {
					return (
						200,
						#"[{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test podcast"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=1"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
					)
				}
				return (
					200,
					#"[{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test podcast"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=1"}},{"id":6,"date":"2026-01-21T00:59:40","title":{"rendered":"Test podcast wynik 2"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=6"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
				)
			}

			if queryItems.contains(where: { $0.name == "categories" }) {
				if shouldFailOnce(&didFailTyflopodcastCategoryPosts) {
					return (500, Data("[]".utf8))
				}
				let requestIndex = nextRequestIndex(for: &tyflopodcastCategoryPostsRequestCount)
				if requestIndex <= 1 {
					return (
						200,
						#"[{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test podcast"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=1"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
					)
				}

				return (
					200,
					#"[{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test podcast"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=1"}},{"id":4,"date":"2026-01-21T00:59:40","title":{"rendered":"Test podcast w kategorii 2"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=4"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
				)
			}

			if shouldFailOnce(&didFailTyflopodcastLatestPosts) {
				return (500, Data("[]".utf8))
			}
			let requestIndex = nextRequestIndex(for: &tyflopodcastLatestPostsRequestCount)
			if requestIndex <= 1 {
				return (
					200,
					#"[{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test podcast"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=1"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
				)
			}

			return (
				200,
				#"[{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test podcast"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=1"}},{"id":3,"date":"2026-01-21T00:59:40","title":{"rendered":"Test podcast 2"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=3"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
			)
		}

		if url.host == "tyfloswiat.pl", url.path.contains("/wp-json/wp/v2/posts") {
			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
			let queryItems = components?.queryItems ?? []

			if queryItems.contains(where: { $0.name == "categories" }) {
				if shouldFailOnce(&didFailTyfloswiatCategoryPosts) {
					return (500, Data("[]".utf8))
				}
				let requestIndex = nextRequestIndex(for: &tyfloswiatCategoryPostsRequestCount)
				if requestIndex <= 1 {
					return (
						200,
						#"[{"id":2,"date":"2026-01-20T00:59:40","title":{"rendered":"Test artykuł"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyfloswiat.pl/?p=2"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
					)
				}

				return (
					200,
					#"[{"id":2,"date":"2026-01-20T00:59:40","title":{"rendered":"Test artykuł"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyfloswiat.pl/?p=2"}},{"id":5,"date":"2026-01-21T00:59:40","title":{"rendered":"Test artykuł 2"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyfloswiat.pl/?p=5"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
				)
			}

			return (
				200,
				#"[{"id":2,"date":"2026-01-20T00:59:40","title":{"rendered":"Test artykuł"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyfloswiat.pl/?p=2"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
			)
		}

		if url.host == "kontakt.tyflopodcast.net" {
			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
			let action = components?.queryItems?.first(where: { $0.name == "ac" })?.value

			if action == "current" {
				if isFlagEnabled("UI_TESTING_TP_AVAILABLE") {
					return (200, #"{"available":true,"title":"Test audycja"}"#.data(using: .utf8) ?? Data())
				}
				return (200, #"{"available":false,"title":null}"#.data(using: .utf8) ?? Data())
			}

			if action == "add" {
				return (200, #"{"author":"UI","comment":"Test","error":null}"#.data(using: .utf8) ?? Data())
			}
		}

		return (200, Data("[]".utf8))
	}

	private static func isFlagEnabled(_ flag: String) -> Bool {
		ProcessInfo.processInfo.arguments.contains(flag)
	}

	private static func shouldFailOnce(_ didFail: inout Bool) -> Bool {
		guard isFlagEnabled("UI_TESTING_FAIL_FIRST_REQUEST") else { return false }

		stateLock.lock()
		defer { stateLock.unlock() }

		if didFail {
			return false
		}
		didFail = true
		return true
	}

	private static func nextRequestIndex(for counter: inout Int) -> Int {
		stateLock.lock()
		defer { stateLock.unlock() }
		counter += 1
		return counter
	}
}
