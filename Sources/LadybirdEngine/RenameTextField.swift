/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * AppKit-backed inline rename field. SwiftUI's TextField cannot select its text on focus, and a rename that starts
 * with the caret at the end makes the user retype the name; this selects everything first, like Arc's space rename.
 */

import AppKit
import SwiftUI

public final class SelectableRenameTextField: NSTextField {
    public var selectAllOnFocus: Bool = false

    // Selecting in viewDidMoveToWindow is too early: the field editor does not exist yet, so currentEditor() is nil and
    // the caret lands at the end of the name. Selecting after becoming first responder is the point where it exists.
    override public func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted && selectAllOnFocus {
            selectAllOnFocus = false
            currentEditor()?.selectAll(nil)
        }
        return accepted
    }
}

public struct RenameTextField: NSViewRepresentable {
    @Binding public var text: String
    public var onSubmit: () -> Void
    public var onCancel: () -> Void

    public init(text: Binding<String>, onSubmit: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self._text = text
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> SelectableRenameTextField {
        let field = SelectableRenameTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        field.focusRingType = .none
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.stringValue = text
        field.selectAllOnFocus = true
        return field
    }

    public func updateNSView(_ nsView: SelectableRenameTextField, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.didFocus {
            // The view is recreated per rename session, so this runs once and lands focus on the new field.
            context.coordinator.didFocus = true
            nsView.selectAllOnFocus = true
            nsView.window?.makeFirstResponder(nsView)
        } else if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    public final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameTextField
        var didFocus = false
        private var settled = false

        init(_ parent: RenameTextField) {
            self.parent = parent
        }

        public func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                settled = true
                parent.onSubmit()
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                settled = true
                parent.onCancel()
                return true
            }
            return false
        }

        // Committing on blur keeps the previous behavior: the rename is not silently dropped when the user clicks away.
        public func controlTextDidEndEditing(_ obj: Notification) {
            guard !settled else { return }
            settled = true
            parent.onSubmit()
        }
    }
}
