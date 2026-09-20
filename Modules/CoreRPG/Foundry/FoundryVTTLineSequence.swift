// @copyright André Trettin

import Foundation

// MARK: - Line-Oriented Reading

/// Iterates mapped or in-memory input without materializing an array containing every line.
struct FoundryVTTLineSequence: Sequence, IteratorProtocol {
    private let data: Data
    private var nextStart: Data.Index?

    init(_ data: Data) {
        self.data = data
        nextStart = data.startIndex
    }

    mutating func next() -> Data.SubSequence? {
        guard let start = nextStart, start < data.endIndex else {
            nextStart = nil
            return nil
        }

        var end = start
        while end < data.endIndex, data[end] != 0x0a {
            data.formIndex(after: &end)
        }
        if end < data.endIndex {
            nextStart = data.index(after: end)
            return data[start..<end]
        }

        nextStart = nil
        return data[start..<data.endIndex]
    }
}

