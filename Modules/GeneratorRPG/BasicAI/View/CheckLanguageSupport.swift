// @copyright André Trettin

import FoundationModels
import SwiftUI

struct CheckLanguageSupport: View {
    @Environment(FoundationManager.self) var manager
    
    @Environment(\.locale) var locale: Locale
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Your current language \(locale.identifier)", bundle: .module)
                HStack {
                    Image(systemName: manager.isLanguageSupported ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(manager.isLanguageSupported ? .green : .red)
                    Text(manager.isLanguageSupported ? "Supported" : "Not Supported", bundle: .module)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .onAppear {
            checkLanguageSupport()
        }
    }
    
    private func checkLanguageSupport() {
        manager.checkLanguageSupport(for: locale)
    }
}

#Preview {
    CheckLanguageSupport()
        .environment(FoundationManager())
}
