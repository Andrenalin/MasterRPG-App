// @copyright André Trettin

import CoreGraphics

// Split out of MapEditorModel.swift — see CODE_AUDIT §9.13.

extension MapEditorSession {
    var canReshare: Bool {
        lastHexScale != hexScale
            || lastPinScale != pinScale
            || lastIsHexMap != isHexMap
    }

    func resetScales(from map: MapModel) {
        pinScale = map.pinScale
        hexScale = map.hexMapScale
        isHexMap = map.entries.contains(where: { $0.isHexGrid })
        resetReshare()
    }

    func resetReshare() {
        lastPinScale = pinScale
        lastHexScale = hexScale
        lastIsHexMap = isHexMap
    }
}
