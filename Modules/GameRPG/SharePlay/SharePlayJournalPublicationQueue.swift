// @copyright André Trettin

import CoreRPG
import Foundation

/// Serializes publications for one journal slot without putting removal of the
/// previous attachment on the publication's critical path.
///
/// `GroupSessionJournal.remove(attachment:)` can remain suspended while a peer
/// finishes transferring the attachment. Waiting for that removal before adding
/// the replacement prevents every later item in the same module from being sent.
/// This queue commits the replacement first and performs old-attachment cleanup
/// in a separate session-scoped task.
@MainActor
final class SharePlayJournalPublicationQueue<Attachment: Identifiable & Sendable>
where Attachment.ID == UUID {
    private var publicationTasks: [NetworkModules: (id: UUID, task: Task<Void, Never>)] = [:]
    private var allPublicationTasks: [UUID: Task<Void, Never>] = [:]
    private var cleanupTasks: [UUID: Task<Void, Never>] = [:]
    private var currentAttachments: [NetworkModules: Attachment] = [:]
    private var generation: UInt = 0

    @discardableResult
    func enqueue(
        for module: NetworkModules,
        priority: TaskPriority? = nil,
        publish: @escaping @MainActor () async -> Attachment?,
        remove: @escaping @MainActor (Attachment) async -> Void
    ) -> Task<Void, Never> {
        let id = UUID()
        let operationGeneration = generation
        let previousTask = publicationTasks[module]?.task
        let task = Task(priority: priority) { [weak self] in
            if let previousTask {
                await previousTask.value
            }
            guard let self,
                  !Task.isCancelled,
                  self.generation == operationGeneration
            else {
                self?.finishPublication(id: id, module: module)
                return
            }
            guard let newAttachment = await publish(),
                  !Task.isCancelled,
                  self.generation == operationGeneration
            else {
                self.finishPublication(id: id, module: module)
                return
            }

            let oldAttachment = self.currentAttachments.updateValue(newAttachment, forKey: module)
            if let oldAttachment, oldAttachment.id != newAttachment.id {
                self.scheduleCleanup(
                    oldAttachment,
                    priority: priority,
                    remove: remove
                )
            }
            self.finishPublication(id: id, module: module)
        }
        publicationTasks[module] = (id, task)
        allPublicationTasks[id] = task
        return task
    }

    func currentAttachment(for module: NetworkModules) -> Attachment? {
        currentAttachments[module]
    }

    func cancelAll() {
        generation &+= 1
        allPublicationTasks.values.forEach { $0.cancel() }
        cleanupTasks.values.forEach { $0.cancel() }
        publicationTasks = [:]
        allPublicationTasks = [:]
        cleanupTasks = [:]
        currentAttachments = [:]
    }

    private func scheduleCleanup(
        _ attachment: Attachment,
        priority: TaskPriority?,
        remove: @escaping @MainActor (Attachment) async -> Void
    ) {
        let id = UUID()
        let task = Task(priority: priority) { [weak self] in
            await remove(attachment)
            self?.cleanupTasks.removeValue(forKey: id)
        }
        cleanupTasks[id] = task
    }

    private func finishPublication(id: UUID, module: NetworkModules) {
        allPublicationTasks[id] = nil
        if publicationTasks[module]?.id == id {
            publicationTasks[module] = nil
        }
    }
}
