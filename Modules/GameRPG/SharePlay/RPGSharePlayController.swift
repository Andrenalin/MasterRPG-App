// @copyright André Trettin

import AudioRPG
import AVFoundation
import CoreRPG
import Combine
import Foundation
@preconcurrency import GroupActivities
import os.log
import SwiftUI

#if os(visionOS)
import TabletopKit
#endif

@MainActor
protocol SharePlayControllerDelegate: AnyObject {
    func handleUpdate(_ model: GameNetworkModel, id: UUID) -> Void
    func handleFileUpdate(_ model: GameNetworkModel) -> Void
    func sharePlayLostPlayer(id: UUID)
    /// Called when the local SharePlay session is invalidated so the player
    /// controller can reset `hasSendPlayer` and mark the master as lost.
    func sharePlayLostConnection()
    /// Called each time a session is fully configured and joined. On a player
    /// device this triggers `ready()` → `sendCharacter()` so the player
    /// re-announces itself to the master after an automatic re-join.
    func sharePlaySessionConfigured()
}

@MainActor
enum RPGSharePlay {
    static let store = RPGSharePlayController()
}

@MainActor @Observable
final class RPGSharePlayController {
    var groupSession: GroupSession<RPGActivity>?
    var isActive: Bool = false
    var canActivateSharePlay: Bool = false
    var stateText: String = "Not Active"

    var gameModel: GameRootModel?
    var packageSender: SharePlaySingleQueuePackageSender?
    var packageReceiver = SharePlayPackageReceiver()

    // Kept alive through session resets so the player can re-join automatically
    // when SharePlay becomes available again for a running game. Only cancelled
    // by stopJoin() when the game itself ends.
    private var joinTask: Task<Void, Never>?

    #if os(visionOS)
    private var systemCoordinator: SystemCoordinator?
    #endif

    private let groupStateObserver = GroupStateObserver()

    private var messenger: GroupSessionMessenger?
    // Session-scoped tasks (state/participant/message/journal loops and in-flight
    // sends), cancelled by reset(). Send tasks remove themselves on completion so
    // the collection stays bounded during a long game.
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var journal: GroupSessionJournal?

    // Lifetime observers — survive session resets; re-created if setup() runs again.
    private var eligibilityTask: Task<Void, Never>?
    #if os(visionOS)
    private var modeChangeTask: Task<Void, Never>?
    #endif

    weak var delegate: SharePlayControllerDelegate?
    weak var playBack: AVPlaybackCoordinator?
    weak var audioCoordinator: AudioListenerCoordinator?

#if os(visionOS)
    weak var tabletopGame: TabletopGame?
#endif

    init() {
        Logger.sharePlay.debug("SharePlay: init")
    }

    deinit {
        // Swift 6: deinit is nonisolated and cannot access @MainActor-isolated `tasks`.
        // Cleanup is handled by reset(), which must be called before releasing this controller.
        Logger.sharePlay.debug("SharePlay: deinit")
    }

    func setup(gameModel: GameRootModel) {
        Logger.sharePlay.debug("SharePlay: setup")
        self.gameModel = gameModel
        packageSender = SharePlaySingleQueuePackageSender { [weak self] package in
            await self?.sendPackage(package)
        }

        eligibilityTask?.cancel()
        eligibilityTask = Task { [weak self] in
            guard let observer = self?.groupStateObserver else { return }
            for await value in observer.$isEligibleForGroupSession.values {
                guard let self else { return }
                self.canActivateSharePlay = value
            }
        }

        #if os(visionOS)
        // Observe presentation mode changes and apply configuration
        modeChangeTask?.cancel()
        modeChangeTask = Task { [weak self] in
            for await newMode in gameModel.shareState.modeChanged.values {
                guard let self else { return }
                Logger.sharePlay.debug("Presentation mode changed to: \(newMode.rawValue, privacy: .public)")

                // Apply the new spatial template configuration
                self.applyShareState()
            }
        }
        #endif
    }

    func setup(audioCoordinator: AudioListenerCoordinator?) {
        self.audioCoordinator = audioCoordinator
        self.playBack = audioCoordinator?.playbackCoordinator
        guard let groupSession else { return }
        playBack?.coordinateWithSession(groupSession)
    }

