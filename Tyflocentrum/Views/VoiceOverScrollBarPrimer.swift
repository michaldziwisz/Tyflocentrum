//
//  VoiceOverScrollBarPrimer.swift
//  Tyflocentrum
//

import SwiftUI
import UIKit

/// Ensures VoiceOver users can access the system scroll bar immediately (without first scrolling).
///
/// This flashes the underlying UIScrollView indicators once when `shouldPrime` changes from `false` to `true`.
struct VoiceOverScrollBarPrimer: UIViewRepresentable {
	let shouldPrime: Bool

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func makeUIView(context _: Context) -> UIView {
		UIView(frame: .zero)
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
				guard let scrollView = uiView.enclosingScrollView() else { return }
				scrollView.showsVerticalScrollIndicator = true
				scrollView.flashScrollIndicators()
			}
		}
	}
}

private extension UIView {
	func enclosingScrollView() -> UIScrollView? {
		var view: UIView? = self
		while let current = view {
			if let found = current.firstScrollViewInSubtree() {
				return found
			}
			view = current.superview
		}
		return nil
	}

	func firstScrollViewInSubtree() -> UIScrollView? {
		if let scrollView = self as? UIScrollView { return scrollView }
		for subview in subviews {
			if let found = subview.firstScrollViewInSubtree() {
				return found
			}
		}
		return nil
	}
}
