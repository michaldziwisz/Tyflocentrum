#if canImport(UIKit)
	import Foundation
	@testable import Tyflocentrum
	import WebKit
	import XCTest

	@MainActor
	final class SafeHTMLCoordinatorLogicTests: XCTestCase {
		func testOldFailureDoesNotCancelTimeoutOrAffectNewNavigation() throws {
			let logic = SafeHTMLCoordinatorLogic()
			let navigator = FakeNavigator()
			logic.attach(navigator: navigator)

			logic.requestRender(forHTML: "<p>One</p>", fontSize: 17)
			let oldNavigation = try XCTUnwrap(navigator.lastNavigation)
			logic.requestRender(forHTML: "<p>Two</p>", fontSize: 17)
			let newNavigation = try XCTUnwrap(navigator.lastNavigation)

			logic.didFail(navigation: oldNavigation, error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))

			XCTAssertEqual(navigator.loadCallCount, 2)
			logic.didFinish(navigation: newNavigation)
			XCTAssertEqual(logic.state.phase, .succeeded)
		}

		func testSupersededCancellationDoesNotShowRetry() throws {
			let logic = SafeHTMLCoordinatorLogic()
			let navigator = FakeNavigator()
			logic.attach(navigator: navigator)

			logic.requestRender(forHTML: "<p>One</p>", fontSize: 17)
			let oldNavigation = try XCTUnwrap(navigator.lastNavigation)
			logic.requestRender(forHTML: "<p>Two</p>", fontSize: 17)

			logic.didFail(navigation: oldNavigation, error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))

			XCTAssertFalse(logic.state.showsRetryButton)
			XCTAssertEqual(logic.state.phase, .attempting)
		}

		func testUnknownNavigationIsIgnored() {
			let logic = SafeHTMLCoordinatorLogic()
			let navigator = FakeNavigator()
			logic.attach(navigator: navigator)
			logic.requestRender(forHTML: "<p>One</p>", fontSize: 17)
			let loadCount = navigator.loadCallCount

			logic.didFail(navigation: nil, error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))

			XCTAssertEqual(navigator.loadCallCount, loadCount)
			XCTAssertEqual(logic.state.phase, .attempting)
		}

		func testDisposePreventsRetryOnLateCallbacks() throws {
			let logic = SafeHTMLCoordinatorLogic()
			let navigator = FakeNavigator()
			logic.attach(navigator: navigator)
			logic.requestRender(forHTML: "<p>One</p>", fontSize: 17)
			let navigation = try XCTUnwrap(navigator.lastNavigation)

			logic.prepareForTeardown()
			logic.didFail(navigation: navigation, error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))

			XCTAssertEqual(navigator.loadCallCount, 1)
		}

		func testActiveCancellationRequiresManualRetryWithoutAutomaticLoop() throws {
			let logic = SafeHTMLCoordinatorLogic()
			let navigator = FakeNavigator()
			logic.attach(navigator: navigator)
			logic.requestRender(forHTML: "<p>Tekst</p>", fontSize: 17)
			let navigation = try XCTUnwrap(navigator.lastNavigation)
			logic.didFail(navigation: navigation, error: URLError(.cancelled))
			XCTAssertEqual(logic.state.phase, .failed(.cancelled))
			XCTAssertTrue(logic.state.showsRetryButton)
			XCTAssertEqual(navigator.loadCallCount, 1)
			logic.markManualRetryRequested()
			XCTAssertEqual(navigator.loadCallCount, 2)
			logic.prepareForTeardown()
		}

		func testFailureActuallyLoadsOnceMoreAndKeepsBaseURL() throws {
			let logic = SafeHTMLCoordinatorLogic()
			let navigator = FakeNavigator()
			logic.currentBaseURL = URL(string: "https://tyfloswiat.pl")
			logic.attach(navigator: navigator)
			logic.requestRender(forHTML: "<p>Tekst</p>", fontSize: 17)
			try logic.didFail(navigation: XCTUnwrap(navigator.lastNavigation), error: URLError(.cannotLoadFromNetwork))
			XCTAssertEqual(navigator.loadCallCount, 2)
			XCTAssertEqual(navigator.lastBaseURL, URL(string: "https://tyfloswiat.pl"))
			try logic.didFail(navigation: XCTUnwrap(navigator.lastNavigation), error: URLError(.cannotLoadFromNetwork))
			XCTAssertEqual(navigator.loadCallCount, 2)
			XCTAssertTrue(logic.state.showsRetryButton)
			logic.prepareForTeardown()
		}

		func testStaleFinishCannotDisarmCurrentTimeout() async throws {
			let logic = SafeHTMLCoordinatorLogic(renderTimeout: 0.02)
			let navigator = FakeNavigator()
			logic.attach(navigator: navigator)
			logic.requestRender(forHTML: "<p>Stary</p>", fontSize: 17)
			let old = try XCTUnwrap(navigator.lastNavigation)
			logic.requestRender(forHTML: "<p>Nowy</p>", fontSize: 17)
			logic.didFinish(navigation: old)
			try await Task.sleep(nanoseconds: 200_000_000)
			XCTAssertEqual(navigator.loadCallCount, 3)
			logic.prepareForTeardown()
		}

		private final class FakeNavigator: SafeHTMLNavigating {
			var navigationDelegate: WKNavigationDelegate?
			var uiDelegate: WKUIDelegate?
			private let webView = WKWebView()
			var loadCallCount = 0
			var lastNavigation: WKNavigation?
			var lastBaseURL: URL?

			func stopLoading() { webView.stopLoading() }

			func loadHTMLString(_ html: String, baseURL: URL?) -> WKNavigation? {
				loadCallCount += 1
				lastBaseURL = baseURL
				let navigation = webView.loadHTMLString(html, baseURL: baseURL)
				lastNavigation = navigation
				return navigation
			}
		}
	}
#endif