    #if os(visionOS)
    func setup(tabletopGame: TabletopGame, gameTableModel: GameTableModel? = nil) {
        self.tabletopGame = tabletopGame
        guard let groupSession else { return }
        tabletopGame.coordinateWithSession(groupSession)

        if let gameTableModel = gameTableModel {
            setupSeatAssignment(gameTableModel: gameTableModel)
        }
    }
    #endif
}

extension RPGSharePlayController {
    func sendData(_ gameNetworkModel: GameNetworkModel, fileJournal: Bool) {
        Logger.sharePlay.debug("sendData state: \(self.printState(), privacy: .public) model: \(gameNetworkModel.debugDescription, privacy: .public)")
        guard let encodedModel = gameNetworkModel.encodeData() else { return }
        guard messenger != nil else { return }

        if let attachmentData = gameNetworkModel.data.data, let journal, fileJournal {
            Logger.sharePlay.debug("Journal: \(self.printState(), privacy: .public) model: \(gameNetworkModel.debugDescription, privacy: .public)")
            addSendTask(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                if let oldAttachment = self.gameModel?.attachments[gameNetworkModel.data.type] {
                    do {
                        try await journal.remove(attachment: oldAttachment)
                    } catch {
                        Logger.sharePlay.error("Cannot remove old attachment from Journal with module \(gameNetworkModel.data.type.token, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
                    }
                }
                let model = Self.journalMetadata(for: gameNetworkModel)
                do {
                    let result = try await journal.add(attachmentData, metadata: model)
                    self.gameModel?.attachments[gameNetworkModel.data.type] = result
                    Logger.sharePlay.debug("Journal: \(result.id, privacy: .public)")
                } catch {
                    Logger.sharePlay.error("Cannot add attachment for module \(gameNetworkModel.data.type.token, privacy: .public) and id: \(gameNetworkModel.data.id, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        // Keep the package path as a compatibility fallback for V1 peers. Current
        // peers deduplicate it against the journal delivery by message key.
        addSendTask { [weak self] in
            guard let self, let sender = self.packageSender else { return }
            await sender.send(data: encodedModel)
        }
    }

    static func journalMetadata(for model: GameNetworkModel) -> GameNetworkModel {
        var metadata = model
        if metadata.data.type == .audio, metadata.targetId != nil {
            // GroupSessionJournal attachments are visible to the whole session.
            // Store the audio on every participant without treating a repair as
            // a new reveal; proxy hosts then forward the same store downstream.
            metadata.type = .store
            metadata.subType = .show
            metadata.targetId = nil
        }
        metadata.data = NetworkCodableDataType(
            id: model.data.id,
            type: model.data.type,
            version: model.data.version,
            data: nil
        )
        return metadata
    }

    /// Runs a send operation as a session-scoped task that is cancellable by
    /// reset() but removes itself when finished, so `tasks` stays bounded.
    private func addSendTask(priority: TaskPriority? = nil, _ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        tasks[id] = Task(priority: priority) { [weak self] in
            await operation()
            self?.tasks.removeValue(forKey: id)
        }
    }

    /// Registers a session-scoped task that reset() cancels. Passing a stable
    /// key replaces (and cancels) the previous task for that key, so repeated
    /// registrations don't accumulate duplicate observers.
    func trackSessionTask(_ task: Task<Void, Never>, key: UUID = UUID()) {
        tasks[key]?.cancel()
        tasks[key] = task
    }

    private func sendPackage(_ package: PackageMessage) async {
        if let messenger {
            try? await messenger.send(package)
        }
    }

    func reset() {
        Logger.sharePlay.debug("SharePlay: reset state: \(self.printState(), privacy: .public)")
        isActive = false
        messenger = nil
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        if groupSession != nil {
            groupSession?.leave()
            groupSession = nil
        }
        #if os(visionOS)
        tabletopGame?.detachNetworkCoordinator()
        systemCoordinator = nil
        gameModel?.shareState.isSharePlayActive = false
        gameModel?.shareState.groupImmersionActive = false
        #endif
    }

    func startSharing(with name: String?, image: AKImage?) {
        Logger.sharePlay.debug("Start Sharing state: \(self.printState(), privacy: .public)")
        #if os(macOS)
            if let image {
                var imageRect = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
                let imageRef = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
                RPGActivity.titleImage = imageRef
            }
        #else
            RPGActivity.titleImage = image?.cgImage
        #endif
        let activity = RPGActivity(adventureTitle: name ?? "Adventure")
        if let groupSession {
            Logger.sharePlay.debug("GroupSession active state: \(self.printState(), privacy: .public)")
            groupSession.activity = activity
        } else {
            Task {
                do {
                    _ = try await activity.activate()
                    Logger.sharePlay.debug("Activate state: \(self.printState(), privacy: .public)")
                } catch {
                    Logger.sharePlay.error("Activate error \(error.localizedDescription) state: \(self.printState(), privacy: .public)")
                }
            }
        }
    }

    func joinGame() {
        Logger.sharePlay.debug("Join state: \(self.printState(), privacy: .public)")
        joinTask?.cancel()
        // Store in joinTask (not tasks) so reset() does not cancel it.
        // The for-await loop stays alive across session invalidations and picks
        // up the next session automatically when the player re-joins the call.
        joinTask = Task { [weak self] in
            for await session in RPGActivity.sessions() {
                guard let self else { return }
                Logger.sharePlay.debug("Session \(session.description, privacy: .public) state: \(self.printState(), privacy: .public)")

                #if os(visionOS)
                await self.configureSystemCoordinator(for: session)
                #endif
                self.configureGroupSession(session)
            }
        }
    }

    func stopJoin() {
        Logger.sharePlay.debug("SharePlay: stopJoin")
        joinTask?.cancel()
        joinTask = nil
    }

    func configureGroupSession(_ groupSession: GroupSession<RPGActivity>) {
        Logger.sharePlay.debug("Configure Session \(groupSession.description, privacy: .public) state: \(self.printState(), privacy: .public)")

        self.groupSession = groupSession
        let messenger = GroupSessionMessenger(session: groupSession)
        self.messenger = messenger
        let journal = GroupSessionJournal(session: groupSession)
        self.journal = journal

        isActive = true
        #if os(visionOS)
        gameModel?.shareState.isSharePlayActive = true
        #endif
        let stateTask = Task { [weak self] in
            for await state in groupSession.$state.values {
                guard let self else { return }
                let stateDescription = self.printState()
                Logger.sharePlay.debug("Session state: \(stateDescription, privacy: .public)")
                self.stateText = stateDescription
                if case .invalidated = state {
                    self.groupSession = nil
                    self.reset()
                    // Notify the player controller so it resets hasSendPlayer
                    // and marks the master as lost — required for re-sync on rejoin.
                    self.delegate?.sharePlayLostConnection()
                    return
                }
            }
        }
        tasks[UUID()] = stateTask

        // Combine's .receive(on:) introduces an async hop that lets the @Published property
        // update before the sink runs — so groupSession.activeParticipants equals activeParticipants
        // by the time the closure fires, making the subtracting() always empty.
        // Apple's recommended approach (WWDC visionOS SharePlay sample) is to use
        // `for await .values` with an explicit previousParticipants local that is updated
        // via defer, which is unambiguous regardless of scheduling.
        let participantTask = Task { [weak self] in
            guard let self else { return }
            var previousParticipants = Set<Participant>()
            for await activeParticipants in groupSession.$activeParticipants.values {
                let removed = previousParticipants.subtracting(activeParticipants)
                let added = activeParticipants.subtracting(previousParticipants)
                defer { previousParticipants = activeParticipants }
                Logger.sharePlay.debug("Session Participants active: \(activeParticipants.debugDescription, privacy: .public) added: \(added.debugDescription, privacy: .public) removed: \(removed.debugDescription, privacy: .public)")
                for participant in removed {
                    self.delegate?.sharePlayLostPlayer(id: participant.id)
                }
            }
        }
        tasks[UUID()] = participantTask

        let messageTask = Task { [weak self] in
            for await (message, context) in messenger.messages(of: PackageMessage.self) {
                guard let self else { return }
                Logger.sharePlay.debug("Received Update Message \(message.uuid, privacy: .public): \(message.count, privacy: .public) - \(message.total, privacy: .public) from \(context.source.id, privacy: .public)")
                if let data = self.packageReceiver.received(package: message)?.data,
                    let gameModel = GameNetworkModel.decodeData(of: data) {
                    self.delegate?.handleUpdate(gameModel, id: context.source.id)
                }
            }
        }
        tasks[UUID()] = messageTask
        let journalTask = Task { [weak self] in
            for await attachment in journal.attachments {
                guard let self else { return }
                await self.handle(attachment)
            }
        }
        tasks[UUID()] = journalTask

        // join() must not run on the main thread while an audio session is active
        // (AVFoundation SessionCore warning), so hop to a detached task.
        Task.detached { [groupSession] in
            groupSession.join()
        }
        playBack?.coordinateWithSession(groupSession)
        // Notify delegate so player re-sends character data and triggers a full
        // game-state sync. Safe to call on first join too: on master the guard
        // in NetworkController.sharePlaySessionConfigured() is a no-op.
        delegate?.sharePlaySessionConfigured()
        #if os(visionOS)
        tabletopGame?.coordinateWithSession(groupSession)

        if tabletopGame != nil {
            if let gameTableModel = gameModel?.gameTableModel {
                setupSeatAssignment(gameTableModel: gameTableModel)
            } else {
                Logger.sharePlay.debug("GameTableModel not available at session configure time — seats assigned later")
            }
        }
        #endif
    }

    func handle(_ attachments: GroupSessionJournal.Attachments.Element) async {
        for attachment in attachments {
            do {
                var metadata = try await attachment.loadMetadata(of: GameNetworkModel.self)
                // journal.attachments emits the FULL current set on every change.
                // Skip attachments we already loaded by comparing attachment.id (the
                // journal's own system UUID, not the game item UUID). This prevents
                // GroupKit's NSCocoaErrorDomain 260 when it cleans up temp files for
                // already-transferred attachments.
                // Using attachment.id instead of game item UUID means remove+re-add
                // (journal.add always produces a new attachment.id) correctly re-sends
                // the same item to newly joined participants.
                if gameModel?.attachments[metadata.data.type]?.id == attachment.id { continue }
                Logger.sharePlay.debug("Attachments \(metadata.counter, privacy: .public)")
                do {
                    let data = try await attachment.load(Data.self)
                    metadata.data = NetworkCodableDataType(id: metadata.data.id, type: metadata.data.type, version: metadata.data.version, data: data)
                    gameModel?.attachments[metadata.data.type] = attachment
                    gameModel?.metaDataAttachments[metadata.data.type] = metadata.data.id
                    delegate?.handleFileUpdate(metadata)
                } catch let error {
                    Logger.sharePlay.error("Exception in load attachment data \(error.localizedDescription, privacy: .public)")
                    // The load fails when the master replaced the attachment while
                    // this participant was still transferring it. Deliver the
                    // data-less metadata anyway: a reveal without data makes the
                    // player controller request the payload again from the master,
                    // instead of silently missing it while everyone else has it.
                    delegate?.handleFileUpdate(metadata)
                }
            } catch let error {
                Logger.sharePlay.error("Exception in load attachment metaData \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

private extension RPGSharePlayController {
    func printState() -> String {
        guard let groupSession else {
            return "Not Active"
        }
        return "\(groupSession.state)"
    }
}

#if os(visionOS)
extension RPGSharePlayController {
    private func configureSystemCoordinator(for session: GroupSession<RPGActivity>) async {
        guard let coordinator = await session.systemCoordinator else { return }
        systemCoordinator = coordinator
        applyShareState()
        
        let immersionTask = Task { [weak self] in
            for await immersionStyle in coordinator.groupImmersionStyle {
                guard let self else { return }
                self.gameModel?.shareState.groupImmersionActive = immersionStyle != nil
            }
        }
        tasks[UUID()] = immersionTask
    }
    
    func applyShareState() {
        guard let coordinator = systemCoordinator else { return }
        var configuration = SystemCoordinator.Configuration()
        configuration.supportsGroupImmersiveSpace = true
        switch gameModel?.shareState.mode ?? .window {
        case .tabletop:
            configuration.spatialTemplatePreference = .surround.contentExtent(1)
        case .window, .immersive:
            configuration.spatialTemplatePreference = .sideBySide
        }
        coordinator.configuration = configuration
    }
}

#endif
