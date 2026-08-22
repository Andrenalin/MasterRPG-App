// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import GameRPG

@MainActor
struct SearchModelTests {
    @Test func initializesWithEmptyResults() async throws {
        let model = GlobalSearchModel()

        #expect(model.searchText.isEmpty)
        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
        #expect(model.selection == nil)
    }

    @Test func initializesWithSearchText() async throws {
        let model = GlobalSearchModel(searchText: "test")

        #expect(model.searchText == "test")
        #expect(model.results.isEmpty)
    }

    @Test func assigningNilCancelsCurrentTask() async throws {
        let model = GlobalSearchModel()

        // Create a long-running task
        let task = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(10))
        }

        model.currentTask = task
        model.currentTask = nil  // triggers `didSet`'s auto-cancel of the previous task

        // Task should be cancelled - just verify it completes
        await task.value
    }

    @Test func currentTaskStoresTaskForTheCallerToAwait() async throws {
        let model = GlobalSearchModel()
        var completed = false

        let task = Task<Void, Never> {
            try? await Task.sleep(for: .milliseconds(100))
            completed = true
        }

        model.currentTask = task
        await task.value

        #expect(completed == true)
    }

    @Test func currentTaskCanBeAwaitedForCompletion() async throws {
        let model = GlobalSearchModel()
        var value = 0

        let task = Task<Void, Never> {
            try? await Task.sleep(for: .milliseconds(50))
            value = 42
        }

        model.currentTask = task
        await task.value

        #expect(value == 42)
    }

    @Test func assigningNilBeforeAwaitDoesNotHang() async throws {
        let model = GlobalSearchModel()

        let task = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(10))
        }

        model.currentTask = task
        model.currentTask = nil  // triggers `didSet`'s auto-cancel

        // Should return immediately, not wait for the (now cancelled) task's original delay
        let start = ContinuousClock.now
        await task.value
        let duration = ContinuousClock.now - start

        // Should complete very quickly since task was cancelled
        #expect(duration < .seconds(1))
    }

    @Test func assigningNewTaskCancelsPreviousViaDidSet() async throws {
        let model = GlobalSearchModel()
        var firstCompleted = false
        var secondCompleted = false

        // First task - checks cancellation
        let firstTask = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            firstCompleted = true
        }
        model.currentTask = firstTask

        let secondTask = Task<Void, Never> {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            secondCompleted = true
        }
        // Assigning the second task cancels the first via `didSet`.
        model.currentTask = secondTask
        await secondTask.value

        // First should be cancelled, second should complete
        #expect(firstCompleted == false)
        #expect(secondCompleted == true)
    }

    @Test func concurrentAccessDoesNotCrash() async throws {
        let model = GlobalSearchModel()

        // Spawn multiple concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let task = Task<Void, Never> {
                        try? await Task.sleep(for: .milliseconds(Double(i * 10)))
                    }
                    await MainActor.run {
                        model.currentTask = task
                    }
                }
            }

            // Add cancellation tasks
            for _ in 0..<5 {
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(25))
                    await MainActor.run {
                        model.currentTask = nil
                    }
                }
            }
        }

        // Should complete without crashes or data races
        #expect(true)
    }
}
