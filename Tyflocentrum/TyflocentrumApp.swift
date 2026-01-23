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
				return #"[{"id":10,"name":"Test podcasty","count":1}]"#.data(using: .utf8) ?? Data("[]".utf8)
			}

			if url.host == "tyfloswiat.pl", url.path.contains("/wp-json/wp/v2/categories") {
				return #"[{"id":20,"name":"Test artykuły","count":1}]"#.data(using: .utf8) ?? Data("[]".utf8)
			}

			if url.host == "tyfloswiat.pl", url.path.contains("/wp-json/wp/v2/posts") {
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

		if url.host == "tyflopodcast.net", url.path.contains("/wp-json/wp/v2/posts") {
			return #"[{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test podcast"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyflopodcast.net/?p=1"}}]"#.data(using: .utf8) ?? Data("[]".utf8)
		}

		return Data("[]".utf8)
	}
}
