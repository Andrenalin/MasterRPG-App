// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import AudioRPG

@Suite("Audio track loader")
struct AudioTrackLoaderTests {
    private actor Probe {
        private(set) var running = 0
        private(set) var maximum = 0

        func enter() {
            running += 1
            maximum = max(maximum, running)
        }

        func leave() {
            running -= 1
        }
    }

    @Test("Results keep the request order and skip what could not be loaded")
    func keepsOrderAndSkipsFailures() async {
        let results = await AudioTrackLoader.loadInOrder(Array(0..<10), limit: 3) { value -> Int? in
            // Later elements finish first.
            try? await Task.sleep(for: .milliseconds((10 - value) * 3))
            return value.isMultiple(of: 3) ? nil : value
        }

        #expect(results == [1, 2, 4, 5, 7, 8])
    }

    @Test("Never more than the limit load at the same time")
    func boundsConcurrency() async {
        let probe = Probe()
        let results = await AudioTrackLoader.loadInOrder(Array(0..<12), limit: 3) { value -> Int? in
            await probe.enter()
            try? await Task.sleep(for: .milliseconds(10))
            await probe.leave()
            return value
        }

        #expect(results.count == 12)
        #expect(await probe.maximum <= 3)
        #expect(await probe.maximum >= 2)
    }

    @Test("A limit below one still loads everything")
    func nonPositiveLimit() async {
        let results = await AudioTrackLoader.loadInOrder([1, 2, 3], limit: 0) { $0 }

        #expect(results == [1, 2, 3])
    }

    @Test("No requests give no items")
    func emptyInput() async {
        let results = await AudioTrackLoader.loadInOrder([Int](), limit: 3) { $0 }

        #expect(results.isEmpty)
    }
}
#endif
