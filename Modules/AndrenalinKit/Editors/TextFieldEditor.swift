// @copyright André Trettin

import SwiftUI

public struct TextFieldEditor: View {
    public init(editController: any EditControllable, model: Binding<String>, title: LocalizedStringKey? = "Name", prompt: LocalizedStringKey = "Enter a name", bundle: Bundle?, focusListner: Bool = false, onSubmitHandler: (() -> Void)? = nil) {
        self.editController = editController
        self.model = model
        self.title = title
        self.prompt = prompt
        self.bundle = bundle
        self.focusListner = focusListner
        self.onSubmitHandler = onSubmitHandler
    }

    let editController: any EditControllable
    let model: Binding<String>
    let title: LocalizedStringKey?
    let prompt: LocalizedStringKey
    let bundle: Bundle?
    let focusListner: Bool
    let onSubmitHandler: (() -> Void)?

    @FocusState private var focusState: Bool

    public var body: some View {
        //let _ = Self._printChanges()
        LabeledContent {
            textField(with: title ?? "")
        } label: {
            Text(title ?? "", bundle: bundle)
        }
        .applyIf(title == nil) { content in
            content.labelsHidden()
        }
        .onChange(of: editController.editorModel.activateFocus, initial: true) {
            guard focusListner && editController.editorModel.activateFocus else { return }
            withAnimation { focusState = true }
            editController.editorModel.activateFocus = false
        }
        .onChange(of: focusState, initial: false) {
            guard focusState == false else { return }
            if let onSubmitHandler {
                onSubmitHandler()
            } else {
                editController.save(with: String(localized: "Typing").localizedString)
            }
        }
    }
    
    func textField(with name: LocalizedStringKey) -> some View {
        TextField(text: model, prompt: Text(prompt, bundle: bundle), axis: .vertical) {
            Text(name, bundle: bundle)
        }
        .lineLimit(5)
#if os(iOS) || os(visionOS)
        .autocapitalization(.none)
        .textContentType(.name)
#endif
        .disableAutocorrection(true)
        .labelsHidden()
        .submitLabel(.return)
        .focused($focusState)
        .onSubmit {
            if let onSubmitHandler {
                onSubmitHandler()
            } else {
                model.wrappedValue = model.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                editController.save(with: String(localized: "Typing").localizedString)
            }
        }
    }
}
