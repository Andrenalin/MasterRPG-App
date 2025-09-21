// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

@Observable public final class TextEditModel {
    @MainActor public init(linkRegisterController: LinkRegisterController, text: String = "") {
        self.linkRegisterController = linkRegisterController
        self.text = text
        self.attributedText = AttributedString("")
        
        resetAttributedText()
    }
    
    let linkRegisterController: LinkRegisterController
    public var text: String
    var attributedText: AttributedString

    var links: [LinkDataModel] = []
    
    @MainActor public func resetAttributedText() {
        var att = AttributedString(text)
        links = linkRegisterController.linkDataModel(in: text)
        links.forEach {
            let markDown = linkRegisterController.markDown(for: $0)
            if let range = att.range(of: markDown) {
                var linkAtt = AttributedString($0.name)
                linkAtt[keyPath: \.linkContent] = $0.id
                att.replaceSubrange(range, with: linkAtt)
            }
        }
        
        self.attributedText = att
    }
    
    @MainActor public func resetText() {
        // Build plain text from attributedText by converting link attributed runs back to Markdown
        // We expect the custom attribute key path `\.linkContent` to contain the UUID of the link (LinkDataModel.id)
        var result = ""
        let att = attributedText

        // Iterate over runs, preserving non-link text and converting link runs
        for run in att.runs {
            print(run)
            let range = run.range
            let substring = String(att[range].characters)
            print(substring)
            
            if let linkId = run.linkContent {
                if let link = linkRegisterController.linkDataModel(linkId: linkId) {
                    let markdown = linkRegisterController.markDown(for: link)
                    result.append(markdown)
                } else {
                    result.append(substring)
                }
            } else {
                result.append(substring)
            }
        }

        // Update model state
        text = result
    }
    
    @MainActor static var preview: TextEditModel = {
        let modelContainer = try! ModelContainer(for: LinkDataModel.self, configurations: .init(isStoredInMemoryOnly: true))
        let controller = LinkRegisterController(container: modelContainer)
        let link = controller.register(name: "Name", sourceId: UUID(), sourceModule: .audio, destinationId: UUID(), destinationModule: .table)
        let text = "Hello World\n In the [Name](RPG://\(link.id.uuidString)) we will find peace."
        return TextEditModel(linkRegisterController: controller, text: text)
    }()
}

public struct TextEditorLinkView: View {
    public init(model: TextEditModel, maxHeight: CGFloat = 200.0) {
        self.model = model
        self.maxHeight = maxHeight
    }
    
    public let model: TextEditModel
    let maxHeight: CGFloat

    @State private var selection: AttributedTextSelection = .init()

    public var body: some View {
        @Bindable var model = model
        TextEditor(text: $model.attributedText, selection: $selection)
            .attributedTextFormattingDefinition(ContentFormattingDefinition(links: Set(model.links.map(\.id))))
            .frame(minHeight: 120, maxHeight: maxHeight)
//            .scrollContentBackground(.hidden)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.secondary)
            }
            .padding(.bottom, 6)
    }
}

#Preview {
    @Previewable @State var model: TextEditModel = .preview
    
    NavigationStack {
        VStack(alignment: .leading) {
            Text("Description")
            
            TextEditorLinkView(model: model)
 
            Button("Save") {
                model.resetText()
            }
            
            Text(model.text)
        }
        .padding()
    }
}

