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
		private var primeGeneration = 0

		func update(uiView: UIView, shouldPrime: Bool) {
			defer { lastShouldPrime = shouldPrime }
			guard shouldPrime, !lastShouldPrime else { return }
			guard UIAccessibility.isVoiceOverRunning else { return }
			guard !ProcessInfo.processInfo.arguments.contains("UI_TESTING") else { return }

			primeGeneration += 1
			let generation = primeGeneration
			attemptPrime(uiView: uiView, generation: generation, remainingAttempts: 25)
		}

		private func attemptPrime(uiView: UIView, generation: Int, remainingAttempts: Int) {
			guard remainingAttempts > 0 else { return }

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak uiView] in
				guard let self else { return }
				guard generation == self.primeGeneration else { return }
				guard let uiView else { return }

				guard UIAccessibility.isVoiceOverRunning else { return }
				guard !ProcessInfo.processInfo.arguments.contains("UI_TESTING") else { return }

				guard let scrollView = uiView.findTargetScrollView() else {
					self.attemptPrime(uiView: uiView, generation: generation, remainingAttempts: remainingAttempts - 1)
					return
				}

				guard scrollView.window != nil else {
					self.attemptPrime(uiView: uiView, generation: generation, remainingAttempts: remainingAttempts - 1)
					return
				}

				scrollView.showsVerticalScrollIndicator = true
				scrollView.layoutIfNeeded()
				scrollView.superview?.layoutIfNeeded()

				let topOffsetY = -scrollView.adjustedContentInset.top
				let bottomOffsetY = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
				let maxOffsetY = max(topOffsetY, bottomOffsetY)
				guard maxOffsetY > topOffsetY else {
					self.attemptPrime(uiView: uiView, generation: generation, remainingAttempts: remainingAttempts - 1)
					return
				}

				guard !scrollView.isDragging, !scrollView.isDecelerating, !scrollView.isTracking else { return }

				let originalOffset = scrollView.contentOffset
				guard originalOffset.y <= topOffsetY + 0.5 else { return }

				let nudgedY = min(max(topOffsetY + 1, 1), maxOffsetY)
				let nudgedOffset = CGPoint(x: originalOffset.x, y: nudgedY)
				scrollView.setContentOffset(nudgedOffset, animated: false)
				scrollView.flashScrollIndicators()

				DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
					scrollView.setContentOffset(originalOffset, animated: false)
					scrollView.flashScrollIndicators()
				}
			}
		}
	}
}

private extension UIView {
	func findTargetScrollView() -> UIScrollView? {
		let identifier = (self as? VoiceOverScrollBarPrimerHostView)?.targetIdentifier

		var ancestor: UIView? = self
		while let view = ancestor {
			if let scrollView = view as? UIScrollView {
				if let identifier, (scrollView.accessibilityIdentifier ?? "").isEmpty {
					scrollView.accessibilityIdentifier = identifier
				}
				return scrollView
			}
			ancestor = view.superview
		}

		let rootView: UIView = window ?? self

		let allScrollViews = rootView.allScrollViews()
		if let identifier, let matched = allScrollViews.first(where: { $0.accessibilityIdentifier == identifier }) {
			return matched
		}

		let hostRect = convert(bounds, to: rootView)
		var bestScrollView: UIScrollView?
		var bestScore: CGFloat = -1

		for scrollView in allScrollViews {
			guard scrollView.alpha > 0.01, !scrollView.isHidden else { continue }
			let scrollRect = scrollView.convert(scrollView.bounds, to: rootView)
			let intersection = hostRect.intersection(scrollRect)
			guard !intersection.isNull else { continue }
			let score = intersection.width * intersection.height
			if score > bestScore {
				bestScore = score
				bestScrollView = scrollView
			}
		}

		return bestScrollView
	}

	func allScrollViews() -> [UIScrollView] {
		var result: [UIScrollView] = []
		collectScrollViews(into: &result)
		return result
	}

	private func collectScrollViews(into result: inout [UIScrollView]) {
		if let scrollView = self as? UIScrollView {
			result.append(scrollView)
		}

		for subview in subviews {
			subview.collectScrollViews(into: &result)
		}
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
