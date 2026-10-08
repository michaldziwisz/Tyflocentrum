//
//  SafeHTMLView.swift
//  Tyflocentrum
//

import SwiftUI
import UIKit
import WebKit

struct SafeHTMLView: UIViewRepresentable {
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize

	let htmlBody: String
	let baseURL: URL?
	let accessibilityIdentifier: String?

	init(htmlBody: String, baseURL: URL? = nil, accessibilityIdentifier: String? = nil) {
		self.htmlBody = htmlBody
		self.baseURL = baseURL
		self.accessibilityIdentifier = accessibilityIdentifier
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(allowedHost: baseURL?.host)
	}

	func makeUIView(context: Context) -> SafeHTMLContainerView {
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = .nonPersistent()
		configuration.defaultWebpagePreferences.allowsContentJavaScript = false

		let container = SafeHTMLContainerView(configuration: configuration)
		container.webView.accessibilityIdentifier = accessibilityIdentifier
		context.coordinator.attach(webView: container.webView, container: container)
		return container
	}

	func updateUIView(_ uiView: SafeHTMLContainerView, context: Context) {
		uiView.webView.accessibilityIdentifier = accessibilityIdentifier
		context.coordinator.allowedHost = baseURL?.host
		context.coordinator.currentBaseURL = baseURL
		context.coordinator.attach(webView: uiView.webView, container: uiView)
		context.coordinator.requestRender(forHTML: htmlBody, fontSize: UIFont.preferredFont(forTextStyle: .body).pointSize)
	}

	static func dismantleUIView(_ uiView: SafeHTMLContainerView, coordinator: Coordinator) {
		coordinator.prepareForTeardown()
		uiView.hideRetryButton()
		uiView.hideMessageLabel()
		uiView.webView.navigationDelegate = nil
		uiView.webView.uiDelegate = nil
	}

	static func optimizeHTMLBody(_ body: String) -> String {
		var result = body
		result = result.replacingOccurrences(
			of: "(?i)<img(?![^>]*\\bloading=)",
			with: "<img loading=\"lazy\"",
			options: .regularExpression
		)
		result = result.replacingOccurrences(
			of: "(?i)<img(?![^>]*\\bdecoding=)",
			with: "<img decoding=\"async\"",
			options: .regularExpression
		)
		result = result.replacingOccurrences(
			of: "(?i)<img(?![^>]*\\bfetchpriority=)",
			with: "<img fetchpriority=\"low\"",
			options: .regularExpression
		)
		return result
	}

	static func makeDocument(body: String, fontSize: CGFloat, languageCode: String = "pl") -> String {
		"""
		<!doctype html>
		<html lang="\(languageCode)">
		<head>
		  <meta charset="utf-8">
		  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
		  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; style-src 'unsafe-inline'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
		  <style>
			:root { color-scheme: light dark; }
			body {
			  font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif;
			  font-size: \(fontSize)px;
			  line-height: 1.45;
			  margin: 0;
			  padding: 16px;
			  overflow-wrap: anywhere;
			  -webkit-text-size-adjust: 100%;
			}
			img { max-width: 100%; height: auto; }
			table { width: 100%; border-collapse: collapse; display: block; overflow-x: auto; }
			th, td { border: 1px solid rgba(127, 127, 127, 0.35); padding: 0.4rem; vertical-align: top; }
			pre, code {
			  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;
			  white-space: pre-wrap;
			}
		  </style>
		</head>
		<body>
		  \(body)
		</body>
		</html>
		"""
	}

	static func isAllowedWebViewScheme(_ scheme: String?) -> Bool {
		switch scheme?.lowercased() {
		case "http", "https", "about":
			return true
		default:
			return false
		}
	}

	static func isAllowedExternalScheme(_ scheme: String?) -> Bool {
		switch scheme?.lowercased() {
		case "http", "https", "mailto", "tel":
			return true
		default:
			return false
		}
	}

	static func isAllowedMainFrameURL(_ url: URL, allowedHost: String?) -> Bool {
		switch url.scheme?.lowercased() {
		case "about":
			return true
		case "http", "https":
			guard let allowedHost else { return false }
			return url.host == allowedHost
		default:
			return false
		}
	}

	final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
		private let logic: SafeHTMLCoordinatorLogic
		private weak var container: SafeHTMLContainerView?

		var allowedHost: String? {
			get { logic.allowedHost }
			set { logic.allowedHost = newValue }
		}

		var currentBaseURL: URL? {
			get { logic.currentBaseURL }
			set { logic.currentBaseURL = newValue }
		}

