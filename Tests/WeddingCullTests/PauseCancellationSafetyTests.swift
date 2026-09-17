import XCTest
@testable import WeddingCullCore

final class PauseCancellationSafetyTests: XCTestCase {

    func testPauseAndResume() async throws {
        let coordinator = AnalysisCoordinator()

        await coordinator.pause()
        let isPausedInitial = await coordinator.getIsPaused()
        XCTAssertTrue(isPausedInitial)

        let resumedExpectation = expectation(description: "Task unblocks after resume")

        let task = Task {
            try await coordinator.waitIfPaused()
            resumedExpectation.fulfill()
        }

        // Give task time to enter waitIfPaused
        try await Task.sleep(nanoseconds: 50_000_000)

        await coordinator.resume()
        let isPausedAfter = await coordinator.getIsPaused()
        XCTAssertFalse(isPausedAfter)

        await fulfillment(of: [resumedExpectation], timeout: 2.0)
        try await task.value
    }

    func testPauseThenCancelNeverHangs() async throws {
        let coordinator = AnalysisCoordinator()

        await coordinator.pause()

        let cancelledExpectation = expectation(description: "Task unblocks and throws CancellationError")

        let task = Task {
            do {
                try await coordinator.waitIfPaused()
                XCTFail("Task should have thrown CancellationError on cancellation")
            } catch is CancellationError {
                cancelledExpectation.fulfill()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        // Ensure task is suspended waiting on pause continuation
        try await Task.sleep(nanoseconds: 50_000_000)

        // Cancel the task
        task.cancel()
        await coordinator.cancel()

        // MUST fulfill promptly (never hang forever)
        await fulfillment(of: [cancelledExpectation], timeout: 2.0)
    }

    func testRepeatedRapidPauseResumeCycles() async throws {
        let coordinator = AnalysisCoordinator()

        for _ in 0..<10 {
            await coordinator.pause()
            XCTAssertTrue(await coordinator.getIsPaused())

            let exp = expectation(description: "Rapid cycle completed")
            let task = Task {
                try await coordinator.waitIfPaused()
                exp.fulfill()
            }

            try await Task.sleep(nanoseconds: 10_000_000)
            await coordinator.resume()
            await fulfillment(of: [exp], timeout: 1.0)
            try await task.value
        }
    }

    func testMultipleTasksWaitingOnPauseResumeConcurrently() async throws {
        let coordinator = AnalysisCoordinator()
        await coordinator.pause()

        let taskCount = 8
        var expectations: [XCTestExpectation] = []
        var tasks: [Task<Void, Error>] = []

        for i in 0..<taskCount {
            let exp = expectation(description: "Task \(i) resumed")
            expectations.append(exp)
            tasks.append(Task {
                try await coordinator.waitIfPaused()
                exp.fulfill()
            })
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        // Resume all 8 tasks at once
        await coordinator.resume()

        await fulfillment(of: expectations, timeout: 2.0)

        for task in tasks {
            try await task.value
        }
    }
}
