// @copyright André Trettin

import SwiftUI

#Preview {
    @Previewable @State var number = 12
    QuickEditorIntView(number: $number)
        .padding()
}

struct QuickEditorIntView: View {
    @Binding var number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickEditorIntViewMinusButtonsView(number: $number)
            QuickEditorIntViewPlusButtonsView(number: $number)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct QuickEditorIntViewMinusButtonsView: View {
    @Binding var number: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach([10, 5, 2, 1], id: \.self) { value in
                QuickEditorButtonView(number: $number, value: value, title: "\(value)", isAddition: false)
            }
        }
    }
}

private struct QuickEditorIntViewPlusButtonsView: View {
    @Binding var number: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach([1, 2, 5, 10], id: \.self) { value in
                QuickEditorButtonView(number: $number, value: value, title: "\(value)", isAddition: true)
            }
        }
    }
}
