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

/// What this device uploaded to the SharePlay Journal, one slot per module (and one for audio playlists), and which Journal
/// attachments it already handed to the game.
///
/// The upload rule is the whole file-repair policy for SharePlay:
/// - Another item or version than the slot holds is uploaded.
/// - The same item and version is never uploaded twice for one show: the counter of the show
///   has to be newer than the one the upload answered.
/// - For a newer show it is uploaded again only when the last upload is older than
///   `reuploadInterval`. This repairs the rare participant whose download never finished: the
///   game master shows the item again after a minute. A request alone never uploads again.
/// - That holds after another item took the slot: the Journal keeps one attachment per module,
///   so two items shown one after the other (an audio playlist and its first track) replace each
///   other. A request for the show of the item that was pushed out is not answered with an
///   upload: it would push the other one out in turn, and the two would take the slot from each
///   other for good while every player's download is cancelled again and again.
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

    /// What a publication is about: an item in one version.
    private struct Key: Hashable, Sendable {
        let slot: SharePlayJournalSlot
        let itemId: UUID
        let version: Int
    }

    /// How many pushed-out uploads are remembered; the oldest show is forgotten first.
    private static let displacedLimit = 16

    private var publications: [SharePlayJournalSlot: Publication] = [:]
    /// The latest upload of every item that another item pushed out of its module's slot.
    private var displaced: [Key: Publication] = [:]
    private var processedAttachmentIds: Set<UUID> = []

    func publication(for module: NetworkModules, isPlaylist: Bool = false) -> Publication? {
        publications[SharePlayJournalSlot(module, isPlaylist: isPlaylist)]
    }

    func shouldUpload(
        module: NetworkModules,
        isPlaylist: Bool = false,
        itemId: UUID,
        version: Int,
        counter: Int,
        now: ContinuousClock.Instant = .now
    ) -> Bool {
        let slot = SharePlayJournalSlot(module, isPlaylist: isPlaylist)
        guard let publication = publications[slot],
              publication.itemId == itemId,
              publication.version == version
        else {
            // Not in the slot: new, or pushed out by another item. A show that was uploaded
            // before is not uploaded again for a request.
            guard let pushedOut = displaced[Key(slot: slot, itemId: itemId, version: version)] else { return true }
            return counter > pushedOut.counter
        }
        guard counter > publication.counter else { return false }
        return publication.uploadedAt.duration(to: now) > Self.reuploadInterval
    }

    /// Reserves the slot when the upload is queued, so a second request for the same show that
    /// arrives while the bytes are still on their way does not start another upload.
    mutating func willUpload(
        module: NetworkModules,
        isPlaylist: Bool = false,
        itemId: UUID,
        version: Int,
        counter: Int,
        now: ContinuousClock.Instant = .now
    ) {
        let slot = SharePlayJournalSlot(module, isPlaylist: isPlaylist)
        if let current = publications[slot],
           current.itemId != itemId || current.version != version {
            displaced[Key(slot: slot, itemId: current.itemId, version: current.version)] = current
            if displaced.count > Self.displacedLimit,
               let oldest = displaced.min(by: { $0.value.counter < $1.value.counter }) {
                displaced[oldest.key] = nil
            }
        }
        displaced[Key(slot: slot, itemId: itemId, version: version)] = nil
        publications[slot] = Publication(
            attachmentId: nil,
            itemId: itemId,
            version: version,
            counter: counter,
            uploadedAt: now
        )
    }

    mutating func didUpload(module: NetworkModules, isPlaylist: Bool = false, itemId: UUID, version: Int, counter: Int, attachmentId: UUID) {
        let slot = SharePlayJournalSlot(module, isPlaylist: isPlaylist)
        processedAttachmentIds.insert(attachmentId)
        guard var publication = publications[slot],
              publication.itemId == itemId,
              publication.version == version,
              publication.counter == counter
        else { return }
        publication.attachmentId = attachmentId
        publications[slot] = publication
    }

    /// Frees the slot of an upload that did not reach the Journal, so the next request or show
    /// can try again.
    mutating func uploadFailed(module: NetworkModules, isPlaylist: Bool = false, itemId: UUID, version: Int, counter: Int) {
        let slot = SharePlayJournalSlot(module, isPlaylist: isPlaylist)
        guard let publication = publications[slot],
              publication.attachmentId == nil,
              publication.itemId == itemId,
              publication.version == version,
              publication.counter == counter
        else { return }
        publications[slot] = nil
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
        displaced = [:]
        processedAttachmentIds = []
    }
}
