// @copyright André Trettin

import Foundation
import Observation

/// Owns the data-mutation lock, save deferral and the parse and apply tasks of an import review.
/// See CODE_AUDIT_26 §10.2.
@MainActor @Observable
final class ImportMutationSession {
    /// The hooks a presenter passes in; plain values the view keeps until it creates the session.
    struct Handlers {
        var beginDataMutation: (@MainActor () -> Bool)?
        var endDataMutation: (@MainActor () async -> Void)?
        var beginSaveDeferral: (@MainActor () -> UUID)?
        var endSaveDeferral: (@MainActor (UUID) -> Void)?
    }

    private let beginDataMutationHandler: (@MainActor () -> Bool)?
    private let endDataMutationHandler: (@MainActor () async -> Void)?
    private let beginSaveDeferral: (@MainActor () -> UUID)?
    private let endSaveDeferral: (@MainActor (UUID) -> Void)?

    private(set) var isActive = false

    var canStartImport: Bool { importTask == nil }

    @ObservationIgnored private var coordinatorToken: UUID?
    /// Held by the session, not the presenting view: release runs from a task that can outlive
    /// the view, and reading the view's `@State` after teardown is not supported.
    /// See CODE_AUDIT_Folder §3.16.
    @ObservationIgnored private var saveDeferralToken: UUID?
    @ObservationIgnored private var importTask: Task<Void, any Error>?
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?

    init(handlers: Handlers) {
        self.beginDataMutationHandler = handlers.beginDataMutation
        self.endDataMutationHandler = handlers.endDataMutation
        self.beginSaveDeferral = handlers.beginSaveDeferral
        self.endSaveDeferral = handlers.endSaveDeferral
    }

    func beginDataMutation() -> Bool {
        guard !isActive else { return true }

        if let beginDataMutationHandler {
            guard beginDataMutationHandler() else { return false }
        } else {
            guard let token = DataMutationCoordinator.shared.begin() else { return false }
            coordinatorToken = token
        }

        isActive = true
        if saveDeferralToken == nil {
            saveDeferralToken = beginSaveDeferral?()
        }
        return true
    }

    /// Runs the review apply as a task the session owns, so `release` waits for it before the
    /// final save and lock release. See CODE_AUDIT_Folder §3.17.
    func runApply(_ work: @escaping @MainActor () async -> Void) async {
        let task = Task { @MainActor in
            await work()
        }
        applyTask = task
        await task.value
        applyTask = nil
    }

    /// Retains the parser task so every exit path can wait until parsing has stopped mutating data.
    func trackImportTask(_ task: Task<Void, any Error>) -> Bool {
        guard importTask == nil else { return false }
        importTask = task
        return true
    }

    func release(cancelImport: Bool) async {
        if cancelImport {
            importTask?.cancel()
        }

        if let cleanupTask {
            await cleanupTask.value
            return
        }

        guard isActive else { return }

        let parserTask = importTask
        let applyTask = applyTask
        let task = Task { @MainActor [self] in
            _ = await parserTask?.result
            await applyTask?.value
            await self.finishRelease()
        }
        cleanupTask = task
        await task.value
        cleanupTask = nil
    }

    /// SwiftUI disappearance callbacks cannot await. This task deliberately retains the session
    /// until parser cancellation, the final save, and lock release have all completed.
    func cancelImportAndReleaseInBackground() {
        importTask?.cancel()
        guard isActive, cleanupTask == nil else { return }

        Task { @MainActor [self] in
            await self.release(cancelImport: true)
        }
    }

    private func finishRelease() async {
        guard isActive else { return }

        if let saveDeferralToken {
            endSaveDeferral?(saveDeferralToken)
            self.saveDeferralToken = nil
        }
        await endDataMutationHandler?()

        if let coordinatorToken {
            DataMutationCoordinator.shared.end(coordinatorToken)
            self.coordinatorToken = nil
        }

        importTask = nil
        isActive = false
    }
}
