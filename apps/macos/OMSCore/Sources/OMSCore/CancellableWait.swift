import Foundation

/// Waits for a shared task, but stops the wait at once when the caller is cancelled.
///
/// `await task.value` ignores the caller's cancel. That is correct for work that other callers share,
/// for example a model load: the work must continue, only this caller stops waiting.
/// The shared task itself is not cancelled.
public func waitCancellably<Value: Sendable>(for task: Task<Value, Error>) async throws -> Value {
    let gate = ResumeOnce<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            gate.set(continuation)
            Task {
                do { gate.resume(with: .success(try await task.value)) } catch { gate.resume(with: .failure(error)) }
            }
        }
    } onCancel: {
        gate.resume(with: .failure(CancellationError()))
    }
}

/// Resumes a continuation exactly one time, also when the cancel arrives before the continuation exists.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var resumed = false

    func set(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result {
            resumed = true
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func resume(with result: Result<Value, Error>) {
        lock.lock()
        guard !resumed, self.result == nil else { lock.unlock(); return }
        guard let continuation else {
            self.result = result
            lock.unlock()
            return
        }
        resumed = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}
