import Foundation

struct HTMLRenderState: Equatable {
	enum Phase: Equatable {
		case idle
		case attempting
		case succeeded
		case failed(FailureReason)
	}

	enum FailureReason: Equatable {
		case emptyContent
		case renderFailed
		case timedOut
		case cancelled
	}

	enum Command: Equatable {
		case none
		case load(html: String, navigationID: Int)
	}

	private(set) var phase: Phase = .idle
	private(set) var currentHTML: String?
	private(set) var currentNavigationID: Int?
	private(set) var lastCompletedHTML: String?
	private(set) var canAutoRecover = false
	private(set) var showsRetryButton = false

	private var nextNavigationID = 1
	private var pendingManualRetry = false

	mutating func requestRender(html: String) -> Command {
		let normalized = html.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !normalized.isEmpty else {
			currentHTML = nil
			currentNavigationID = nil
			lastCompletedHTML = nil
			phase = .failed(.emptyContent)
			canAutoRecover = false
			showsRetryButton = false
			pendingManualRetry = false
			return .none
		}

		if pendingManualRetry {
			pendingManualRetry = false
			canAutoRecover = true
			showsRetryButton = false
			return beginLoad(html: normalized)
		}

		if currentHTML != normalized {
			canAutoRecover = true
			showsRetryButton = false
			return beginLoad(html: normalized)
		}

		switch phase {
		case .idle:
			return .none
		case .attempting, .succeeded:
			return .none
		case let .failed(reason):
			guard reason != .cancelled else {
				showsRetryButton = true
				return .none
			}
			guard canAutoRecover else {
				showsRetryButton = true
				return .none
			}
			canAutoRecover = false
			showsRetryButton = false
			return beginLoad(html: normalized)
		}
	}

	mutating func markManualRetryRequested() {
		pendingManualRetry = true
		showsRetryButton = false
	}

	mutating func didFinish(navigationID: Int) {
		guard navigationID == currentNavigationID, phase == .attempting else { return }
		phase = .succeeded
		lastCompletedHTML = currentHTML
		showsRetryButton = false
	}

	mutating func didFail(navigationID: Int, reason: FailureReason) {
		guard navigationID == currentNavigationID, phase == .attempting else { return }
		phase = .failed(reason)
		showsRetryButton = false
		if reason == .cancelled {
			canAutoRecover = false
		}
	}

	mutating func didTerminateProcess(navigationID: Int) {
		guard navigationID == currentNavigationID, phase == .attempting || phase == .succeeded else { return }
		phase = .failed(.renderFailed)
		showsRetryButton = false
	}

	mutating func didTimeout(navigationID: Int) {
		didFail(navigationID: navigationID, reason: .timedOut)
	}

	private mutating func beginLoad(html: String) -> Command {
		let navigationID = nextNavigationID
		nextNavigationID += 1
		currentHTML = html
		currentNavigationID = navigationID
		phase = .attempting
		return .load(html: html, navigationID: navigationID)
	}
}
