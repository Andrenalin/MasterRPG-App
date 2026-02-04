// @copyright André Trettin

import SwiftUI

@MainActor @Observable public final class DetailInspectorModel {
    public init(canShowInspector: Bool = false, currentInspectorView: AnyView? = nil) {
        self.canShowInspector = canShowInspector
        self.currentInspectorView = currentInspectorView
    }

    public var canShowInspector: Bool = false
    public var disableShowInspector: Bool = false
    public var currentInspectorView: AnyView? = nil
    public var showInspector: Bool = false
}
