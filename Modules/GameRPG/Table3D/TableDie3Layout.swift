// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation

// The d3 on the 3D table is the d6's cube (`TableDie6Geometry`) with a texture of its own: a cube
// whose six faces read 1, 2, 3, 1, 2, 3, so that the top face always gives the value. Opposite faces
// of the cube add up to seven, so the faces with 1 and 6 pips, 2 and 5 pips, and 3 and 4 pips are
// opposite and share a number. Pure, so it is unit-tested on iOS.

enum TableDie3Layout {
    /// The number a face of the cube shows on the d3, known by its pips on the d6: the face
    /// opposite it gets the same.
    static func number(forPips pips: Int) -> Int {
        pips > 3 ? 7 - pips : pips
    }

    /// The cube face to turn up to show a d3 value: the face with as many pips as the value.
    static func faceUp(forValue value: Int) -> Int? {
        (1 ... 3).contains(value) ? value : nil
    }
}
#endif
