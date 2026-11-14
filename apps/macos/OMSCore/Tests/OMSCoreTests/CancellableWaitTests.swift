import Foundation
import Testing
@testable import OMSCore

struct CancellableWaitTests {
    @Test func returnsTheValueOfTheSharedTask() async throws {
        let shared = Task<Int, Error> { 42 }
        #expect(try await waitCancellably(for: shared) == 42)
    }

    @Test func cancelStopsTheWaitAtOnceAndTheSharedTaskContinues() async throws {
        let shared = Task<Int, Error> {
            try? await Task.sleep(for: .seconds(2))
            return 7
        }
        let waiter = Task { try await waitCancellably(for: shared) }
        try await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(ContinuousClock.now - start < .milliseconds(500))
        #expect(!shared.isCancelled)
        #expect(try await shared.value == 7)
    }

    @Test func aCallerThatIsCancelledBeforeTheWaitDoesNotWait() async throws {
        let shared = Task<Int, Error> {
            try? await Task.sleep(for: .seconds(2))
            return 1
        }
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await waitCancellably(for: shared)
        }
        let start = ContinuousClock.now
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(ContinuousClock.now - start < .milliseconds(500))
    }

    @Test func passesTheErrorOfTheSharedTask() async {
        struct Failure: Error {}
        let shared = Task<Int, Error> { throw Failure() }
        await #expect(throws: Failure.self) { try await waitCancellably(for: shared) }
    }
}
