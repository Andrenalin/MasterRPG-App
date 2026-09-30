// @copyright André Trettin

import CoreData
import Foundation

/// Store setup steps shared by the iCloud and the local persistence controllers, which had
/// identical copies. See CODE_AUDIT_19 §9.20.
extension CoreDataInitModel {
    /// Destroys the damaged store files and loads a fresh store, then hands the container to the
    /// controller's own `setupContext`.
    func recoverStore(setupContext: @escaping @MainActor @Sendable (NSPersistentContainer, CoreDataInitModel) -> Void) {
        guard recoverableError, let url = containerStoreUrl, let container else { return }
        do {
            try container.destroyStoreFiles(at: url)
            let model = self
            container.loadPersistentStores { _, error in
                let newError: CoreDataInitError = if let error = error as NSError? {
                    .creation(message: error.localizedDescription)
                } else {
                    .none
                }
                runOnMainActor {
                    model.error = newError
                    setupContext(container, model)
                }
            }
        } catch {
            self.error = .removeFile(message: error.localizedDescription)
        }
    }

    /// Creates the background context every module saves through. Returns `false` (and sets
    /// nothing) while the store failed to load.
    func installBackgroundContext(from container: NSPersistentContainer) -> Bool {
        guard error == .none else { return false }
        let context = container.newBackgroundContext()
        context.name = "background_context"
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.transactionAuthor = currentActor.rawValue
        context.automaticallyMergesChangesFromParent = true
        self.context = context
        return true
    }
}
