import Foundation

enum AsyncTimeoutError: Error {
	case timedOut
}

private final class TimeoutState<T>: @unchecked Sendable {
	private let lock = NSLock()
	private var didFinish = false
	private var continuation: CheckedContinuation<T, Error>?
	private var pendingResult: Result<T, Error>?

	var operationTask: Task<Void, Never>?
	var timeoutTask: Task<Void, Never>?

	func isFinished() -> Bool {
		lock.lock()
		defer { lock.unlock() }
		return didFinish
	}

	func setContinuation(_ continuation: CheckedContinuation<T, Error>) {
		lock.lock()
		self.continuation = continuation
		let didFinish = didFinish
		let pendingResult = pendingResult
		self.pendingResult = nil
		let operationTask = operationTask
		let timeoutTask = timeoutTask
		lock.unlock()

		if didFinish, let pendingResult {
			operationTask?.cancel()
			timeoutTask?.cancel()
			continuation.resume(with: pendingResult)
		}
	}

	func finish(_ result: Result<T, Error>) {
		lock.lock()
		guard !didFinish else {
			lock.unlock()
			return
		}
		didFinish = true

		if let continuation = continuation {
			let operationTask = operationTask
			let timeoutTask = timeoutTask
			lock.unlock()

			operationTask?.cancel()
			timeoutTask?.cancel()
			continuation.resume(with: result)
			return
		}

		pendingResult = result
		lock.unlock()
	}
}

func withTimeout<T>(
	_ seconds: TimeInterval,
	operation: @escaping @Sendable () async throws -> T
) async throws -> T {
	guard seconds > 0 else { return try await operation() }

	let state = TimeoutState<T>()

	return try await withTaskCancellationHandler {
		try await withCheckedThrowingContinuation { continuation in
			state.setContinuation(continuation)
			guard !state.isFinished() else { return }

			state.operationTask = Task.detached {
				do {
					let value = try await operation()
					state.finish(.success(value))
				} catch {
					state.finish(.failure(error))
				}
			}

			state.timeoutTask = Task.detached {
				do {
					try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
					state.finish(.failure(AsyncTimeoutError.timedOut))
				} catch {
					// Cancelled.
				}
			}
		}
	} onCancel: {
		state.finish(.failure(CancellationError()))
	}
}
