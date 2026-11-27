// @copyright André Trettin

import AudioRPG
import AVFoundation
import CoreRPG
import Foundation
import GroupActivities
import os.log
import SwiftUI

#if os(visionOS)
import TabletopKit
#endif

// The send operation queue and its drain, split out of RPGSharePlayController+ChunkedTransport.swift. See CODE_AUDIT_29 §9.9.

extension RPGSharePlayController {
    /// Bounds work before encoding and preserves the same FIFO order that the
    /// package sender enforces once bytes have been produced.
    ///
    /// All Messenger traffic goes through this one FIFO queue. ACCEPTED OVERHEAD, WON'T FIX
    /// (CODE_AUDIT_Game_Photo_Audio §7.3): a large package delays the messages queued behind it.
    @discardableResult
    func addSendTask(
        byteCount: Int,
        _ operation: @escaping @MainActor () async -> Void
    ) -> Bool {
        let safeByteCount = max(0, byteCount)
        let outstandingCount = pendingSendOperations.count + (activeSendOperation == nil ? 0 : 1)
        guard outstandingCount < SharePlaySingleQueuePackageSender.maxOutstandingMessages,
              safeByteCount <= SharePlayMessengerPayloadBudget.maximumRawPayloadByteCount,
              sendOperationByteCount <=
                SharePlayMessengerPayloadBudget.maximumOutstandingRawPayloadByteCount - safeByteCount
        else { return false }

        pendingSendOperations.append(PendingSendOperation(
            id: UUID(),
            byteCount: safeByteCount,
            operation: operation
        ))
        sendOperationByteCount += safeByteCount
        startSendOperationTaskIfNeeded()
        return true
    }

    func startSendOperationTaskIfNeeded() {
        guard sendOperationTask == nil else { return }
        let generation = sendOperationGeneration
        sendOperationTask = Task { @MainActor [weak self] in
            await self?.drainSendOperations(generation: generation)
        }
    }

    func drainSendOperations(generation: UInt64) async {
        while !Task.isCancelled,
              sendOperationGeneration == generation,
              !pendingSendOperations.isEmpty {
            let pendingOperation = pendingSendOperations.removeFirst()
            activeSendOperation = pendingOperation
            await pendingOperation.operation()
            guard sendOperationGeneration == generation,
                  activeSendOperation?.id == pendingOperation.id
            else { return }
            sendOperationByteCount = max(0, sendOperationByteCount - pendingOperation.byteCount)
            activeSendOperation = nil
            promoteDeferredDeliveries()
        }
        guard sendOperationGeneration == generation else { return }
        activeSendOperation = nil
        sendOperationTask = nil
    }

    /// Sends the deferred messages that are ready, in queue order. Called after every completed
    /// send operation, when a timer for a retry back-off fires and when an entry is deferred.
    ///
    /// A full send queue ends the pass without a timer: a send operation is running, and its
    /// completion calls this again. A timer against a deadline that has already passed fired at
    /// once, promoted, found the queue full and armed the next one, a loop on the main actor for
    /// as long as a large transfer filled the queue (CODE_AUDIT_Game_Shareplay §5.2). A timer is
    /// armed only for the earliest entry that is not ready yet, and an entry that waits for its
    /// back-off no longer holds back the ready ones behind it (§5.17).
    func promoteDeferredDeliveries() {
        deferredDeliveryQueue.removeEntries { [sessionLifecycle] entry in
            !sessionLifecycle.isCurrent(sessionId: entry.sessionId)
        }
        let now = ContinuousClock().now
        while let ready = deferredDeliveryQueue.firstReady(at: now) {
            let delivery = ready.entry
            guard enqueueChunkedSend(
                delivery.model,
                sessionId: delivery.sessionId,
                participantId: delivery.participantId,
                allowDeferral: false,
                deliveryAttempt: delivery.deliveryAttempt
            ) else { return }
            deferredDeliveryQueue.remove(ready.token)
        }
        scheduleDeferredPromotionIfNeeded()
    }

    /// Arms the timer for the earliest deferred entry whose back-off has not passed yet.
    func scheduleDeferredPromotionIfNeeded() {
        let now = ContinuousClock().now
        guard deferredPromotionTask == nil,
              let retryNotBefore = deferredDeliveryQueue.earliestRetry(after: now)
        else { return }
        let generation = sendOperationGeneration
        let delay = now.duration(to: retryNotBefore)
        deferredPromotionTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self,
                  self.sendOperationGeneration == generation
            else { return }
            self.deferredPromotionTask = nil
            self.promoteDeferredDeliveries()
        }
    }

    /// Registers a session-scoped task that reset() cancels. Passing a stable
    /// key replaces (and cancels) the previous task for that key, so repeated
    /// registrations don't accumulate duplicate observers.
    func trackSessionTask(_ task: Task<Void, Never>, key: UUID = UUID()) {
        tasks[key]?.cancel()
        tasks[key] = task
    }
}
