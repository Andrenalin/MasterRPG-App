// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation

// The d3 on the 3D table is the d6's mesh (`Die.usdz`) with a texture of its own: a cube whose six
// faces read 1, 2, 3, 1, 2, 3, so that the top face always gives the value. Opposite faces of the d6
// add up to seven, so the faces with 1 and 6 pips, 2 and 5 pips, and 3 and 4 pips are opposite and
// share a number. Pure, so it is unit-tested on iOS.

enum TableDie3Layout {
    /// A face of the d6 mesh on its texture atlas, known by the pips it has on the d6.
    struct Island: Equatable {
        let pips: Int
        /// The center of the face on the atlas (0…1, y down), measured from the d6's pips, which
        /// lie symmetrically around it.
        let center: SIMD2<Float>

        /// The number this face shows on the d3.
        var number: Int {
            TableDie3Layout.number(forPips: pips)
        }
    }

    static let islands: [Island] = [
        Island(pips: 5, center: [0.1881, 0.1716]),
        Island(pips: 6, center: [0.5464, 0.1711]),
        Island(pips: 3, center: [0.1875, 0.4996]),
        Island(pips: 4, center: [0.5461, 0.4973]),
        Island(pips: 2, center: [0.1885, 0.8283]),
        Island(pips: 1, center: [0.5468, 0.8310])
    ]

    /// The number of a face with this many pips on the d6: the face opposite it gets the same.
    static func number(forPips pips: Int) -> Int {
        pips > 3 ? 7 - pips : pips
    }

    /// The d6 face to turn up to show a d3 value: the face with as many pips as the value.
    static func faceUp(forValue value: Int) -> Int? {
        (1 ... 3).contains(value) ? value : nil
    }
}
#endif
