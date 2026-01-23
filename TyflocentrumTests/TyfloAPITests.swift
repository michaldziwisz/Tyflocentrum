import Foundation
import XCTest

@testable import Tyflocentrum

final class TyfloAPITests: XCTestCase {
	override func tearDown() {
		StubURLProtocol.requestHandler = nil
		super.tearDown()
	}

	func testGetListenableURLBuildsExpectedQueryItems() throws {
		let api = TyfloAPI(session: makeSession())
		let url = api.getListenableURL(for: makePodcast(id: 123))

		let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
		XCTAssertEqual(components.host, "tyflopodcast.net")
		XCTAssertEqual(components.path, "/pobierz.php")

		let items = components.queryItems ?? []
		XCTAssertEqual(items.first(where: { $0.name == "id" })?.value, "123")
		XCTAssertEqual(items.first(where: { $0.name == "plik" })?.value, "0")
	}

	func testSearchEncodesQueryAndUsesPerPage100() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			XCTAssertEqual(url.host, "tyflopodcast.net")
			XCTAssertTrue(url.path.contains("/wp/v2/posts"))

			let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
			let items = components.queryItems ?? []
			XCTAssertEqual(items.first(where: { $0.name == "per_page" })?.value, "100")
			XCTAssertEqual(items.first(where: { $0.name == "search" })?.value, "ala ma kota")

			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, Data("[]".utf8))
		}

		let api = TyfloAPI(session: makeSession())
		_ = await api.getPodcasts(for: "Ala ma kota")

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testContactRadioPostsJSON() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			XCTAssertEqual(url.host, "kontakt.tyflopodcast.net")
			XCTAssertEqual(request.httpMethod, "POST")
			XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

			let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
			let items = components.queryItems ?? []
			XCTAssertEqual(items.first(where: { $0.name == "ac" })?.value, "add")

			let body = try XCTUnwrap(request.httpBody)
			let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
			XCTAssertEqual(json["author"] as? String, "Jan")
			XCTAssertEqual(json["comment"] as? String, "Test")

			let responseBody = #"{"author":"Jan","comment":"Test","error":null}"#.data(using: .utf8)!
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, responseBody)
		}

		let api = TyfloAPI(session: makeSession())
		let (success, error) = await api.contactRadio(as: "Jan", with: "Test")

		XCTAssertTrue(success)
		XCTAssertNil(error)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	private func makeSession() -> URLSession {
		let config = URLSessionConfiguration.ephemeral
		config.protocolClasses = [StubURLProtocol.self]
		return URLSession(configuration: config)
	}

	private func makePodcast(id: Int) -> Podcast {
		let title = Podcast.PodcastTitle(rendered: "Test")
		return Podcast(
			id: id,
			date: "2026-01-20T00:59:40",
			title: title,
			excerpt: title,
			content: title,
			guid: title
		)
	}
}

