// @copyright André Trettin

import SwiftUI

/// Centered, `.headline`-styled section header (with a macOS-only leading
/// divider), collapsing the block that was duplicated verbatim across
/// `WeatherPhotoEditor`, `WeatherConditionEditor`, `WeatherStormEditor`, and
/// `WeatherThunderEditor`. See CODE_AUDIT_Weather §9.5.
struct WeatherSectionHeader: View {
    let titleKey: LocalizedStringKey
    let bundle: Bundle

    var body: some View {
#if os(macOS)
        Divider()
            .padding(.top)
#endif
        Text(titleKey, bundle: bundle)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
