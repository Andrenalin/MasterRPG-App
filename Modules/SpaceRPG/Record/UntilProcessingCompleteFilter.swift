/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
An asynchronous sequence filter this sample applies to the photogrammetry session.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Foundation
import RealityKit

struct UntilProcessingCompleteFilter<Base>: AsyncSequence,
                                            AsyncIteratorProtocol where Base: AsyncSequence, Base.Element == PhotogrammetrySession.Output, Base.AsyncIterator: Sendable {
    func makeAsyncIterator() -> UntilProcessingCompleteFilter {
        return self
    }

    typealias AsyncIterator = Self
    typealias Element = PhotogrammetrySession.Output

    private let inputSequence: Base
    private var completed: Bool = false
    private var iterator: Base.AsyncIterator

    init(input: Base) where Base.Element == Element {
        inputSequence = input
        iterator = inputSequence.makeAsyncIterator()
    }

    mutating func next() async throws -> Element? {
        if completed {
            return nil
        }

        guard let nextElement = try await iterator.next() else {
            completed = true
            return nil
        }

        if case .processingComplete = nextElement {
            completed = true
        }
        if case .processingCancelled = nextElement {
            completed = true
        }

        return nextElement
    }
}

#endif
