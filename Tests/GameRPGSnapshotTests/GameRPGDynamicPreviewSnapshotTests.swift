// @copyright André Trettin

#if !os(visionOS)

import CharacterRPG
import CoreRPG
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
@testable import GameRPG

@MainActor
@Suite(.disabled(if: SnapshotTestAvailability.isDisabledForCurrentXcode, "Snapshot tests are disabled on Xcode 26."), .serialized, .snapshots, .tags(.snapshot))
struct GameRPGDynamicPreviewSnapshotTests {
    // snapshot-root: GameRPG::AttachmentSection
    @Test("AttachmentSection")
    func attachmentSection() async throws {
        try await assertDynamicSnapshot("AttachmentSection") {
            AttachmentSection(logController: .preview, isExpanded: .constant(true))
                .padding()
        }
    }

    // snapshot-root: GameRPG::GameToolBarButtonView
    @Test("GameToolBarButtonView")
    func gameToolBarButtonView() async throws {
        try await assertDynamicSnapshot("GameToolBarButtonView") {
            GameToolBarButtonView(valueType: .adventure, showType: .constant(.adventure))
                .environment(ScenesManager())
                .padding()
        }
    }

    // snapshot-root: GameRPG::SharingOptionsSection
    @Test("SharingOptionsSection")
    func sharingOptionsSection() async throws {
        try await assertDynamicSnapshot("SharingOptionsSection") {
            Form {
                SharingOptionsSection(features: .constant(GameFeatureModel()))
            }
        }
    }

    // snapshot-root: GameRPG::GameStatisticsFilterView
    @Test("GameStatisticsFilterView")
    func gameStatisticsFilterView() async throws {
        try await assertDynamicSnapshot("GameStatisticsFilterView") {
            GameStatisticsFilterView(configuration: .constant(.default))
                .padding()
        }
    }

    private func assertDynamicSnapshot<Content: View>(
        _ name: String,
        root: GameRoot = .previewFixture(),
        @ViewBuilder content: () -> Content
    ) async throws {
        let container = try await GameRPGDynamicPreviewSnapshotFixtureCache.modelContainer()
        assertRepositorySnapshot(
            of: content()
                .modifier(MockRootViewModifier(root: root))
                .environment(AppFocusModel())
                .modelContainer(container)
                .deterministicSnapshotEnvironment()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background),
            as: .image(
                perceptualPrecision: 0.98,
                layout: .fixed(width: 390, height: 844)
            ),
            named: name
        )
    }
}

@MainActor
private enum GameRPGDynamicPreviewSnapshotFixtureCache {
    private static var cachedContainer: ModelContainer?

    static func modelContainer() async throws -> ModelContainer {
        if let cachedContainer {
            return cachedContainer
        }
        let container = try await MockData.makeSharedContext()
        cachedContainer = container
        return container
    }
}

#endif
