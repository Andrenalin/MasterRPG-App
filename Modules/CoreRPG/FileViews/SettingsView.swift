// @copyright André Trettin

import SwiftUI

@MainActor
public protocol StoreManiplable: Sendable {
    func resetData() async
    func validate()
}
