/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * AppKit-backed address text field providing native focus, complete text selection, and keyboard commands.
 */

import AppKit
import SwiftUI

public final class FocusableAddressTextField: NSTextField {
    public var pendingFocusToken: Int?
    public var onFocusPerformed: ((Int) -> Void)?

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            performPendingFocusIfNeeded()
        }
    }

    public func performPendingFocusIfNeeded() {
        guard let window, let token = pendingFocusToken else { return }
        if window.firstResponder != currentEditor() {
            window.makeFirstResponder(self)
        }
        selectText(nil)
        pendingFocusToken = nil
        onFocusPerformed?(token)
    }

    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "l" {
            selectText(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

public struct AddressNativeField: NSViewRepresentable {
    @Binding public var text: String
    public var editRequestToken: Int
    public var onSubmit: () -> Void
    public var onCancel: () -> Void

    public init(
        text: Binding<String>,
        editRequestToken: Int,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._text = text
        self.editRequestToken = editRequestToken
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> FocusableAddressTextField {
        let textField = FocusableAddressTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.placeholderString = "Search or enter address"
        textField.onFocusPerformed = { [weak coordinator = context.coordinator] token in
            coordinator?.lastHandledToken = token
            coordinator?.isEditing = true
            coordinator?.actionHandled = false
        }
        return textField
    }

    public func updateNSView(_ nsView: FocusableAddressTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text && !context.coordinator.isEditing {
            nsView.stringValue = text
        }

        if context.coordinator.lastHandledToken != editRequestToken {
            nsView.stringValue = text
            nsView.pendingFocusToken = editRequestToken
            nsView.performPendingFocusIfNeeded()
        }
    }

    public final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressNativeField
        public internal(set) var lastHandledToken: Int = -1
        public internal(set) var isEditing = false
        public internal(set) var actionHandled = false

        init(_ parent: AddressNativeField) {
            self.parent = parent
        }

        public func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
            actionHandled = false
        }

        public func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        public func controlTextDidEndEditing(_ obj: Notification) {
            guard isEditing else { return }
            isEditing = false
            if !actionHandled {
                parent.onCancel()
            }
            actionHandled = false
        }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                actionHandled = true
                parent.onSubmit()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                actionHandled = true
                parent.onCancel()
                return true
            }
            return false
        }
    }
}
