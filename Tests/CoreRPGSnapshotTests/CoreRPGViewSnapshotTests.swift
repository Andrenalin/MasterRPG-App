// @copyright André Trettin

import SnapshotTesting
import SwiftUI
import Testing
@testable import CoreRPG

@MainActor
@Suite(.serialized, .snapshots, .tags(.snapshot))
struct CoreRPGViewSnapshotTests {
    // snapshot-root: CoreRPG::BottomSafetyView
    @Test("BottomSafetyView")
    func bottomSafetyView() {
        let view = VStack {
            Text("Snapshot content")
            BottomSafetyView(space: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .environment(AppFocusModel())
        .environment(SearchBarVisibleModel())

        assertRepositorySnapshot(
            of: view.deterministicSnapshotEnvironment(),
            as: .image(
                perceptualPrecision: 0.98,
                layout: .fixed(width: 390, height: 180)
            )
        )
    }
}
