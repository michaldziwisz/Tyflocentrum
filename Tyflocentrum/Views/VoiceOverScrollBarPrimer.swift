//
//  VoiceOverScrollBarPrimer.swift
//  Tyflocentrum
//

import SwiftUI
import UIKit

/// Ensures VoiceOver users can access the system scroll bar immediately (without first scrolling).
///
/// This performs a tiny scroll “nudge” once when `shouldPrime` changes from `false` to `true`.
struct VoiceOverScrollBarPrimer: UIViewRepresentable {
	let shouldPrime: Bool
	let targetIdentifier: String?

	init(shouldPrime: Bool, targetIdentifier: String? = nil) {
		self.shouldPrime = shouldPrime
		self.targetIdentifier = targetIdentifier
	}

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func makeUIView(context _: Context) -> UIView {
		VoiceOverScrollBarPrimerHostView(targetIdentifier: targetIdentifier)
	}

	func updateUIView(_ uiView: UIView, context: Context) {
		context.coordinator.update(uiView: uiView, shouldPrime: shouldPrime)
	}

	final class Coordinator {
		private var lastShouldPrime = false

		func update(uiView: UIView, shouldPrime: Bool) {
			defer { lastShouldPrime = shouldPrime }
			guard shouldPrime, !lastShouldPrime else { return }
			guard UIAccessibility.isVoiceOverRunning else { return }

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak uiView] in
				guard let uiView else { return }
				guard let scrollView = uiView.findTargetScrollView() else { return }
				scrollView.showsVerticalScrollIndicator = true
				scrollView.layoutIfNeeded()

				let originalOffset = scrollView.contentOffset
				let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
				guard maxOffsetY > 0 else { return }

				let nudgedOffset = CGPoint(x: originalOffset.x, y: min(originalOffset.y + 1, maxOffsetY))
				scrollView.setContentOffset(nudgedOffset, animated: false)
				scrollView.setContentOffset(originalOffset, animated: false)
				scrollView.flashScrollIndicators()
			}
		}
	}
}

private extension UIView {
	func findTargetScrollView() -> UIScrollView? {
		let rootView: UIView = window ?? self
		let identifier = (self as? VoiceOverScrollBarPrimerHostView)?.targetIdentifier
		return rootView.firstScrollView(where: { scrollView in
			guard let identifier else { return true }
			return scrollView.accessibilityIdentifier == identifier
		})
	}

	func firstScrollView(where predicate: (UIScrollView) -> Bool) -> UIScrollView? {
		if let scrollView = self as? UIScrollView, predicate(scrollView) {
			return scrollView
		}

		for subview in subviews {
			if let found = subview.firstScrollView(where: predicate) {
				return found
			}
		}
		return nil
	}
}

private final class VoiceOverScrollBarPrimerHostView: UIView {
	let targetIdentifier: String?

	init(targetIdentifier: String?) {
		self.targetIdentifier = targetIdentifier
		super.init(frame: .zero)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
