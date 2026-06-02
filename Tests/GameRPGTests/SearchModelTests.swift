// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import GameRPG

@MainActor
struct SearchModelTests {
    @Test func initializesWithEmptyResults() async throws {
        let model = SearchModel()

        #expect(model.searchText.isEmpty)
        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
        #expect(model.selection == nil)
    }

    @Test func initializesWithSearchText() async throws {
        let model = SearchModel(searchText: "test")

        #expect(model.searchText == "test")
        #expect(model.results.isEmpty)
    }

    @Test func cancelSearchCancelsTask() async throws {
        let model = SearchModel()

        // Create a long-running task
        let task = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(10))
        }

        model.setSearchTask(task)
        model.cancelSearch()

        // Task should be cancelled - just verify it completes
        await task.value
    }

    @Test func setSearchTaskStoresTask() async throws {
        let model = SearchModel()
        var completed = false

        let task = Task<Void, Never> {
            try? await Task.sleep(for: .milliseconds(100))
            completed = true
        }

        model.setSearchTask(task)
        await model.awaitCurrentSearch()

        #expect(completed == true)
    }

    @Test func awaitCurrentSearchWaitsForCompletion() async throws {
        let model = SearchModel()
        var value = 0

        let task = Task<Void, Never> {
            try? await Task.sleep(for: .milliseconds(50))
            value = 42
        }

        model.setSearchTask(task)
        await model.awaitCurrentSearch()

        #expect(value == 42)
    }

    @Test func cancelSearchBeforeAwaitDoesNotHang() async throws {
        let model = SearchModel()

        let task = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(10))
        }

        model.setSearchTask(task)
        model.cancelSearch()

        // Should return immediately, not wait for cancelled task
        let start = ContinuousClock.now
        await model.awaitCurrentSearch()
        let duration = ContinuousClock.now - start

        // Should complete very quickly since task was cancelled
        #expect(duration < .seconds(1))
    }

    @Test func multipleSearchTasksCancelPrevious() async throws {
        let model = SearchModel()
        var firstCompleted = false
        var secondCompleted = false

        // First task - checks cancellation
        let firstTask = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            firstCompleted = true
        }
        model.setSearchTask(firstTask)

        // Cancel and start second task
        model.cancelSearch()

        let secondTask = Task<Void, Never> {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            secondCompleted = true
        }
        model.setSearchTask(secondTask)
        await model.awaitCurrentSearch()

        // First should be cancelled, second should complete
        #expect(firstCompleted == false)
        #expect(secondCompleted == true)
    }

    @Test func concurrentAccessDoesNotCrash() async throws {
        let model = SearchModel()

        // Spawn multiple concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let task = Task<Void, Never> {
                        try? await Task.sleep(for: .milliseconds(Double(i * 10)))
                    }
                    await MainActor.run {
                        model.setSearchTask(task)
                    }
                    await model.awaitCurrentSearch()
                }
            }

            // Add cancellation tasks
            for _ in 0..<5 {
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(25))
                    await MainActor.run {
                        model.cancelSearch()
                    }
                }
            }
        }

        // Should complete without crashes or data races
        #expect(true)
    }
}
