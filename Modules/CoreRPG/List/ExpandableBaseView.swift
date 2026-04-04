// @copyright André Trettin

import SwiftUI

struct ExpandableBaseView<Header: View, Content: View>: View, Animatable {
    var animatableData: CGFloat

    let header: Header
    let content: Content

    @State var baseFrame: CGRect = .zero
    @State var expansionFrame: CGRect = .zero

    init(animatableData: CGFloat,
         @ViewBuilder header: () -> Header,
         @ViewBuilder content: () -> Content) {
        self.animatableData = animatableData
        self.header = header()
        self.content = content()
    }

    var expandedContent: some View {
        content
            .opacity(animatableData)
            .getFrame($expansionFrame, space: .local)
            .offset(y: baseFrame.height)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            header
                .frame(maxWidth: .infinity)
                .getFrame($baseFrame, space: .local)
                .overlay(expandedContent, alignment: .top)
        }
        .frame(height: baseFrame.height + expansionFrame.height * animatableData,
               alignment: .top)
    }
}


fileprivate struct FrameMeasurePreferenceKey: PreferenceKey {
    typealias Value = [String: CGRect]

    static let defaultValue: Value = [:]

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { $1 }
    }
}

fileprivate struct MeasureFrameViewModifier: ViewModifier {
    @Binding var frame: CGRect
    let space: CoordinateSpace
    @State private var frameId = UUID()

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: FrameMeasurePreferenceKey.self,
                            value: ["frame_\(frameId)": geometry.frame(in: space)]
                        )
                }
            )
            .onPreferenceChange(FrameMeasurePreferenceKey.self) { preferences in
                if let frame = preferences["frame_\(frameId)"] {
                    self.frame = frame
                }
            }
    }
}

fileprivate extension View {
    func getFrame(_ frame: Binding<CGRect>, space: CoordinateSpace) -> some View {
        modifier(MeasureFrameViewModifier(frame: frame, space: space))
    }
}


#Preview {
    @Previewable @State var isExpanded = false
    List {
        ExpandableBaseView(
            animatableData: isExpanded ? 1 : 0,
            header: {
                Text("Tap to expand/collapse")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation() {
                            isExpanded.toggle()
                        }
                    }
            },
            content: {
                Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding()
            }
        )
        .background(.background.secondary)
        .clipShape(.rect(cornerRadius: 8))

        ExpandableBaseView(
            animatableData: isExpanded ? 1 : 0,
            header: {
                Text("2. Tap to expand/collapse")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation() {
                            isExpanded.toggle()
                        }
                    }
            },
            content: {
                Text("********* Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. ****")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding()
            }
        )
        .background(.background.secondary)
        .clipShape(.rect(cornerRadius: 8))

    }
}
