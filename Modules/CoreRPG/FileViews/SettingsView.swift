// @copyright André Trettin

import SwiftUI

@MainActor
public protocol StoreManipulable: Sendable {
    func resetData() async
    func validate()
}
