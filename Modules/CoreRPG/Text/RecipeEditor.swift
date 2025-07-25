// @copyright André Trettin

import SwiftUI
import SwiftData
import Foundation

@Model
final class ContentText: Identifiable {
    var lastModified: Date
    @Relationship(deleteRule: .cascade)
    var links: [LinkDataModel]

    var content: AttributedString {
        get { contentModel.value }
        set {
            contentModel.value = newValue
            lastModified = .now
        }
    }

    @Relationship(deleteRule: .cascade)
    private var contentModel: AttributedStringModel

    init(content: AttributedString, links: [LinkDataModel]) {
        self.links = links
        self.lastModified = .now
        self.contentModel = AttributedStringModel(value: content, scope: .content)
    }

    convenience init() {
        self.init(content: "", links: [])
    }
}



@MainActor
@Observable
final class EditableContentText: Identifiable {
    let model: ContentText

    var text: AttributedString {
        get {
            // SwiftData periodically saves the recipe while a person types, and
            // checks for changes to the model from other sources, like changes
            // from cloud storage. The editor needs to handle situations where
            // the text in the editor and the text in the SwiftData model
            // diverge. This code just chooses the newer version of the two. A
            // real app might compute the difference between the two variants,
            // attempt to merge them, and ask the user to resolve conflicts
            // where necessary.
            if lastModified >= model.lastModified {
                editedText
            } else {
                model.content
            }
        }
        set {
            model.content = newValue
            editedText = newValue
        }
    }

    private var editedText: AttributedString {
        didSet {
            lastModified = .now
        }
    }
    private var lastModified: Date

    var selection: AttributedTextSelection

    init(content: ContentText) {
        self.model = content
        self.selection = AttributedTextSelection()
        self.editedText = model.content
        self.lastModified = model.lastModified
    }
}

extension EditableContentText {
    /// The paragraph format the current selection exhibits.
    fileprivate var paragraphFormat: ParagraphFormat {
        get {
            let containers = selection.attributes(in: text)
            let formats = containers[\.paragraphFormat]

            return formats.contains(.section) ? .section : .body
        }
        set {
            text.transformAttributes(in: &selection) {
                $0.paragraphFormat = newValue
            }
        }
    }
}


struct DescriptionLinkEditor: View {
    @State var content = EditableContentText(content: ContentText(content: AttributedString("Example ohne Example"), links: []))

    var body: some View {
        VStack {
            Text(content.text)
            Divider()
            Picker("Paragraph Format", selection: $content.paragraphFormat) {
                Text("Section")
                    .tag(ParagraphFormat.section)
                Text("Body")
                    .tag(ParagraphFormat.body)
            }
            .pickerStyle(.inline)
            .fixedSize()

            Button {
                addLinks()
            } label: {
                Text("Selected: \(content.text[content.selection])")
            }
            Divider()
            TextEditor(text: $content.text, selection: $content.selection)
                .attributedTextFormattingDefinition(ContentFormattingDefinition(
                    links: Set(content.model.links.map(\.id))
                ))
        }
    }
    
    func addLinks() {
        let name = content.text[content.selection]
        let link = LinkDataModel(name: AttributedString(name), sourceId: UUID(), sourceModule: .pdf, destinationId: UUID(), destinationEntryId: nil, destinationModel: .photo)
        content.model.links.append(link)
        
        
        let ranges = RangeSet(content.text.characters.ranges(of: name.characters))

        content.text.transform(updating: &content.selection) { text in
            text[ranges].linkContent = link.id
        }
    }
}

#Preview {
    NavigationStack {
        DescriptionLinkEditor()
            .toolbarRole(.editor)
    }
}
