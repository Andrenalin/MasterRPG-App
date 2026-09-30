// @copyright André Trettin

import Foundation
import simd
import Testing

@testable import SpaceRPG

/// CODE_AUDIT_19 §9.23: the table-placement decision and pose math, moved out of `SpaceViewer`.
@MainActor
@Suite("Space table placement")
struct SpaceTablePlacementTests {
    @Test("A realignment re-places the object only until someone moves it")
    func realignmentRespectsAMovedObject() {
        let sut = SpaceTablePlacement()
        #expect(sut.shouldPlace(onTable: 1))

        sut.didPlace(onTable: 1)
        #expect(sut.shouldPlace(onTable: 1))

        sut.markMoved()
        #expect(!sut.shouldPlace(onTable: 1))
        #expect(sut.shouldPlace(onTable: 2))
    }

    @Test("A retained synced pose is kept on the same table")
    func retainedPoseIsKept() {
        let sut = SpaceTablePlacement()
        sut.adoptRetainedPose(onTable: 7)
        #expect(!sut.shouldPlace(onTable: 7))
    }

    @Test("The object's center lands one meter above the table top")
    func offsetFloatsAboveTable() {
        var tableTop = matrix_identity_float4x4
        tableTop.columns.3 = SIMD4<Float>(2, 0.8, -1, 1)
        var anchorPose = matrix_identity_float4x4
        anchorPose.columns.3 = SIMD4<Float>(0.5, 0, 0, 1)
        let center = SIMD3<Float>(0.1, 0.2, 0.3)

        let offset = SpaceTablePlacement.objectOffset(tableTop: tableTop, anchorPose: anchorPose, objectCenter: center)

        // Target in anchor space: (2 - 0.5, 0.8 + 1, -1); the center moves there.
        let expected = SIMD3<Float>(1.5, 1.8, -1) - center
        #expect(simd_distance(offset, expected) < 1e-5)
    }
}
