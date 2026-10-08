#if canImport(UIKit)
	import Foundation
	import UIKit
	import WebKit

	protocol SafeHTMLNavigating: AnyObject {
		var navigationDelegate: WKNavigationDelegate? { get set }
		var uiDelegate: WKUIDelegate? { get set }
		func stopLoading()
		@discardableResult
		func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation?
	}

	extension WKWebView: SafeHTMLNavigating {}

	final class SafeHTMLCoordinatorLogic {
		private(set) var state = HTMLRenderState()
		var allowedHost: String?
		var currentBaseURL: URL?
		var onStateChange: ((HTMLRenderState.Command) -> Void)?
		var onOverlayChange: ((HTMLRenderState) -> Void)?

		private weak var navigator: SafeHTMLNavigating?
		private var isDisposed = false
		private var navigationIDsByObjectID: [ObjectIdentifier: Int] = [:]
		private var currentNavigationObjectID: ObjectIdentifier?
		private var renderTimeoutWorkItem: DispatchWorkItem?
		private let renderTimeout: TimeInterval

		init(allowedHost: String? = nil, renderTimeout: TimeInterval = 12) {
			precondition(renderTimeout.isFinite && renderTimeout > 0)
			self.allowedHost = allowedHost
			self.renderTimeout = renderTimeout
		}

		func attach(navigator: SafeHTMLNavigating) {
			self.navigator = navigator
		}

		func requestRender(forHTML htmlBody: String, fontSize: CGFloat) {
			guard !isDisposed else { return }
			let trimmedBody = htmlBody.trimmingCharacters(in: .whitespacesAndNewlines)
			let command: HTMLRenderState.Command
			if trimmedBody.isEmpty {
				command = state.requestRender(html: "")
			} else {
				let optimizedBody = SafeHTMLView.optimizeHTMLBody(trimmedBody)
				let document = SafeHTMLView.makeDocument(body: optimizedBody, fontSize: fontSize)
				command = state.requestRender(html: document)
			}
			execute(command)
		}

		func markManualRetryRequested() {
			guard !isDisposed else { return }
			state.markManualRetryRequested()
			execute(state.requestRender(html: state.currentHTML ?? ""))
		}

		func didFinish(navigation: WKNavigation?) {
			guard !isDisposed, let navigationID = activeNavigationID(for: navigation) else { return }
			cancelTimeout(for: navigationID)
			state.didFinish(navigationID: navigationID)
			forgetNavigation(navigation)
			execute(state.requestRender(html: state.currentHTML ?? ""))
		}

		func didFail(navigation: WKNavigation?, error: Error) {
			guard !isDisposed, let navigationID = activeNavigationID(for: navigation) else { return }
			cancelTimeout(for: navigationID)
			let nsError = error as NSError
			if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
				state.didFail(navigationID: navigationID, reason: .cancelled)
			} else {
				state.didFail(navigationID: navigationID, reason: .renderFailed)
			}
			forgetNavigation(navigation)
			execute(state.requestRender(html: state.currentHTML ?? ""))
		}

		func didTerminateProcess() {
			guard !isDisposed, let navigationID = state.currentNavigationID else { return }
			cancelTimeout(for: navigationID)
			state.didTerminateProcess(navigationID: navigationID)
			execute(state.requestRender(html: state.currentHTML ?? ""))
		}

		func prepareForTeardown() {
			isDisposed = true
			cancelTimeout(force: true)
			navigationIDsByObjectID.removeAll()
			currentNavigationObjectID = nil
			navigator?.stopLoading()
		}

		private func execute(_ command: HTMLRenderState.Command) {
			guard !isDisposed else { return }
			onOverlayChange?(state)
			onStateChange?(command)
			switch command {
			case .none:
				if case .failed = state.phase {
					cancelTimeout(force: true)
					navigationIDsByObjectID.removeAll()
					currentNavigationObjectID = nil
					navigator?.stopLoading()
				}
			case let .load(html, navigationID):
				beginLoading(navigationID: navigationID, html: html)
			}
		}

		private func beginLoading(navigationID: Int, html: String) {
			guard !isDisposed else { return }
			cancelTimeout(force: true)
			// Stare callbacki nie należą do nowej próby; usuń je przed stopLoading.
			navigationIDsByObjectID.removeAll()
			currentNavigationObjectID = nil
			navigator?.stopLoading()
			let navigation = navigator?.loadHTMLString(html, baseURL: currentBaseURL)
			if let navigation {
				let objectID = ObjectIdentifier(navigation)
				navigationIDsByObjectID[objectID] = navigationID
				currentNavigationObjectID = objectID
			} else {
				currentNavigationObjectID = nil
			}
			scheduleTimeout(for: navigationID)
		}

		private func activeNavigationID(for navigation: WKNavigation?) -> Int? {
			guard let activeNavigationID = state.currentNavigationID, let navigation else { return nil }
			let objectID = ObjectIdentifier(navigation)
			guard navigationIDsByObjectID[objectID] == activeNavigationID else { return nil }
			return activeNavigationID
		}

		private func forgetNavigation(_ navigation: WKNavigation?) {
			guard let navigation else { return }
			let objectID = ObjectIdentifier(navigation)
			navigationIDsByObjectID.removeValue(forKey: objectID)
			if currentNavigationObjectID == objectID {
				currentNavigationObjectID = nil
			}
		}

		private func scheduleTimeout(for navigationID: Int) {
			let workItem = DispatchWorkItem { [weak self] in
				guard let self, !self.isDisposed else { return }
				guard self.state.currentNavigationID == navigationID else { return }
				self.state.didTimeout(navigationID: navigationID)
				self.currentNavigationObjectID = nil
				self.execute(self.state.requestRender(html: self.state.currentHTML ?? ""))
			}
			renderTimeoutWorkItem = workItem
			DispatchQueue.main.asyncAfter(deadline: .now() + renderTimeout, execute: workItem)
		}

		private func cancelTimeout(for navigationID: Int) {
			guard state.currentNavigationID == navigationID else { return }
			cancelTimeout(force: true)
		}

		private func cancelTimeout(force: Bool) {
			guard force else { return }
			renderTimeoutWorkItem?.cancel()
			renderTimeoutWorkItem = nil
		}
	}
#endif
