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

		func testFetchPodcastSearchSummariesUsesEmbedFieldsAndSearchQuery() async {
			let requestMade = expectation(description: "request made")

			StubURLProtocol.requestHandler = { request in
				requestMade.fulfill()
				let url = try XCTUnwrap(request.url)

				XCTAssertEqual(url.host, "tyflopodcast.net")
				XCTAssertTrue(url.path.contains("/wp-json/wp/v2/posts"))

				let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
				let items = components.queryItems ?? []
				XCTAssertEqual(items.first(where: { $0.name == "context" })?.value, "embed")
				XCTAssertEqual(items.first(where: { $0.name == "per_page" })?.value, "100")
				XCTAssertEqual(items.first(where: { $0.name == "search" })?.value, "Ala ma kota")
				XCTAssertEqual(items.first(where: { $0.name == "_fields" })?.value, "id,date,link,title,excerpt")

				let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
				return (response, Data("[]".utf8))
			}

			let api = TyfloAPI(session: makeSession())
			do {
				let results = try await api.fetchPodcastSearchSummaries(matching: "  Ala ma kota ")
				XCTAssertTrue(results.isEmpty)
			} catch {
				XCTFail("Expected success but got error: \(error)")
			}

			await fulfillment(of: [requestMade], timeout: 1)
		}

		func testFetchArticleSearchSummariesUsesWorldHostAndEmbedFields() async {
			let requestMade = expectation(description: "request made")

			StubURLProtocol.requestHandler = { request in
				requestMade.fulfill()
				let url = try XCTUnwrap(request.url)

				XCTAssertEqual(url.host, "tyfloswiat.pl")
				XCTAssertTrue(url.path.contains("/wp-json/wp/v2/posts"))

				let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
				let items = components.queryItems ?? []
				XCTAssertEqual(items.first(where: { $0.name == "context" })?.value, "embed")
				XCTAssertEqual(items.first(where: { $0.name == "per_page" })?.value, "100")
				XCTAssertEqual(items.first(where: { $0.name == "search" })?.value, "Test")
				XCTAssertEqual(items.first(where: { $0.name == "_fields" })?.value, "id,date,link,title,excerpt")

				let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
				return (response, Data("[]".utf8))
			}

			let api = TyfloAPI(session: makeSession())
			do {
				let results = try await api.fetchArticleSearchSummaries(matching: "Test")
				XCTAssertTrue(results.isEmpty)
			} catch {
				XCTFail("Expected success but got error: \(error)")
			}

			await fulfillment(of: [requestMade], timeout: 1)
		}

		func testFetchTyfloswiatPagesUsesPagesEndpointAndSlugQuery() async {
			let requestMade = expectation(description: "request made")

			StubURLProtocol.requestHandler = { request in
				requestMade.fulfill()
				let url = try XCTUnwrap(request.url)

				XCTAssertEqual(url.host, "tyfloswiat.pl")
				XCTAssertTrue(url.path.contains("/wp-json/wp/v2/pages"))

				let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
				let items = components.queryItems ?? []
				XCTAssertEqual(items.first(where: { $0.name == "context" })?.value, "embed")
				XCTAssertEqual(items.first(where: { $0.name == "per_page" })?.value, "1")
				XCTAssertEqual(items.first(where: { $0.name == "slug" })?.value, "czasopismo")
				XCTAssertEqual(items.first(where: { $0.name == "_fields" })?.value, "id,date,link,title,excerpt")

				let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
				return (response, Data("[]".utf8))
			}

			let api = TyfloAPI(session: makeSession())
			do {
				let results = try await api.fetchTyfloswiatPages(slug: "czasopismo", perPage: 1)
				XCTAssertTrue(results.isEmpty)
			} catch {
				XCTFail("Expected success but got error: \(error)")
			}

			await fulfillment(of: [requestMade], timeout: 1)
		}

		func testFetchTyfloswiatPageSummariesUsesParentAndEmbedFields() async {
			let requestMade = expectation(description: "request made")

			StubURLProtocol.requestHandler = { request in
				requestMade.fulfill()
				let url = try XCTUnwrap(request.url)

				XCTAssertEqual(url.host, "tyfloswiat.pl")
				XCTAssertTrue(url.path.contains("/wp-json/wp/v2/pages"))

				let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
				let items = components.queryItems ?? []
				XCTAssertEqual(items.first(where: { $0.name == "context" })?.value, "embed")
				XCTAssertEqual(items.first(where: { $0.name == "per_page" })?.value, "100")
				XCTAssertEqual(items.first(where: { $0.name == "parent" })?.value, "1409")
				XCTAssertEqual(items.first(where: { $0.name == "orderby" })?.value, "date")
				XCTAssertEqual(items.first(where: { $0.name == "order" })?.value, "desc")
				XCTAssertEqual(items.first(where: { $0.name == "_fields" })?.value, "id,date,link,title,excerpt")

				let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
				return (response, Data("[]".utf8))
			}

			let api = TyfloAPI(session: makeSession())
			do {
				let results = try await api.fetchTyfloswiatPageSummaries(parentPageID: 1409, perPage: 100)
				XCTAssertTrue(results.isEmpty)
			} catch {
				XCTFail("Expected success but got error: \(error)")
			}

			await fulfillment(of: [requestMade], timeout: 1)
		}

		func testFetchTyfloswiatPageUsesPageEndpoint() async {
			let requestMade = expectation(description: "request made")

			StubURLProtocol.requestHandler = { request in
				requestMade.fulfill()
				let url = try XCTUnwrap(request.url)

				XCTAssertEqual(url.host, "tyfloswiat.pl")
				XCTAssertTrue(url.path.contains("/wp-json/wp/v2/pages/123"))

				let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
				let items = components.queryItems ?? []
				XCTAssertEqual(items.first(where: { $0.name == "_fields" })?.value, "id,date,title,excerpt,content,guid")

				let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
				let payload = #"""
				{"id":123,"date":"2026-01-20T00:59:40","title":{"rendered":"Test"},"excerpt":{"rendered":"Excerpt"},"content":{"rendered":"Content"},"guid":{"rendered":"https://tyfloswiat.pl/?page_id=123"}}
				"""#.data(using: .utf8) ?? Data()
				return (response, payload)
			}

			let api = TyfloAPI(session: makeSession())
			do {
				let page = try await api.fetchTyfloswiatPage(id: 123)
				XCTAssertEqual(page.id, 123)
			} catch {
				XCTFail("Expected success but got error: \(error)")
			}

			await fulfillment(of: [requestMade], timeout: 1)
		}

		func testGetLatestPodcastsUsesPerPage100() async {
			let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			XCTAssertEqual(url.host, "tyflopodcast.net")
			XCTAssertTrue(url.path.contains("/wp-json/wp/v2/posts"))

			let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
			let items = components.queryItems ?? []
			XCTAssertEqual(items.first(where: { $0.name == "per_page" })?.value, "100")

			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, self.podcastsResponseData(ids: [1]))
		}

		let api = TyfloAPI(session: makeSession())
		let podcasts = await api.getLatestPodcasts()

		XCTAssertEqual(podcasts.count, 1)
		XCTAssertEqual(podcasts.first?.id, 1)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testFetchPodcastSummariesPageUsesPerPageAndPageParameters() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			XCTAssertEqual(url.host, "tyflopodcast.net")
			XCTAssertTrue(url.path.contains("/wp-json/wp/v2/posts"))

			let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
			let items = components.queryItems ?? []
			XCTAssertEqual(items.first(where: { $0.name == "context" })?.value, "embed")
			XCTAssertEqual(items.first(where: { $0.name == "per_page" })?.value, "20")
			XCTAssertEqual(items.first(where: { $0.name == "page" })?.value, "2")

			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, Data("[]".utf8))
		}

		let api = TyfloAPI(session: makeSession())
		do {
			let page = try await api.fetchPodcastSummariesPage(page: 2, perPage: 20)
			XCTAssertTrue(page.items.isEmpty)
		} catch {
			XCTFail("Expected success but got error: \(error)")
		}

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testGetCategoriesUsesPerPage100() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			XCTAssertEqual(url.host, "tyflopodcast.net")
			XCTAssertTrue(url.path.contains("/wp-json/wp/v2/categories"))

			let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
			let items = components.queryItems ?? []
			XCTAssertEqual(items.first(where: { $0.name == "per_page" })?.value, "100")

			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, self.categoriesResponseData())
		}

		let api = TyfloAPI(session: makeSession())
		let categories = await api.getCategories()

		XCTAssertEqual(categories.count, 1)
		XCTAssertEqual(categories.first?.id, 10)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testGetPodcastsForCategoryUsesCategoryId() async {
		let requestMade = expectation(description: "request made")
		let category = Category(name: "Test", id: 7, count: 0)

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			XCTAssertEqual(url.host, "tyflopodcast.net")
			XCTAssertTrue(url.path.contains("/wp-json/wp/v2/posts"))

			let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
			let items = components.queryItems ?? []
			XCTAssertEqual(items.first(where: { $0.name == "categories" })?.value, "7")
			XCTAssertEqual(items.first(where: { $0.name == "per_page" })?.value, "100")

			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, self.podcastsResponseData(ids: [42]))
		}

		let api = TyfloAPI(session: makeSession())
		let podcasts = await api.getPodcast(for: category)

		XCTAssertEqual(podcasts.count, 1)
		XCTAssertEqual(podcasts.first?.id, 42)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testFetchArticleSummariesPageUsesPerPageAndPageParameters() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			XCTAssertEqual(url.host, "tyfloswiat.pl")
			XCTAssertTrue(url.path.contains("/wp-json/wp/v2/posts"))

			let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
			let items = components.queryItems ?? []
			XCTAssertEqual(items.first(where: { $0.name == "context" })?.value, "embed")
			XCTAssertEqual(items.first(where: { $0.name == "per_page" })?.value, "10")
			XCTAssertEqual(items.first(where: { $0.name == "page" })?.value, "3")

			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, Data("[]".utf8))
		}

		let api = TyfloAPI(session: makeSession())
		do {
			let page = try await api.fetchArticleSummariesPage(page: 3, perPage: 10)
			XCTAssertTrue(page.items.isEmpty)
		} catch {
			XCTFail("Expected success but got error: \(error)")
		}

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testGetArticleCategoriesUsesCorrectHost() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			XCTAssertEqual(url.host, "tyfloswiat.pl")
			XCTAssertTrue(url.path.contains("/wp-json/wp/v2/categories"))

			let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
			let items = components.queryItems ?? []
			XCTAssertEqual(items.first(where: { $0.name == "per_page" })?.value, "100")

			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, self.categoriesResponseData())
		}

		let api = TyfloAPI(session: makeSession())
		let categories = await api.getArticleCategories()

		XCTAssertEqual(categories.count, 1)
		XCTAssertEqual(categories.first?.id, 10)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testGetArticlesForCategoryUsesCorrectHostAndCategoryId() async {
		let requestMade = expectation(description: "request made")
		let category = Category(name: "Test", id: 9, count: 0)

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			XCTAssertEqual(url.host, "tyfloswiat.pl")
			XCTAssertTrue(url.path.contains("/wp-json/wp/v2/posts"))

			let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
			let items = components.queryItems ?? []
			XCTAssertEqual(items.first(where: { $0.name == "categories" })?.value, "9")
			XCTAssertEqual(items.first(where: { $0.name == "per_page" })?.value, "100")

			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, self.podcastsResponseData(ids: [100]))
		}

		let api = TyfloAPI(session: makeSession())
		let articles = await api.getArticles(for: category)

		XCTAssertEqual(articles.count, 1)
		XCTAssertEqual(articles.first?.id, 100)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testGetCommentsUsesPostIdAndPerPage100() async {
		let requestMade = expectation(description: "request made")
		let podcast = makePodcast(id: 123)

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			XCTAssertEqual(url.host, "tyflopodcast.net")
			XCTAssertTrue(url.path.contains("/wp-json/wp/v2/comments"))

			let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
			let items = components.queryItems ?? []
			XCTAssertEqual(items.first(where: { $0.name == "post" })?.value, "123")
			XCTAssertEqual(items.first(where: { $0.name == "per_page" })?.value, "100")

			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, self.commentsResponseData(postID: 123))
		}

		let api = TyfloAPI(session: makeSession())
		let comments = await api.getComments(for: podcast)

		XCTAssertEqual(comments.count, 1)
		XCTAssertEqual(comments.first?.post, 123)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testIsTPAvailableUsesCorrectQuery() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			XCTAssertEqual(url.host, "kontakt.tyflopodcast.net")
			XCTAssertEqual(request.httpMethod ?? "GET", "GET")

			let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
			let items = components.queryItems ?? []
			XCTAssertEqual(items.first(where: { $0.name == "ac" })?.value, "current")

			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, self.availabilityResponseData(available: true, title: "Test"))
		}

		let api = TyfloAPI(session: makeSession())
		let (available, info) = await api.isTPAvailable()

		XCTAssertTrue(available)
		XCTAssertEqual(info.title, "Test")

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testGetLatestPodcastsReturnsEmptyOnServerError() async {
		let requestMade = expectation(description: "request made")
		requestMade.expectedFulfillmentCount = 2

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
			return (response, Data())
		}

		let api = TyfloAPI(session: makeSession())
		let podcasts = await api.getLatestPodcasts()
		XCTAssertTrue(podcasts.isEmpty)

		await fulfillment(of: [requestMade], timeout: 2)
	}

	func testGetLatestPodcastsReturnsEmptyOnInvalidJSON() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, Data("not-json".utf8))
		}

		let api = TyfloAPI(session: makeSession())
		let podcasts = await api.getLatestPodcasts()
		XCTAssertTrue(podcasts.isEmpty)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testGetCategoriesReturnsEmptyOnServerError() async {
		let requestMade = expectation(description: "request made")
		requestMade.expectedFulfillmentCount = 2

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
			return (response, Data())
		}

		let api = TyfloAPI(session: makeSession())
		let categories = await api.getCategories()
		XCTAssertTrue(categories.isEmpty)

		await fulfillment(of: [requestMade], timeout: 2)
	}

	func testGetCategoriesReturnsEmptyOnInvalidJSON() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, Data("not-json".utf8))
		}

		let api = TyfloAPI(session: makeSession())
		let categories = await api.getCategories()
		XCTAssertTrue(categories.isEmpty)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testGetPodcastForCategoryReturnsEmptyOnServerError() async {
		let requestMade = expectation(description: "request made")
		requestMade.expectedFulfillmentCount = 2
		let category = Category(name: "Test", id: 7, count: 0)

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
			return (response, Data())
		}

		let api = TyfloAPI(session: makeSession())
		let podcasts = await api.getPodcast(for: category)
		XCTAssertTrue(podcasts.isEmpty)

		await fulfillment(of: [requestMade], timeout: 2)
	}

	func testGetPodcastForCategoryReturnsEmptyOnInvalidJSON() async {
		let requestMade = expectation(description: "request made")
		let category = Category(name: "Test", id: 7, count: 0)

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, Data("not-json".utf8))
		}

		let api = TyfloAPI(session: makeSession())
		let podcasts = await api.getPodcast(for: category)
		XCTAssertTrue(podcasts.isEmpty)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testGetArticleCategoriesReturnsEmptyOnServerError() async {
		let requestMade = expectation(description: "request made")
		requestMade.expectedFulfillmentCount = 2

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
			return (response, Data())
		}

		let api = TyfloAPI(session: makeSession())
		let categories = await api.getArticleCategories()
		XCTAssertTrue(categories.isEmpty)

		await fulfillment(of: [requestMade], timeout: 2)
	}

	func testGetArticleCategoriesReturnsEmptyOnInvalidJSON() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, Data("not-json".utf8))
		}

		let api = TyfloAPI(session: makeSession())
		let categories = await api.getArticleCategories()
		XCTAssertTrue(categories.isEmpty)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testGetArticlesForCategoryReturnsEmptyOnServerError() async {
		let requestMade = expectation(description: "request made")
		requestMade.expectedFulfillmentCount = 2
		let category = Category(name: "Test", id: 9, count: 0)

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
			return (response, Data())
		}

		let api = TyfloAPI(session: makeSession())
		let articles = await api.getArticles(for: category)
		XCTAssertTrue(articles.isEmpty)

		await fulfillment(of: [requestMade], timeout: 2)
	}

	func testGetArticlesForCategoryReturnsEmptyOnInvalidJSON() async {
		let requestMade = expectation(description: "request made")
		let category = Category(name: "Test", id: 9, count: 0)

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, Data("not-json".utf8))
		}

		let api = TyfloAPI(session: makeSession())
		let articles = await api.getArticles(for: category)
		XCTAssertTrue(articles.isEmpty)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testGetCommentsReturnsEmptyOnServerError() async {
		let requestMade = expectation(description: "request made")
		requestMade.expectedFulfillmentCount = 2
		let podcast = makePodcast(id: 123)

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
			return (response, Data())
		}

		let api = TyfloAPI(session: makeSession())
		let comments = await api.getComments(for: podcast)
		XCTAssertTrue(comments.isEmpty)

		await fulfillment(of: [requestMade], timeout: 2)
	}

	func testGetCommentsReturnsEmptyOnInvalidJSON() async {
		let requestMade = expectation(description: "request made")
		let podcast = makePodcast(id: 123)

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, Data("not-json".utf8))
		}

		let api = TyfloAPI(session: makeSession())
		let comments = await api.getComments(for: podcast)
		XCTAssertTrue(comments.isEmpty)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testSearchReturnsEmptyOnServerError() async {
		let requestMade = expectation(description: "request made")
		requestMade.expectedFulfillmentCount = 2

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
			return (response, Data())
		}

		let api = TyfloAPI(session: makeSession())
		let podcasts = await api.getPodcasts(for: "test")
		XCTAssertTrue(podcasts.isEmpty)

		await fulfillment(of: [requestMade], timeout: 2)
	}

	func testSearchReturnsEmptyOnInvalidJSON() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, Data("not-json".utf8))
		}

		let api = TyfloAPI(session: makeSession())
		let podcasts = await api.getPodcasts(for: "test")
		XCTAssertTrue(podcasts.isEmpty)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testIsTPAvailableReturnsFalseOnServerError() async {
		let requestMade = expectation(description: "request made")
		requestMade.expectedFulfillmentCount = 2

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
			return (response, Data())
		}

		let api = TyfloAPI(session: makeSession())
		let (available, info) = await api.isTPAvailable()
		XCTAssertFalse(available)
		XCTAssertFalse(info.available)
		XCTAssertNil(info.title)

		await fulfillment(of: [requestMade], timeout: 2)
	}

	func testIsTPAvailableReturnsFalseOnInvalidJSON() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, Data("not-json".utf8))
		}

		let api = TyfloAPI(session: makeSession())
		let (available, info) = await api.isTPAvailable()
		XCTAssertFalse(available)
		XCTAssertFalse(info.available)
		XCTAssertNil(info.title)

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

			let body = try self.requestBodyData(from: request)
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

	func testContactRadioReturnsFalseWithErrorMessageWhenAPIReportsError() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			let responseBody = #"{"author":"Jan","comment":"Test","error":"Nope"}"#.data(using: .utf8)!
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, responseBody)
		}

		let api = TyfloAPI(session: makeSession())
		let (success, error) = await api.contactRadio(as: "Jan", with: "Test")

		XCTAssertFalse(success)
		XCTAssertEqual(error, "Nope")

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testContactRadioReturnsFalseOnServerError() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
			return (response, Data())
		}

		let api = TyfloAPI(session: makeSession())
		let (success, error) = await api.contactRadio(as: "Jan", with: "Test")

		XCTAssertFalse(success)
		XCTAssertNil(error)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	func testContactRadioReturnsFalseOnInvalidJSON() async {
		let requestMade = expectation(description: "request made")

		StubURLProtocol.requestHandler = { request in
			requestMade.fulfill()
			let url = try XCTUnwrap(request.url)

			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (response, Data("not-json".utf8))
		}

		let api = TyfloAPI(session: makeSession())
		let (success, error) = await api.contactRadio(as: "Jan", with: "Test")

		XCTAssertFalse(success)
		XCTAssertNil(error)

		await fulfillment(of: [requestMade], timeout: 1)
	}

	private func podcastsResponseData(ids: [Int]) -> Data {
		let items: [[String: Any]] = ids.map { id in
			[
				"id": id,
				"date": "2026-01-20T00:59:40",
				"title": ["rendered": "Title \(id)"],
				"excerpt": ["rendered": "Excerpt \(id)"],
				"content": ["rendered": "Content \(id)"],
				"guid": ["rendered": "GUID \(id)"],
			]
		}

		return (try? JSONSerialization.data(withJSONObject: items)) ?? Data()
	}

	private func categoriesResponseData() -> Data {
		let items: [[String: Any]] = [
			[
				"name": "Test",
				"id": 10,
				"count": 5,
			]
		]
		return (try? JSONSerialization.data(withJSONObject: items)) ?? Data()
	}

	private func commentsResponseData(postID: Int) -> Data {
		let items: [[String: Any]] = [
			[
				"id": 1,
				"post": postID,
				"parent": 0,
				"author_name": "Jan",
				"content": ["rendered": "Test"],
			]
		]

		return (try? JSONSerialization.data(withJSONObject: items)) ?? Data()
	}

	private func availabilityResponseData(available: Bool, title: String?) -> Data {
		var obj: [String: Any] = ["available": available]
		if let title {
			obj["title"] = title
		}
		return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
	}

	private func requestBodyData(from request: URLRequest) throws -> Data {
		if let body = request.httpBody {
			return body
		}

		guard let stream = request.httpBodyStream else {
			throw URLError(.badURL)
		}

		stream.open()
		defer { stream.close() }

		var data = Data()
		var buffer = [UInt8](repeating: 0, count: 1024)

		while true {
			let count = stream.read(&buffer, maxLength: buffer.count)
			if count > 0 {
				data.append(buffer, count: count)
			} else if count == 0 {
				break
			} else {
				throw stream.streamError ?? URLError(.cannotDecodeContentData)
			}
		}

		return data
	}

	func testFetchPodcastSummariesPageRetriesOnceOnServerError() async throws {
		let responseBody = #"[{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test"},"excerpt":{"rendered":"Ex"},"link":"https://tyflopodcast.net/?p=1"}]"#
		var requestCount = 0

		StubURLProtocol.requestHandler = { request in
			requestCount += 1
			let url = try XCTUnwrap(request.url)

			let statusCode = requestCount == 1 ? 500 : 200
			let headers = [
				"X-WP-Total": "1",
				"X-WP-TotalPages": "1",
			]
			let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
			return (response, Data(responseBody.utf8))
		}

		let api = TyfloAPI(session: makeSession())
		let page = try await api.fetchPodcastSummariesPage(page: 1, perPage: 1)

		XCTAssertEqual(requestCount, 2)
		XCTAssertEqual(page.items.count, 1)
		XCTAssertEqual(page.totalPages, 1)
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