		init(allowedHost: String? = nil) {
			logic = SafeHTMLCoordinatorLogic(allowedHost: allowedHost)
			super.init()
			#if DEBUG
				if ProcessInfo.processInfo.arguments.contains("UI_TESTING") {
					var remainingControlledFailures = 0
					if ProcessInfo.processInfo.arguments.contains("UI_TESTING_SAFE_HTML_FAIL_ONCE") {
						remainingControlledFailures = 1
					} else if ProcessInfo.processInfo.arguments.contains("UI_TESTING_SAFE_HTML_FAIL_TWICE") {
						remainingControlledFailures = 2
					}
					if remainingControlledFailures > 0 {
						logic.onStateChange = { [weak self] command in
							guard let self else { return }
							guard case let .load(_, navigationID) = command else { return }
							guard remainingControlledFailures > 0 else { return }
							guard self.logic.state.currentNavigationID == navigationID else { return }
							remainingControlledFailures -= 1
							DispatchQueue.main.async { [weak self] in
								guard let self else { return }
								guard self.logic.state.currentNavigationID == navigationID else { return }
								self.logic.didTerminateProcess()
							}
						}
					}
				}
			#endif
			logic.onOverlayChange = { [weak self] state in
				guard let self, let container = self.container else { return }
				container.webView.isHidden = state.phase == .failed(.emptyContent)
				switch state.phase {
				case .failed(.emptyContent):
					container.showMessage("Treść artykułu jest pusta.", identifier: "articleDetail.empty")
					container.hideRetryButton()
				case .failed:
					container.hideMessageLabel()
					if state.showsRetryButton {
						container.showRetryButton(action: #selector(self.retryButtonTapped), target: self)
					} else {
						container.hideRetryButton()
					}
				default:
					container.hideRetryButton()
					container.hideMessageLabel()
				}
			}
		}

		func attach(webView: WKWebView, container: SafeHTMLContainerView) {
			self.container = container
			logic.attach(navigator: webView)
			webView.navigationDelegate = self
			webView.uiDelegate = self
		}

		func requestRender(forHTML html: String, fontSize: CGFloat) {
			logic.requestRender(forHTML: html, fontSize: fontSize)
		}

		func prepareForTeardown() {
			logic.prepareForTeardown()
		}

		@objc private func retryButtonTapped() {
			logic.markManualRetryRequested()
		}

		func webView(_: WKWebView, didFinish navigation: WKNavigation!) {
			logic.didFinish(navigation: navigation)
		}

		func webView(_: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
			logic.didFail(navigation: navigation, error: error)
		}

		func webView(_: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
			logic.didFail(navigation: navigation, error: error)
		}

		func webViewWebContentProcessDidTerminate(_: WKWebView) {
			logic.didTerminateProcess()
		}

		func webView(
			_: WKWebView,
			decidePolicyFor navigationAction: WKNavigationAction,
			decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
		) {
			guard let url = navigationAction.request.url else {
				decisionHandler(.cancel)
				return
			}

			if navigationAction.navigationType == .linkActivated {
				openExternally(url)
				decisionHandler(.cancel)
				return
			}

			let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
			if isMainFrame {
				decisionHandler(SafeHTMLView.isAllowedMainFrameURL(url, allowedHost: allowedHost) ? .allow : .cancel)
				return
			}

			if SafeHTMLView.isAllowedWebViewScheme(url.scheme) {
				decisionHandler(.allow)
			} else {
				decisionHandler(.cancel)
			}
		}

		func webView(
			_: WKWebView,
			createWebViewWith _: WKWebViewConfiguration,
			for navigationAction: WKNavigationAction,
			windowFeatures _: WKWindowFeatures
		) -> WKWebView? {
			if let url = navigationAction.request.url {
				openExternally(url)
			}
			return nil
		}

		private func openExternally(_ url: URL) {
			guard SafeHTMLView.isAllowedExternalScheme(url.scheme) else { return }
			DispatchQueue.main.async {
				UIApplication.shared.open(url)
			}
		}
	}
}

final class SafeHTMLContainerView: UIView {
	let webView: WKWebView
	private let retryButton = UIButton(type: .system)
	private let messageLabel = UILabel()

	init(configuration: WKWebViewConfiguration) {
		webView = WKWebView(frame: .zero, configuration: configuration)
		super.init(frame: .zero)
		configureWebView()
		configureMessageLabel()
		configureRetryButton()
		layoutViews()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func showRetryButton(action: Selector, target: Any?) {
		retryButton.removeTarget(nil, action: nil, for: .allEvents)
		retryButton.addTarget(target, action: action, for: .touchUpInside)
		retryButton.isHidden = false
	}

	func hideRetryButton() {
		retryButton.isHidden = true
	}

	func showMessage(_ text: String, identifier: String) {
		messageLabel.text = text
		messageLabel.accessibilityIdentifier = identifier
		messageLabel.isHidden = false
	}

	func hideMessageLabel() {
		messageLabel.isHidden = true
		messageLabel.text = nil
	}

	private func configureWebView() {
		webView.isOpaque = false
		webView.backgroundColor = .clear
		webView.scrollView.backgroundColor = .clear
		webView.allowsBackForwardNavigationGestures = false
		webView.allowsLinkPreview = false
		if #available(iOS 15.0, *) {
			webView.underPageBackgroundColor = .clear
		}
	}

	private func configureMessageLabel() {
		messageLabel.numberOfLines = 0
		messageLabel.font = .preferredFont(forTextStyle: .body)
		messageLabel.adjustsFontForContentSizeCategory = true
		messageLabel.isHidden = true
		messageLabel.translatesAutoresizingMaskIntoConstraints = false
	}

	private func configureRetryButton() {
		retryButton.setTitle("Wczytaj treść ponownie", for: .normal)
		retryButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
		retryButton.titleLabel?.adjustsFontForContentSizeCategory = true
		retryButton.titleLabel?.numberOfLines = 0
		retryButton.accessibilityIdentifier = "articleDetail.retry"
		retryButton.isHidden = true
		retryButton.translatesAutoresizingMaskIntoConstraints = false
	}

	private func layoutViews() {
		for item in [webView, messageLabel, retryButton] {
			item.translatesAutoresizingMaskIntoConstraints = false
			addSubview(item)
		}

		NSLayoutConstraint.activate([
			webView.leadingAnchor.constraint(equalTo: leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: trailingAnchor),
			webView.topAnchor.constraint(equalTo: topAnchor),
			webView.bottomAnchor.constraint(equalTo: bottomAnchor),
			messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
			retryButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			retryButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
			retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
			retryButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 12),
		])
	}
}
