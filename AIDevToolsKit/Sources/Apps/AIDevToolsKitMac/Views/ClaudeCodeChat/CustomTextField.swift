import AppKit
import SwiftUI

public struct CustomTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    let onTab: () -> Void
    let onUpArrow: () -> Void
    let onDownArrow: () -> Void

    public func makeNSView(context: Context) -> CustomNSTextField {
        let textField = CustomNSTextField()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)

        textField.onTab = onTab
        textField.onUpArrow = onUpArrow
        textField.onDownArrow = onDownArrow
        textField.onReturn = onSubmit

        return textField
    }

    public func updateNSView(_ nsView: CustomNSTextField, context _: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.onTab = onTab
        nsView.onUpArrow = onUpArrow
        nsView.onDownArrow = onDownArrow
        nsView.onReturn = onSubmit
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    public class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        public func controlTextDidChange(_ notification: Notification) {
            if let textField = notification.object as? NSTextField {
                text = textField.stringValue
            }
        }

        public func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                if let tf = control as? CustomNSTextField {
                    tf.onTab?()
                }
                return true
            } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
                if let tf = control as? CustomNSTextField {
                    tf.onUpArrow?()
                }
                return true
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                if let tf = control as? CustomNSTextField {
                    tf.onDownArrow?()
                }
                return true
            } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if let tf = control as? CustomNSTextField {
                    tf.onReturn?()
                }
                return true
            }
            return false
        }
    }
}

public class CustomNSTextField: NSTextField {
    var onTab: (() -> Void)?
    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?
    var onReturn: (() -> Void)?
}
