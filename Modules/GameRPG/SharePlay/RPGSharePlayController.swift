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

    var gameModel: GameModel?
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
    private var cancellables: Set<AnyCancellable> = []

    private var messenger: GroupSessionMessenger?
    var subscriptions = Set<AnyCancellable>()
    private var tasks = Set<Task<Void, Never>>()
    private var journal: GroupSessionJournal?

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

    func setup(gameModel: GameModel) {
        Logger.sharePlay.debug("SharePlay: setup")
        self.gameModel = gameModel
        packageSender = SharePlaySingleQueuePackageSender { [weak self] package in
            await self?.sendPackage(package)
        }

        groupStateObserver.$isEligibleForGroupSession
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                MainActor.assumeIsolated {
                    self?.canActivateSharePlay = value
                }
            }.store(in: &cancellables)
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
        guard let data = gameNetworkModel.encodeData() else { return }
        guard messenger != nil else { return }

        if let data = gameNetworkModel.data.data, let journal, fileJournal {
            Logger.sharePlay.debug("Journal: \(self.printState(), privacy: .public) model: \(gameNetworkModel.debugDescription, privacy: .public)")
            let journalTask = Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                if let oldAttachment = self.gameModel?.attachments[gameNetworkModel.data.type] {
                    do {
                        try await journal.remove(attachment: oldAttachment)
                    } catch {
                        Logger.sharePlay.error("Cannot remove old attachment from Journal with module \(gameNetworkModel.data.type.token, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
                    }
                }
                var model = gameNetworkModel
                model.data = NetworkCodableDataType(id: gameNetworkModel.data.id, type: gameNetworkModel.data.type, version: gameNetworkModel.data.version, data: nil)
                do {
                    let result = try await journal.add(data, metadata: model)
                    self.gameModel?.attachments[gameNetworkModel.data.type] = result
                    Logger.sharePlay.debug("Journal: \(result.id, privacy: .public)")
                } catch {
                    Logger.sharePlay.error("Cannot add attachment for module \(gameNetworkModel.data.type.token, privacy: .public) and id: \(gameNetworkModel.data.id, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
                }
            }
            tasks.insert(journalTask)
            return
        }
        let sendTask = Task { [weak self] in
            guard let self, let sender = self.packageSender else { return }
            await sender.send(data: data)
        }
        tasks.insert(sendTask)
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
        tasks.forEach { $0.cancel() }
        tasks = []
        subscriptions = []
        if groupSession != nil {
            groupSession?.leave()
            groupSession = nil
        }
        #if os(visionOS)
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
        groupSession.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                MainActor.assumeIsolated {
                    let stateDescription = self.printState()
                    Logger.sharePlay.debug("Session state: \(stateDescription, privacy: .public)")
                    self.stateText = stateDescription
                    if case .invalidated = state {
                        self.groupSession = nil
                        self.reset()
                        // Notify the player controller so it resets hasSendPlayer
                        // and marks the master as lost — required for re-sync on rejoin.
                        self.delegate?.sharePlayLostConnection()
                    }
                }
            }
            .store(in: &subscriptions)

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
        tasks.insert(participantTask)

        let task = Task { [weak self] in
            for await (message, context) in messenger.messages(of: PackageMessage.self) {
                guard let self else { return }
                Logger.sharePlay.debug("Received Update Message \(message.uuid, privacy: .public): \(message.count, privacy: .public) - \(message.total, privacy: .public) from \(context.source.id, privacy: .public)")
                if let data = self.packageReceiver.received(package: message)?.data,
                    let gameModel = GameNetworkModel.decodeData(of: data) {
                    self.delegate?.handleUpdate(gameModel, id: context.source.id)
                }
            }
        }
        tasks.insert(task)
        let journalTask = Task { [weak self] in
            for await attachment in journal.attachments {
                guard let self else { return }
                await self.handle(attachment)
            }
        }
        tasks.insert(journalTask)

        groupSession.join()
        playBack?.coordinateWithSession(groupSession)
        // Notify delegate so player re-sends character data and triggers a full
        // game-state sync. Safe to call on first join too: on master the guard
        // in NetworkController.sharePlaySessionConfigured() is a no-op.
        delegate?.sharePlaySessionConfigured()
        #if os(visionOS)
        tabletopGame?.coordinateWithSession(groupSession)

        if tabletopGame != nil {
            Task {
                if let gameTableModel = self.gameModel?.gameTableModel {
                    self.setupSeatAssignment(gameTableModel: gameTableModel)
                } else {
                    Logger.sharePlay.debug("GameTableModel not available at session configure time — seats assigned later")
                }
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
        tasks.insert(immersionTask)
    }

    func applyShareState() {
        guard let coordinator = systemCoordinator else { return }
        var configuration = SystemCoordinator.Configuration()
        configuration.supportsGroupImmersiveSpace = true
        switch gameModel?.shareState.mode ?? .window {
        case .tabletop:
            configuration.spatialTemplatePreference = .surround.contentExtent(100)
        case .window, .immersive:
            configuration.spatialTemplatePreference = .sideBySide
        }
        coordinator.configuration = configuration
    }
}
#endif
