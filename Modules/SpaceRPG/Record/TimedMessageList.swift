/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A timed queue of messages that modifies published properties.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Combine
import CoreRPG
import Foundation
import SwiftUI

/// Adds a message to a queue that appears with a minimum duration.
///
/// The duration extends if the queue refreshes and automatically removes items for which the timer is expired.
@MainActor @Observable
final class TimedMessageList {
    /// A unique container for a message string and timestamps.
    ///
    /// SwiftUI can consistently animate each `Message` instance because the
    /// type adopts the `Identifiable` proptocol.
    /// The `id` property is unique and consistent for the life of the instance,
    /// as opposed to the `message` property, which may have identical content
    /// to another message instance.
    struct Message: Identifiable {
        /// A stable identifier which ensures that animations work properly.
        let id = UUID()

        /// The text of the message.
        let message: String

        /// The message's creation date.
        let startTime = Date()

        /// The message's expiration date.
        ///
        /// The property is `private` so the app can maintain a single timer state.
        /// Only the `TimedMessageList` type can add time extensions.
        fileprivate(set) var endTime: Date?

        init(_ string: String) {
            message = string
        }

        /// Returns a Boolean that indicates whether the message's expiration
        /// date is in the past.
        func hasExpired() -> Bool {
            guard let endTime else {
                return false
            }
            return Date() >= endTime
        }
    }

    /// The list's next message in its queue.
    var activeMessage: Message? = nil

    /// An ordered list of the messages in the list.
    private var messages = [Message]() {
        didSet {
            if activeMessage?.message != messages.first?.message {
                activeMessage = messages.first
            }
        }
    }

    /// A cancellable task the message list schedules to fire at the time when the
    /// message with the nearest expiration date (in the future) expires.
    ///
    /// Replaces a selector-based `Timer`: `@MainActor` isolation already guarantees
    /// main-actor execution at compile time, so the old `dispatchPrecondition` runtime
    /// checks throughout this file are redundant and have been removed. See CODE_AUDIT §3.5.
    private var expirationTask: Task<Void, Never>?

    private let feedbackMessageMinimumDurationSecs: Double = 2.0

    /// Creates a new message from a string and adds it to the list.
    /// - Parameter string: The text of a message.
    func add(_ msg: String) {
        if let index = messages.lastIndex(where: { $0.message == msg }) {
            messages[index].endTime = nil
        } else {
            messages.append(Message(msg))
        }
        scheduleExpiration()
    }

    /// Removes the message with the given string.
    /// - Parameter msg: A string to display for the message
    func remove(_ msg: String) {
        guard let index = messages.lastIndex(where: { $0.message == msg }) else { return }
        var endTime = Date()
        let earliestAcceptableEndTime = messages[index].startTime + feedbackMessageMinimumDurationSecs
        if endTime < earliestAcceptableEndTime {
            endTime = earliestAcceptableEndTime
        }
        messages[index].endTime = endTime
        scheduleExpiration()
    }

    /// Schedules a task to fire when the message with the nearest expiration
    /// date (in the future) expires. Cancels and replaces any in-flight task, so a
    /// superseding `add`/`remove` call always reschedules cleanly.
    private func scheduleExpiration() {
        expirationTask?.cancel()
        expirationTask = nil

        // Removes expired messages.
        cullExpired()

        // Finds the next expiration time in the future.
        guard let nearestEndTime = (messages.compactMap { $0.endTime }).min() else { return }

        let duration = nearestEndTime.timeIntervalSinceNow
        expirationTask = delayedTask(.seconds(max(duration, 0))) { [weak self] in
            self?.handleExpiration()
        }
    }

    private func cullExpired() {
        messages.removeAll(where: { $0.hasExpired() })
    }

    private func handleExpiration() {
        expirationTask?.cancel()
        expirationTask = nil
        cullExpired()
        scheduleExpiration()
    }
}

#endif
