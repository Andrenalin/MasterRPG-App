// @copyright André Trettin

import Foundation
import FoundationModels
import SwiftUI

@Observable
@MainActor
final class FoundationManager {
    private(set) var notAvailableReason: LocalizedStringKey = "Checking model availability..."
    
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
            notAvailableReason = "Upgrade to use Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            notAvailableReason = "Enable Apple Intelligence in System Settings."
        case .unavailable(.modelNotReady):
            notAvailableReason = "Model not ready. Downloading or temporarily unavailable. Please wait, ensure sufficient battery and Wi-Fi."
        case.unavailable(let unknownReason):
            notAvailableReason = "Model unavailable: \(String(describing: unknownReason))"
        }
        return isModelAvailable
    }
    
    func minimizeMarkDown(_ content: String) -> String {
        let tags = ["#", "##", "###", "####", "---"]
        var content = content
        tags.forEach { tag in
            content = content.replacingOccurrences(of: tag, with: "")
        }
        return content
    }
    
    func checkLanguageSupport(for locale: Locale) {
        isLanguageSupported = SystemLanguageModel.default.supportsLocale(locale)
    }
}
