// @copyright André Trettin

import Foundation
import Network
import SwiftUI

@MainActor @Observable
final class BrowserModel: Sendable {
    private(set) var browsers: [BrowserDeviceModel] = []
    private(set) var removed: [NWBrowser.Result] = []
    
    func setBrowsers(_ browsers: [BrowserDeviceModel]) {
        removed = []
        self.browsers = browsers
        if browsers.isEmpty {
            statusMessage = "Nothing found"
        }
    }

    func append(model: BrowserDeviceModel) {
        browsers.append(model)
        browsers.sort { $0.deviceName < $1.deviceName }
        statusMessage = "Found \(browsers.count) Players"
    }

    func remove(id: BrowserDeviceModel.ID, result: NWBrowser.Result) {
        guard let index = browsers.firstIndex(where: { $0.id == id }) else { return }
        removed.append(result)
        browsers.remove(at: index)
        if browsers.isEmpty {
            statusMessage = "Nothing found"
        }
    }

    var hasMessage: Bool {
        !browsers.isEmpty
    }
    
    var statusMessage: LocalizedStringKey = "Nothing found"
}

struct BrowserDeviceModel: Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    let deviceName: String
}
