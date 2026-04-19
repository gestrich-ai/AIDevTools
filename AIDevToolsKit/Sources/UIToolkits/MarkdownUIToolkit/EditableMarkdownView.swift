import MarkdownUI
import SwiftUI

public struct EditableMarkdownView: View {
    @Binding private var text: String
    private let isEditing: Bool

    public init(text: Binding<String>, isEditing: Bool) {
        self._text = text
        self.isEditing = isEditing
    }

    public var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $text)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Markdown(text)
                    .markdownTheme(.gitHub.text {
                        ForegroundColor(.primary)
                        FontSize(14)
                    })
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
