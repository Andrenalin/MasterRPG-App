// @copyright André Trettin

import Foundation
import FoundationModels

@Observable
@MainActor
final class FoundationManager {
    private(set) var notAvailableReason = String(
        localized: "Checking model availability...",
        bundle: .module
    )
    
    var isModelAvailable: Bool = false
    var isLanguageSupported = false
    
    init() {
        checkIsAvailable()
    }
    
    @discardableResult
    func checkIsAvailable() -> Bool {
        isModelAvailable = false
        switch SystemLanguageModel.default.availability {
        case .available:
            notAvailableReason = ""
            isModelAvailable = true
        case .unavailable(.deviceNotEligible):
            notAvailableReason = String(localized: "Upgrade to use Apple Intelligence", bundle: .module)
        case .unavailable(.appleIntelligenceNotEnabled):
            notAvailableReason = String(
                localized: "Enable Apple Intelligence in System Settings.",
                bundle: .module
            )
        case .unavailable(.modelNotReady):
            notAvailableReason = String(
                localized: "Model not ready. Downloading or temporarily unavailable. Please wait, ensure sufficient battery and Wi-Fi.",
                bundle: .module
            )
        case.unavailable(let unknownReason):
            notAvailableReason = String(
                localized: "Model unavailable: \(String(describing: unknownReason))",
                bundle: .module
            )
        }
        return isModelAvailable
    }
    
    func minimizeMarkDown(_ content: String) -> String {
        let tags = ["#", "##", "###", "####", "---"]
        var content = content
        tags.forEach { tag in
            content = content.replacing(tag, with: "")
        }
        return content
    }
    
    func checkLanguageSupport(for locale: Locale) {
        isLanguageSupported = SystemLanguageModel.default.supportsLocale(locale)
    }
}
