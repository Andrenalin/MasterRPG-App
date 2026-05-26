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
        let joinTask = Task { [weak self] in
            for await session in RPGActivity.sessions() {
                guard let self else { return }
                Logger.sharePlay.debug("Session \(session.description, privacy: .public) state: \(self.printState(), privacy: .public)")

                #if os(visionOS)
                await self.configureSystemCoordinator(for: session)
                #endif
                self.configureGroupSession(session)
            }
        }
        tasks.insert(joinTask)
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
                    }
                }
            }
            .store(in: &subscriptions)

        groupSession.$activeParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activeParticipants in
                guard let self else { return }
                MainActor.assumeIsolated {
                    let newParticipants = activeParticipants.subtracting(groupSession.activeParticipants)
                    let removedParticipants = groupSession.activeParticipants.subtracting(activeParticipants)

                    Logger.sharePlay.debug("Session Participants active: \(activeParticipants.debugDescription, privacy: .public) and new: \(newParticipants.debugDescription, privacy: .public) and removed: \(removedParticipants.debugDescription, privacy: .public)")

                    removedParticipants.forEach {
                        self.delegate?.sharePlayLostPlayer(id: $0.id)
                    }
                }
            }
            .store(in: &subscriptions)

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
                Logger.sharePlay.debug("Attachments \(metadata.counter, privacy: .public)")
                do {
                    let data = try await attachment.load(Data.self)
                    metadata.data = NetworkCodableDataType(id: metadata.data.id, type: metadata.data.type, version: metadata.data.version, data: data)
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
