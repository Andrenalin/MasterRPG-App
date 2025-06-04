// @copyright André Trettin

import Foundation
import SwiftUI

public struct TextFieldInlineEditor: View {
    public init(editController: any EditControllable, model: Binding<String>, prompt: LocalizedStringKey = "Enter a name", bundle: Bundle?, submitAction: (() -> Void)? = nil) {
        self.editController = editController
        self.model = model
        self.prompt = prompt
        self.bundle = bundle
        self.submitAction = submitAction
    }

    let editController: any EditControllable
    let model: Binding<String>
    let prompt: LocalizedStringKey
    let bundle: Bundle?
    let submitAction: (() -> Void)?

    @FocusState private var focusState: Bool

    public var body: some View {
        //let _ = Self._printChanges()
        TextField(text: model, prompt: Text(prompt, bundle: bundle), axis: .vertical) {
            EmptyView()
        }
        .lineLimit(5)
#if os(iOS) || os(visionOS)
        .autocapitalization(.none)
        .textContentType(.name)
#endif
        .disableAutocorrection(true)
        .labelsHidden()
        .submitLabel(.done)
        .focused($focusState)
        .onSubmit {
            model.wrappedValue = model.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            editController.save(with: String(localized: "Typing").localizedString)
            submitAction?()
        }
        .onChange(of: focusState, initial: true) {
            guard focusState == false else { return }
            editController.submitChanges()
            editController.save(with: String(localized: "Typing").localizedString)
            submitAction?()
        }
    }
}


public struct TextFieldInlineModelEditor: View {
    public init(editController: any EditControllable, linkReplaceController: LinkReplaceController, prompt: LocalizedStringKey = "Enter a name", bundle: Bundle?) {
        self.editController = editController
        self.controller = linkReplaceController
        self.prompt = prompt
        self.bundle = bundle
        self._name = State(wrappedValue: controller.editValue.wrappedValue)
    }

    let editController: any EditControllable
    let controller: LinkReplaceController
    let prompt: LocalizedStringKey
    let bundle: Bundle?

    @FocusState private var focusState: Bool
    
    @State private var name: String = ""
    
    public var body: some View {
        //let _ = Self._printChanges()
        TextField(text: $name, prompt: Text(prompt, bundle: bundle), axis: .vertical) {
            EmptyView()
        }
        .lineLimit(5)
#if os(iOS) || os(visionOS)
        .autocapitalization(.none)
        .textContentType(.name)
#endif
        .disableAutocorrection(true)
        .labelsHidden()
        .submitLabel(.done)
        .focused($focusState)
        .onSubmit {
            save()
        }
        .onChange(of: focusState, initial: true) {
            guard focusState == false else { return }
            save()
        }
        .onChange(of: controller.editValue.wrappedValue) {
            guard controller.editValue.wrappedValue != name else { return }
            withAnimation { name = controller.editValue.wrappedValue }
        }
    }
    
    private func save() {
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        controller.editValue.wrappedValue = name
        editController.save(with: String(localized: "Typing").localizedString)
    }
}
