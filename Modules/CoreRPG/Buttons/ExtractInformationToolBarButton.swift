// @copyright André Trettin

#if !os(tvOS)
import SwiftUI

/// The "Extract Information" toolbar button that opens a module's on-device extraction sheet.
/// Shared by Adventure, Map, PDF and Table, which each had an identical copy that differed only
/// in the route and the disabled condition. See CODE_AUDIT_18 §9.14.
public struct ExtractInformationToolBarButton<Route: NavigationDestination>: View {
    private let route: Route
    private let isDisabled: Bool

    @Environment(\.navigator) private var navigator

    public init(route: Route, isDisabled: Bool) {
        self.route = route
        self.isDisabled = isDisabled
    }

    public var body: some View {
        Button {
            navigator.navigate(to: route, method: .managedSheet)
        } label: {
            Label {
                Text("Extract Information", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
        }
        .disabled(isDisabled)
    }
}
#endif
