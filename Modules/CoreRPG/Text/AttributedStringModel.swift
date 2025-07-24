// @copyright André Trettin

import SwiftData
import Foundation

@Model
final class AttributedStringModel: Identifiable {
    @Transient
    lazy var value: AttributedString = initializeValue() {
        didSet {
            valueChanged = true
        }
    }

    @Transient
    private var valueChanged: Bool = false

    @Attribute(.externalStorage)
    private var data: Data

    private var scope: Scope

    init(value: AttributedString, scope: Scope) {
        self.data = Data()
        self.scope = scope
        self.value = value

        NotificationCenter.default.addObserver(
            self, selector: #selector(willSave),
            name: ModelContext.willSave, object: nil)
    }

    private func initializeValue() -> AttributedString {
        NotificationCenter.default.addObserver(
            self, selector: #selector(willSave),
            name: ModelContext.willSave, object: nil)

        do {
            let string = try JSONDecoder().decode(
                AttributedString.self,
                from: data,
                configuration: scope.decodingConfiguration)
            return string
        } catch {
            return ""
        }
    }

    @objc
    private func willSave() {
        guard valueChanged else { return }
        valueChanged = false

        do {
            self.data = try JSONEncoder().encode(
                value,
                configuration: scope.encodingConfiguration)
        } catch {
            print(error)
        }
    }
}

extension AttributedStringModel {
    enum Scope: String, Codable {
        case recipe
        case link

        fileprivate var encodingConfiguration: AttributeScopeCodableConfiguration {
            switch self {
            case .recipe:
                AttributeScopes.LinkModelAttributes.encodingConfiguration
            case .link:
                AttributeScopes.LinkNameAttributes.encodingConfiguration
            }
        }

        fileprivate var decodingConfiguration: AttributeScopeCodableConfiguration {
            switch self {
            case .recipe:
                AttributeScopes.LinkModelAttributes.decodingConfiguration
            case .link:
                AttributeScopes.LinkNameAttributes.decodingConfiguration
            }
        }
    }
}
