// @copyright André Trettin

import FoundationModels
import SwiftUI

struct GenericSegmentsView: View {
    let segments: [Transcript.Segment]
    let isUser: Bool

    @Environment(GeneratorRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            ForEach(segments, id: \.id) { segment in
                switch segment {
                case .structure(let structure):
                    VStack {
                        if let value = root.generatorController.model.result {
                            CharacterGenView(value: value, level: 0)
                        }
                        Group {
                            if let value = try? CharacterGenModel(structure.content) {
                                CharacterGenView(value: value, level: 0)
                            } else {
                                Text(verbatim: structure.description)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(8)
                        .background(isUser ? Color.blue.opacity(0.2) : nil)
                        .clipShape(.rect(cornerRadius: 8))
                        .contentTransition(.interpolate)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: structure.description)
                    }
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                case .text(let text):
                    VStack {
                        Text(verbatim: text.content)
                            .padding(8)
                            .background(isUser ? Color.blue.opacity(0.2) : nil)
                            .clipShape(.rect(cornerRadius: 8))
                            .contentTransition(.interpolate)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: text)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
#if compiler(>=6.4)
                case .attachment(let attachment):
                    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
                        attachmentView(attachment)
                            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                    } else {
                        Text(verbatim: String(describing: segment))
                    }
                case .custom(let custom):
                    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
                        customSegmentView(custom)
                            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                    } else {
                        Text(verbatim: String(describing: segment))
                    }
#endif
                @unknown default:
                    Text(verbatim: String(describing: segment))
                        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                }
            }
        }
        .textSelection(.enabled)
    }

#if compiler(>=6.4)
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    @ViewBuilder
    private func attachmentView(_ attachment: Transcript.AttachmentSegment) -> some View {
        switch attachment.content {
        case .image(let imageAttachment):
            Image(decorative: imageAttachment.cgImage, scale: 1)
                .resizable()
                .scaledToFit()
                .accessibilityLabel(
                    Text(
                        verbatim: attachment.label
                        ?? String(localized: "Attached image", bundle: .module)
                    )
                )
        @unknown default:
            Text(verbatim: attachment.description)
        }
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    private func customSegmentView(_ custom: any Transcript.CustomSegment) -> some View {
        Text(verbatim: custom.description)
            .padding(8)
            .background(isUser ? Color.blue.opacity(0.2) : nil)
            .clipShape(.rect(cornerRadius: 8))
    }
#endif
}

#Preview("Transcript Segments", traits: .mockData) {
    GenericSegmentsView(
        segments: [.text(.init(content: "A ruined fortress waits above the stormy coast."))],
        isUser: true
    )
}
