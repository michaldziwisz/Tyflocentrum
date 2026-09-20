import Foundation
import XCTest

@testable import Tyflocentrum

final class HTMLRenderStateTests: XCTestCase {
	func testFirstRequestStartsAttemptAndEmitsLoad() {
		var state = HTMLRenderState()
		let html = "<p>Test</p>"

		let command = state.requestRender(html: html)

		XCTAssertEqual(command, .load(html: html, navigationID: 1))
		XCTAssertEqual(state.phase, .attempting)
		XCTAssertEqual(state.currentHTML, html)
		XCTAssertEqual(state.currentNavigationID, 1)
		XCTAssertTrue(state.canAutoRecover)
		XCTAssertFalse(state.showsRetryButton)
	}

	func testSameHTMLDoesNotReloadWhileCurrentAttemptIsHealthy() {
		var state = HTMLRenderState()
		_ = state.requestRender(html: "<p>Test</p>")
		state.didFinish(navigationID: 1)

		let command = state.requestRender(html: "<p>Test</p>")

		XCTAssertEqual(command, .none)
		XCTAssertEqual(state.phase, .succeeded)
		XCTAssertEqual(state.currentNavigationID, 1)
	}

	func testFailureAutoRecoversOnceFromSameHTML() {
		var state = HTMLRenderState()
		let html = "<p>Test</p>"
		_ = state.requestRender(html: html)

		state.didFail(navigationID: 1, reason: .renderFailed)
		let retry = state.requestRender(html: html)

		XCTAssertEqual(retry, .load(html: html, navigationID: 2))
		XCTAssertEqual(state.phase, .attempting)
		XCTAssertFalse(state.canAutoRecover)
		XCTAssertFalse(state.showsRetryButton)
	}

	func testSecondFailureOnSameHTMLShowsRetryButtonWithoutLoop() {
		var state = HTMLRenderState()
		let html = "<p>Test</p>"
		_ = state.requestRender(html: html)
		state.didFail(navigationID: 1, reason: .renderFailed)
		_ = state.requestRender(html: html)
		state.didFail(navigationID: 2, reason: .renderFailed)

		let command = state.requestRender(html: html)

		XCTAssertEqual(command, .none)
		XCTAssertEqual(state.phase, .failed(.renderFailed))
		XCTAssertTrue(state.showsRetryButton)
	}

	func testManualRetryClearsFailedStateAndLoadsAgain() {
		var state = HTMLRenderState()
		let html = "<p>Test</p>"
		_ = state.requestRender(html: html)
		state.didFail(navigationID: 1, reason: .renderFailed)
		_ = state.requestRender(html: html)
		state.didFail(navigationID: 2, reason: .renderFailed)

		state.markManualRetryRequested()
		let retry = state.requestRender(html: html)

		XCTAssertEqual(retry, .load(html: html, navigationID: 3))
		XCTAssertEqual(state.phase, .attempting)
		XCTAssertTrue(state.canAutoRecover)
		XCTAssertFalse(state.showsRetryButton)
	}

	func testStaleCallbacksDoNotOverrideNewNavigation() {
		var state = HTMLRenderState()
		_ = state.requestRender(html: "<p>One</p>")
		_ = state.requestRender(html: "<p>Two</p>")

		state.didFail(navigationID: 1, reason: .renderFailed)

		XCTAssertEqual(state.phase, .attempting)
		state.didFinish(navigationID: 2)
		XCTAssertEqual(state.phase, .succeeded)
	}

	func testSupersededNavigationCancellationDoesNotLoopOrShowError() {
		var state = HTMLRenderState()
		let html = "<p>Test</p>"
		_ = state.requestRender(html: html)

		_ = state.requestRender(html: "<p>Nowy dokument</p>")
		state.didFail(navigationID: 1, reason: .cancelled)
		let command = state.requestRender(html: "<p>Nowy dokument</p>")

		XCTAssertEqual(command, .none)
		XCTAssertEqual(state.phase, .attempting)
		XCTAssertFalse(state.showsRetryButton)
	}

	func testActiveCancellationStopsLoadingAndRequiresManualRetry() {
		var state = HTMLRenderState()
		let html = "<p>Test</p>"
		_ = state.requestRender(html: html)

		state.didFail(navigationID: 1, reason: .cancelled)
		let command = state.requestRender(html: html)

		XCTAssertEqual(command, .none)
		XCTAssertEqual(state.phase, .failed(.cancelled))
		XCTAssertTrue(state.showsRetryButton)
	}

	func testTerminateEventTriggersSingleRecovery() {
		var state = HTMLRenderState()
		let html = "<p>Test</p>"
		_ = state.requestRender(html: html)
		state.didFinish(navigationID: 1)

		state.didTerminateProcess(navigationID: 1)
		let retry = state.requestRender(html: html)

		XCTAssertEqual(retry, .load(html: html, navigationID: 2))
		XCTAssertEqual(state.phase, .attempting)
		XCTAssertFalse(state.canAutoRecover)
	}

	func testTimeoutTriggersRecoveryThenRetryButton() {
		var state = HTMLRenderState()
		let html = "<p>Test</p>"
		_ = state.requestRender(html: html)

		state.didTimeout(navigationID: 1)
		XCTAssertEqual(state.requestRender(html: html), .load(html: html, navigationID: 2))
		state.didTimeout(navigationID: 2)
		XCTAssertEqual(state.requestRender(html: html), .none)
		XCTAssertTrue(state.showsRetryButton)
		XCTAssertEqual(state.phase, .failed(.timedOut))
	}

	func testLateCompletionCannotEraseTerminalFailure() {
		var state = HTMLRenderState()
		_ = state.requestRender(html: "<p>Test</p>")
		state.didFail(navigationID: 1, reason: .cancelled)
		state.didFinish(navigationID: 1)
		XCTAssertEqual(state.phase, .failed(.cancelled))
	}

	func testNavigationFailureAfterSuccessIsIgnoredButProcessFailureRecovers() {
		var state = HTMLRenderState()
		_ = state.requestRender(html: "<p>Test</p>")
		state.didFinish(navigationID: 1)
		state.didFail(navigationID: 1, reason: .renderFailed)
		XCTAssertEqual(state.phase, .succeeded)
		state.didTerminateProcess(navigationID: 1)
		XCTAssertEqual(state.requestRender(html: "<p>Test</p>"), .load(html: "<p>Test</p>", navigationID: 2))
	}

	func testEmptyHTMLDoesNotLoadAndShowsEmptyReason() {
		var state = HTMLRenderState()

		let command = state.requestRender(html: "   \n\t")

		XCTAssertEqual(command, .none)
		XCTAssertEqual(state.phase, .failed(.emptyContent))
		XCTAssertFalse(state.canAutoRecover)
		XCTAssertFalse(state.showsRetryButton)
	}
}
