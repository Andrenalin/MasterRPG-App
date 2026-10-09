// @copyright André Trettin

import SwiftUI

/// Asks the user what happens to the file an item already has before a new file replaces it:
/// delete it, leave it on disk, or cancel the replacement.
///
/// A view that lets the user pick a new file owns one (`@State`), shows its alert with
/// `fileReplacementAlert(_:)` and replaces the file through it. Nothing is asked when the
/// replacement deletes no stored file (`EditControllable.storedFileDeletedByReplacement`).
@MainActor @Observable
public final class FileReplacementConfirmation {
    /// One question to the user. The alert's buttons hold it, so an answer reaches the waiting
    /// replacement also when the alert's binding was cleared first.
    @MainActor
    public final class Request: Identifiable {
        /// The name of the file that is replaced.
        public let fileName: String
        private var continuation: CheckedContinuation<ReplacedFileDisposal?, Never>?

        fileprivate init(fileName: String, continuation: CheckedContinuation<ReplacedFileDisposal?, Never>) {
            self.fileName = fileName
            self.continuation = continuation
        }

        // A question nobody answered counts as cancelled; its replacement must not wait forever.
        isolated deinit {
            continuation?.resume(returning: nil)
        }

        fileprivate func answer(_ disposal: ReplacedFileDisposal?) {
            continuation?.resume(returning: disposal)
            continuation = nil
        }
    }

    public init() {}

    /// The question the alert shows; `nil` while nothing is asked.
    public private(set) var request: Request?

    /// What happens to the file that the new file of `itemId` replaces, or `nil` when the user
    /// cancelled and the item keeps its file. Asks only when the replacement would delete a
    /// stored file; otherwise there is nothing to decide and the result is `.delete`.
    /// - Parameter url: The new file, or `nil` when it is written from data.
    public func disposal(
        forReplacingFileOf itemId: UUID,
        with url: URL? = nil,
        editControllable: any EditControllable
    ) async -> ReplacedFileDisposal? {
        guard let replacedFileUrl = await editControllable.storedFileDeletedByReplacement(itemId: itemId, url: url) else {
            return .delete
        }
        // One question at a time: a newer replacement supersedes the one still asked.
        request?.answer(nil)
        return await withCheckedContinuation { continuation in
            request = Request(fileName: replacedFileUrl.rawUrl.lastPathComponent, continuation: continuation)
        }
    }

    /// Replaces the file of `itemId` with the file at `url`, after asking what happens to the
    /// file it replaces. Returns whether the item has the new file afterwards; `false` also
    /// when the user cancelled.
    @discardableResult
    public func resetFile(url: URL, itemId: UUID, editControllable: any EditControllable) async -> Bool {
        guard let replaced = await disposal(forReplacingFileOf: itemId, with: url, editControllable: editControllable) else {
            return false
        }
        return await editControllable.resetFile(url: url, itemId: itemId, replaced: replaced)
    }

    /// The user's answer to `request`; `nil` cancels the replacement.
    func answer(_ request: Request, with disposal: ReplacedFileDisposal?) {
        request.answer(disposal)
        if self.request === request {
            self.request = nil
        }
    }

    /// The alert was dismissed. Its button answers the question, before or after this.
    func dismissed() {
        request = nil
    }

    /// The view showing the alert went away: the question can no longer be answered.
    func cancel() {
        request?.answer(nil)
        request = nil
    }
}

public extension View {
    /// Shows the question of `confirmation`. Attach it inside the presentation the user picks
    /// the new file in: an alert below a sheet that is still open is not shown.
    func fileReplacementAlert(_ confirmation: FileReplacementConfirmation) -> some View {
        modifier(FileReplacementAlertModifier(confirmation: confirmation))
    }
}

private struct FileReplacementAlertModifier: ViewModifier {
    let confirmation: FileReplacementConfirmation

    func body(content: Content) -> some View {
        content
            .alert(
                Text("Replace File?", bundle: .module),
                isPresented: Binding {
                    confirmation.request != nil
                } set: { isPresented in
                    if !isPresented { confirmation.dismissed() }
                },
                presenting: confirmation.request
            ) { request in
                Button(role: .cancel) {
                    confirmation.answer(request, with: nil)
                } label: {
                    Text("Cancel", bundle: .module)
                }
                Button(role: .destructive) {
                    confirmation.answer(request, with: .delete)
                } label: {
                    Text("Delete File", bundle: .module)
                }
                Button {
                    confirmation.answer(request, with: .keep)
                } label: {
                    Text("Leave on Disk", bundle: .module)
                }
#if !os(tvOS)
                .keyboardShortcut(.defaultAction)
#endif
            } message: { request in
                Text("The new file replaces “\(request.fileName)”. Delete the previous file or leave it on disk?", bundle: .module)
            }
            .onDisappear {
                confirmation.cancel()
            }
    }
}
