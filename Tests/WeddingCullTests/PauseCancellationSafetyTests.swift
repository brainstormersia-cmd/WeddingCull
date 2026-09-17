import XCTest
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif
#if canImport(TestDatasetGeneratorLibrary)
import TestDatasetGeneratorLibrary
#endif

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
            let isPaused = await coordinator.getIsPaused()
            XCTAssertTrue(isPaused)

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

    func testSecondAnalysisAfterCancellationSucceedsPromptly() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cancel_pipeline_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Generate small test dataset
        let generator = SyntheticWeddingGenerator()
        let config = SyntheticWeddingGenerator.GeneratorConfig(generateLargeImages: false, targetTotalPhotos: 20)
        _ = try? generator.generateDataset(at: tempDir, config: config)

        let pipeline = AnalysisPipeline()

        // 1. Launch first analysis and cancel it quickly
        let cancelledExp = expectation(description: "First pipeline cancels")
        let firstTask = Task {
            do {
                _ = try await pipeline.runAnalysis(sourceFolder: tempDir, targetCount: 10)
                XCTFail("First task should have been cancelled")
            } catch is CancellationError {
                cancelledExp.fulfill()
            } catch {
                // Cancelled or thrown
                cancelledExp.fulfill()
            }
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        firstTask.cancel()
        await pipeline.cancel()

        await fulfillment(of: [cancelledExp], timeout: 5.0)

        // 2. Launch second analysis on same pipeline instance - MUST succeed
        let secondSession = try await pipeline.runAnalysis(sourceFolder: tempDir, targetCount: 10)
        XCTAssertGreaterThan(secondSession.photos.count, 0, "Second pipeline run must succeed and process photos")
        XCTAssertEqual(secondSession.targetSelectionCount, 10)
    }
}
