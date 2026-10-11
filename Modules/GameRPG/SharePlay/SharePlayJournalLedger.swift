// @copyright André Trettin

import CoreRPG
import Foundation

/// What `RPGSharePlayController.publishAsset` did with a package.
enum SharePlayAssetPublication: Equatable, Sendable {
    /// Queued for the Journal.
    case uploading
    /// The Journal already holds this item and version for this show.
    case alreadyPublished
    /// The Journal could not take it; the package was handed to Messenger.
    case sentByMessenger
    /// No session, or neither transport accepted it.
    case unavailable
}

/// What this device uploaded to the SharePlay Journal, one slot per module, and which Journal
/// attachments it already handed to the game.
///
/// The upload rule is the whole file-repair policy for SharePlay:
/// - Another item or version than the slot holds is uploaded.
/// - The same item and version is never uploaded twice for one show: the counter of the show
///   has to be newer than the one the upload answered.
/// - For a newer show it is uploaded again only when the last upload is older than
///   `reuploadInterval`. This repairs the rare participant whose download never finished: the
///   game master shows the item again after a minute. A request alone never uploads again.
struct SharePlayJournalLedger: Sendable {
    static let reuploadInterval: Duration = .seconds(60)

    struct Publication: Equatable, Sendable {
        /// `nil` while the upload is still running.
        var attachmentId: UUID?
        let itemId: UUID
        let version: Int
        /// The counter of the show this upload delivered.
        let counter: Int
        let uploadedAt: ContinuousClock.Instant
    }

    private var publications: [NetworkModules: Publication] = [:]
    private var processedAttachmentIds: Set<UUID> = []

    func publication(for module: NetworkModules) -> Publication? {
        publications[module]
    }

    func shouldUpload(
        module: NetworkModules,
        itemId: UUID,
        version: Int,
        counter: Int,
        now: ContinuousClock.Instant = .now
    ) -> Bool {
        guard let publication = publications[module],
              publication.itemId == itemId,
              publication.version == version
        else { return true }
        guard counter > publication.counter else { return false }
        return publication.uploadedAt.duration(to: now) > Self.reuploadInterval
    }

    /// Reserves the slot when the upload is queued, so a second request for the same show that
    /// arrives while the bytes are still on their way does not start another upload.
    mutating func willUpload(
        module: NetworkModules,
        itemId: UUID,
        version: Int,
        counter: Int,
        now: ContinuousClock.Instant = .now
    ) {
        publications[module] = Publication(
            attachmentId: nil,
            itemId: itemId,
            version: version,
            counter: counter,
            uploadedAt: now
        )
    }

    mutating func didUpload(module: NetworkModules, itemId: UUID, version: Int, counter: Int, attachmentId: UUID) {
        processedAttachmentIds.insert(attachmentId)
        guard var publication = publications[module],
              publication.itemId == itemId,
              publication.version == version,
              publication.counter == counter
        else { return }
        publication.attachmentId = attachmentId
        publications[module] = publication
    }

    /// Frees the slot of an upload that did not reach the Journal, so the next request or show
    /// can try again.
    mutating func uploadFailed(module: NetworkModules, itemId: UUID, version: Int, counter: Int) {
        guard let publication = publications[module],
              publication.attachmentId == nil,
              publication.itemId == itemId,
              publication.version == version,
              publication.counter == counter
        else { return }
        publications[module] = nil
    }

    /// Forgets attachments that left the Journal. `journal.attachments` always reports the full
    /// current set.
    mutating func reconcile(attachmentIds: Set<UUID>) {
        processedAttachmentIds.formIntersection(attachmentIds)
        publications = publications.filter { _, publication in
            guard let attachmentId = publication.attachmentId else { return true }
            return attachmentIds.contains(attachmentId)
        }
    }

    mutating func didRemove(attachmentId: UUID) {
        processedAttachmentIds.remove(attachmentId)
        publications = publications.filter { $0.value.attachmentId != attachmentId }
    }

    /// Whether this attachment has not been handed to the game yet.
    mutating func shouldProcess(attachmentId: UUID) -> Bool {
        processedAttachmentIds.insert(attachmentId).inserted
    }

    mutating func retryProcessing(attachmentId: UUID) {
        processedAttachmentIds.remove(attachmentId)
    }

    mutating func reset() {
        publications = [:]
        processedAttachmentIds = []
    }
}
