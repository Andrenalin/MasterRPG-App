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
    
    var switchToImmersive: Bool = false
    
    private let groupStateObserver = GroupStateObserver()
    private var cancellables: Set<AnyCancellable> = []
    
    private var messenger: GroupSessionMessenger?
    private var subscriptions = Set<AnyCancellable>()
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
//#if os(visionOS)
//        tabletopGame?.detachNetworkCoordinator()
//#endif
        Logger.sharePlay.debug("SharePlay: deinit")
    }
    
    func setup(gameModel: GameModel) {
        Logger.sharePlay.debug("SharePlay: setup")
        self.gameModel = gameModel
        packageSender = SharePlaySingleQueuePackageSender { [weak self] package in
            await self?.sendPackage(package)
        }
        
        groupStateObserver.$isEligibleForGroupSession
            .sink { [weak self] in
                self?.canActivateSharePlay = $0
            }.store(in: &cancellables)
    }
    
    func setup(audioCoordinator: AudioListenerCoordinator?) {
        self.audioCoordinator = audioCoordinator
        self.playBack = audioCoordinator?.playbackCoordinator
        guard let groupSession else { return }
        playBack?.coordinateWithSession(groupSession)
    }
    
    #if os(visionOS)
    func setup(tabletopGame: TabletopGame) {
        self.tabletopGame = tabletopGame
        guard let groupSession else { return }
        tabletopGame.coordinateWithSession(groupSession)
    }
    #endif
}

extension RPGSharePlayController {
    func sendData(_ gameNetworkModel: GameNetworkModel, fileJournal: Bool) {
        Logger.sharePlay.debug("sendData state: \(self.printState(), privacy: .public) model: \(gameNetworkModel.debugDescription, privacy: .public)")
        guard let data = gameNetworkModel.encodeData() else { return }
        guard messenger != nil else { return }

        if let data = gameNetworkModel.data.data, let journal, fileJournal  {
            Logger.sharePlay.debug("Journal: \(self.printState(), privacy: .public) model: \(gameNetworkModel.debugDescription, privacy: .public)")
            Task(priority: .userInitiated) {
                if let oldAttachment = gameModel?.attachments[gameNetworkModel.data.type] {
                    do {
                        try await journal.remove(attachment: oldAttachment)
                    } catch let error {
                        Logger.sharePlay.error("Cannot remove old attachment from Journal with module \(gameNetworkModel.data.type.token, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
                    }
                }
                var model = gameNetworkModel
                model.data = NetworkCodableDataType(id: gameNetworkModel.data.id, type: gameNetworkModel.data.type, version: gameNetworkModel.data.version, data: nil)
                do {
                    let result = try await journal.add(data, metadata: model)
                    gameModel?.attachments[gameNetworkModel.data.type] = result
                    Logger.sharePlay.debug("Journal: \(result.id, privacy: .public)")
                } catch let error {
                    Logger.sharePlay.error("Cannot add attachment for module \(gameNetworkModel.data.type.token, privacy: .public) and id: \(gameNetworkModel.data.id, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
                }
            }
            return
        }
        Task {
            await packageSender?.send(data: data)
        }
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
            Task { @MainActor in
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
        Task {
            for await session in RPGActivity.sessions() {
                Logger.sharePlay.debug("Session \(session.description, privacy: .public) state: \(self.printState(), privacy: .public)")

                #if os(visionOS)
                if let coordinator = await session.systemCoordinator {
                    var configuration = SystemCoordinator.Configuration()
                    configuration.spatialTemplatePreference = .surround.contentExtent(100)
                    configuration.supportsGroupImmersiveSpace = true
                    coordinator.configuration = configuration

                    let vpTask = Task { @MainActor in
                        tabletopGame?.coordinateWithSession(session)
                        for await immersionStyle in coordinator.groupImmersionStyle {
                            if immersionStyle != nil {
                                switchToImmersive = true
                            } else {
                                switchToImmersive = false
                            }
                        }
                    }

//                    Task.detached { @MainActor in
//                        for await state in coordinator.localParticipantStates {
//                            if state.isSpatial {
//                                // Synchronize additional data for the shared context.
//                                gameModel.isSpatial = true
//                            } else {
//                                // Don't synchronize additional data.
//                                gameModel.isSpatial = false
//                            }
//                        }
//                    }
                    tasks.insert(vpTask)
                }

                #endif

                self.configureGroupSession(session)
            }
        }
    }

    func configureGroupSession(_ groupSession: GroupSession<RPGActivity>) {
        Logger.sharePlay.debug("Configure Session \(groupSession.description, privacy: .public) state: \(self.printState(), privacy: .public)")

        self.groupSession = groupSession
        let messenger = GroupSessionMessenger(session: groupSession)
        self.messenger = messenger
        let journal = GroupSessionJournal(session: groupSession)
        self.journal = journal

        isActive = true
        groupSession.$state
            .sink { state in
                Logger.sharePlay.debug("Session state: \(self.printState(), privacy: .public)")
                self.stateText = self.printState()
                if case .invalidated = state {
                    self.groupSession = nil
                    self.reset()
                }
            }
            .store(in: &subscriptions)

        groupSession.$activeParticipants
            .sink { activeParticipants in
                let newParticipants = activeParticipants.subtracting(groupSession.activeParticipants)
                let removedParticipants = groupSession.activeParticipants.subtracting(activeParticipants)

                Logger.sharePlay.debug("Session Participants active: \(activeParticipants.debugDescription, privacy: .public) and new: \(newParticipants.debugDescription, privacy: .public) and removed: \(removedParticipants.debugDescription, privacy: .public)")

                removedParticipants.forEach {
                    self.delegate?.sharePlayLostPlayer(id: $0.id)
                }
            }
            .store(in: &subscriptions)

        let task = Task {
            for await (message, context) in messenger.messages(of: PackageMessage.self) {
                Logger.sharePlay.debug("Received Update Message \(message.uuid, privacy: .public): \(message.count, privacy: .public) - \(message.total, privacy: .public) from \(context.source.id, privacy: .public)")
                if let data = packageReceiver.received(package: message)?.data,
                    let gameModel = GameNetworkModel.decodeData(of: data) {
                    delegate?.handleUpdate(gameModel, id: context.source.id)
                }
            }
        }
        tasks.insert(task)
        let journalTask = Task {
            for await attachment in journal.attachments {
                await handle(attachment)
            }
        }
        tasks.insert(journalTask)
        
        groupSession.join()
        playBack?.coordinateWithSession(groupSession)
        #if os(visionOS)
        tabletopGame?.coordinateWithSession(groupSession)
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
