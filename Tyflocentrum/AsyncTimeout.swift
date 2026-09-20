import Foundation

enum AsyncTimeoutError: Error {
	case timedOut
}

struct RequestAttemptBudget: Equatable {
	let totalDeadline: ContinuousClock.Instant
	let attemptTimeout: TimeInterval
	let maxAttempts: Int

	init(totalBudget: TimeInterval, attemptTimeout: TimeInterval, maxAttempts: Int = 2, clock: ContinuousClock = .init()) {
		totalDeadline = clock.now.advanced(by: .seconds(totalBudget))
		self.attemptTimeout = attemptTimeout
		self.maxAttempts = max(1, maxAttempts)
	}

	func remainingSeconds(clock: ContinuousClock = .init()) -> TimeInterval {
		let remaining = clock.now.duration(to: totalDeadline)
		guard remaining > .zero else { return 0 }
		let seconds = Double(remaining.components.seconds)
		let attoseconds = Double(remaining.components.attoseconds) / 1_000_000_000_000_000_000
		return max(0, seconds + attoseconds)
	}

	func timeout(forAttempt attempt: Int, clock: ContinuousClock = .init()) -> TimeInterval? {
		guard attempt > 0, attempt <= maxAttempts else { return nil }
		let remainingSeconds = remainingSeconds(clock: clock)
		let effectiveTimeout = min(attemptTimeout, remainingSeconds)
		return effectiveTimeout > 0 ? effectiveTimeout : nil
	}

	func canRetry(after delay: TimeInterval = 0, clock: ContinuousClock = .init()) -> Bool {
		guard delay.isFinite, delay >= 0 else { return false }
		return delay < remainingSeconds(clock: clock)
	}
}

func withTimeout<T>(
	_ seconds: TimeInterval,
	operation: @escaping @Sendable () async throws -> T
) async throws -> T {
	guard seconds > 0 else { return try await operation() }

	return try await withThrowingTaskGroup(of: T.self) { group in
		group.addTask {
			try await operation()
		}

		group.addTask {
			try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
			throw AsyncTimeoutError.timedOut
		}

		guard let result = try await group.next() else {
			throw CancellationError()
		}

		group.cancelAll()
		return result
	}
}
