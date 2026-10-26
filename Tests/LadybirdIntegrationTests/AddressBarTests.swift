/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Tests for address bar formatting, draft lifecycle, tab isolation, and copy semantics.
 */

import AppKit
import Foundation
import SwiftUI
import Testing

@testable import LadybirdEngine

@Suite("Address bar resting display formatting")
struct AddressBarFormattingTests {
    @Test("Ordinary HTTP and HTTPS hosts display their full host name without scheme or path")
    func ordinaryHosts() {
        #expect(AddressFormatter.restingDisplay(for: "https://example.com") == "example.com")
        #expect(AddressFormatter.restingDisplay(for: "https://example.com/path/to/page?q=1#frag") == "example.com")
        #expect(AddressFormatter.restingDisplay(for: "http://example.org/") == "example.org")
    }

    @Test("Subdomains are fully preserved and never truncated")
    func subdomains() {
        #expect(AddressFormatter.restingDisplay(for: "https://sub.domain.example.com/path") == "sub.domain.example.com")
        #expect(AddressFormatter.restingDisplay(for: "https://api.v2.internal.corp/status") == "api.v2.internal.corp")
    }

    @Test("Standard ports 80 (HTTP) and 443 (HTTPS) are omitted from resting display")
    func standardPorts() {
        #expect(AddressFormatter.restingDisplay(for: "http://example.com:80/") == "example.com")
        #expect(AddressFormatter.restingDisplay(for: "https://example.com:443/") == "example.com")
    }

    @Test("Unusual and non-standard ports are explicitly displayed")
    func unusualPorts() {
        #expect(AddressFormatter.restingDisplay(for: "http://localhost:8080/dashboard") == "localhost:8080")
        #expect(AddressFormatter.restingDisplay(for: "http://127.0.0.1:3000/") == "127.0.0.1:3000")
        #expect(AddressFormatter.restingDisplay(for: "https://example.com:8443/secure") == "example.com:8443")
        #expect(AddressFormatter.restingDisplay(for: "http://example.com:443/") == "example.com:443")
        #expect(AddressFormatter.restingDisplay(for: "https://example.com:80/") == "example.com:80")
    }

    @Test("IPv6 addresses are safely bracketed with and without unusual ports")
    func ipv6Hosts() {
        #expect(AddressFormatter.restingDisplay(for: "http://[::1]/") == "[::1]")
        #expect(AddressFormatter.restingDisplay(for: "http://[::1]:8080/api") == "[::1]:8080")
        #expect(AddressFormatter.restingDisplay(for: "https://[2001:db8::1]/path") == "[2001:db8::1]")
        #expect(AddressFormatter.restingDisplay(for: "https://[2001:db8::1]:9443/path") == "[2001:db8::1]:9443")
    }

    @Test("Empty strings and about:blank display subdued prompt (empty resting string)")
    func emptyAndBlank() {
        #expect(AddressFormatter.restingDisplay(for: "") == "")
        #expect(AddressFormatter.restingDisplay(for: "   ") == "")
        #expect(AddressFormatter.restingDisplay(for: "about:blank") == "")
    }

    @Test("Non-HTTP(S) schemes display explicit safe raw strings, never guessing a false domain")
    func nonHTTPSchemes() {
        #expect(AddressFormatter.restingDisplay(for: "about:version") == "about:version")
        #expect(AddressFormatter.restingDisplay(for: "file:///Users/test/index.html") == "file:///Users/test/index.html")
        #expect(AddressFormatter.restingDisplay(for: "data:text/html,<h1>Hello</h1>") == "data:text/html,<h1>Hello</h1>")
        #expect(AddressFormatter.restingDisplay(for: "javascript:alert(1)") == "javascript:alert(1)")
    }

    @Test("Unparseable or malformed input displays safely without synthesizing a domain")
    func unparseableInput() {
        #expect(AddressFormatter.restingDisplay(for: "not a valid url") == "not a valid url")
        #expect(AddressFormatter.restingDisplay(for: "http://") == "http://")
    }
}

@Suite("Address bar draft lifecycle and tab isolation")
@MainActor
struct AddressBarStateTests {
    @Test("Resting address bar correctly separates resting display from complete copyable URL")
    func restingStateAndCopyableURL() {
        let state = AddressBarState(initialURL: "https://sub.example.com:8080/path?query=1#hash")
        #expect(!state.isEditing)
        #expect(state.restingDisplay == "sub.example.com:8080")
        #expect(state.copyableURL == "https://sub.example.com:8080/path?query=1#hash")
    }

    @Test("Beginning editing populates the full URL into the draft")
    func beginEditingWithFullURL() {
        let state = AddressBarState(initialURL: "https://example.com/docs/api?version=2")
        state.beginEditing()
        #expect(state.isEditing)
        #expect(state.draft == "https://example.com/docs/api?version=2")
        #expect(state.editRequestToken == 1)
    }

    @Test("Repeated beginEditing increments token for repeated Cmd-L re-selection")
    func repeatedBeginEditingIncrementsToken() {
        let state = AddressBarState(initialURL: "https://example.com/page")
        state.beginEditing()
        #expect(state.editRequestToken == 1)

        // User presses Cmd-L again while editing
        state.beginEditing()
        #expect(state.editRequestToken == 2)
        #expect(state.isEditing)
        #expect(state.draft == "https://example.com/page")
    }

    @Test("Beginning editing on an empty or about:blank tab starts with an empty draft")
    func beginEditingOnBlankTab() {
        let blankState = AddressBarState(initialURL: "about:blank")
        blankState.beginEditing()
        #expect(blankState.isEditing)
        #expect(blankState.draft == "")

        let emptyState = AddressBarState(initialURL: "")
        emptyState.beginEditing()
        #expect(emptyState.isEditing)
        #expect(emptyState.draft == "")
    }

    @Test("Discarding draft exits editing and restores resting display without changing URL")
    func discardDraft() {
        let state = AddressBarState(initialURL: "https://example.com")
        state.beginEditing()
        state.draft = "some search query in progress"
        state.discardDraft()
        #expect(!state.isEditing)
        #expect(state.draft == "")
        #expect(state.restingDisplay == "example.com")
        #expect(state.currentURL == "https://example.com")
    }

    @Test("Committing draft returns trimmed input and exits editing")
    func commitDraft() {
        let state = AddressBarState(initialURL: "https://example.com")
        state.beginEditing()
        state.draft = "  https://newsite.org/page   "
        let committed = state.commitDraft()
        #expect(committed == "https://newsite.org/page")
        #expect(!state.isEditing)
        #expect(state.draft == "")

        // Empty commit returns nil
        state.beginEditing()
        state.draft = "   \n\t "
        #expect(state.commitDraft() == nil)
        #expect(!state.isEditing)
    }

    @Test("Stale engine callbacks during editing do not overwrite in-progress user drafts")
    func staleCallbackDoesNotOverwriteDraft() {
        let state = AddressBarState(initialURL: "https://first.example")
        state.beginEditing()
        state.draft = "user is currently typing"

        // Background load finishes or redirect fires
        state.handleURLChange("https://redirected.example")

        #expect(state.isEditing)
        #expect(state.draft == "user is currently typing")
        #expect(state.currentURL == "https://redirected.example")
    }

    @Test("Tab switches discard active draft and restore new tab's URL without leaking")
    func tabSwitchDiscardsDraftAndPreventsLeak() {
        let state = AddressBarState(initialURL: "https://tab1.example/page")
        state.beginEditing()
        state.draft = "draft meant for tab 1 only"

        // Switch to Tab 2
        state.handleTabSwitch(to: "https://tab2.example")

        #expect(!state.isEditing)
        #expect(state.draft == "")
        #expect(state.currentURL == "https://tab2.example")
        #expect(state.restingDisplay == "tab2.example")
    }

    @Test("BrowserModel copyCurrentURL writes to an isolated test pasteboard without side effects")
    func copyCurrentURLWritesToIsolatedPasteboard() {
        let store = GraphStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json"))
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        _ = manager.createWorkspace(name: "Test")
        _ = manager.createTab(tier: .normal, url: "https://example.com:8443/path?key=value")

        let model = BrowserModel(store: store)
        // Use an isolated pasteboard instance with a unique name to prevent any mutation to NSPasteboard.general
        let isolatedPasteboard = NSPasteboard.withUniqueName()

        model.copyCurrentURL(to: isolatedPasteboard)
        #expect(isolatedPasteboard.string(forType: .string) == "https://example.com:8443/path?key=value")
    }
}

@Suite("Native address text field behavior")
@MainActor
struct NativeAddressFieldTests {
    @Test("Pending focus request is deferred until attached to window and selects all text")
    func deferredFocusOnWindowAttachment() {
        let textField = FocusableAddressTextField()
        textField.stringValue = "https://example.com/long/path"
        var tokenRecorded: Int?
        textField.onFocusPerformed = { token in
            tokenRecorded = token
        }
        textField.pendingFocusToken = 42

        // Before window attachment, performPendingFocusIfNeeded does nothing
        textField.performPendingFocusIfNeeded()
        #expect(textField.pendingFocusToken == 42)
        #expect(tokenRecorded == nil)

        // Attach to a window
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(textField)
        window.makeKeyAndOrderFront(nil)

        // viewDidMoveToWindow automatically triggered performPendingFocusIfNeeded
        #expect(textField.pendingFocusToken == nil)
        #expect(tokenRecorded == 42)
        if let editor = textField.currentEditor() as? NSTextView {
            #expect(editor.selectedRange().location == 0)
            #expect(editor.selectedRange().length == ("https://example.com/long/path" as NSString).length)
        }
    }

    @Test("Repeated focus token re-selects entire text")
    func repeatedFocusTokenReselectsAll() {
        let textField = FocusableAddressTextField()
        textField.stringValue = "https://example.com"
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(textField)
        window.makeKeyAndOrderFront(nil)

        textField.pendingFocusToken = 1
        textField.performPendingFocusIfNeeded()
        let editor = textField.currentEditor() as! NSTextView
        #expect(editor.selectedRange() == NSRange(location: 0, length: 19))

        // Deselect text
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        #expect(editor.selectedRange() == NSRange(location: 3, length: 0))

        // Re-focus request (repeated Cmd-L)
        textField.pendingFocusToken = 2
        textField.performPendingFocusIfNeeded()
        #expect(editor.selectedRange() == NSRange(location: 0, length: 19))
    }

    @Test("performKeyEquivalent with Cmd-L re-selects entire text")
    func performKeyEquivalentCmdLReselectsAll() {
        let textField = FocusableAddressTextField()
        textField.stringValue = "https://example.com/page"
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(textField)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textField)
        textField.selectText(nil)

        let editor = textField.currentEditor() as! NSTextView
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(editor.selectedRange() == NSRange(location: 5, length: 0))

        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "l",
            charactersIgnoringModifiers: "l",
            isARepeat: false,
            keyCode: 37
        )!
        let handled = textField.performKeyEquivalent(with: event)
        #expect(handled)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 24))
    }

    @Test("Blur without submit or cancel invokes discard callback")
    func blurInvokesCancelCallback() {
        var cancelCount = 0
        var submitCount = 0
        var text = "https://example.com"
        let binding = Binding(get: { text }, set: { text = $0 })

        let field = AddressNativeField(
            text: binding,
            editRequestToken: 1,
            onSubmit: { submitCount += 1 },
            onCancel: { cancelCount += 1 }
        )
        let coordinator = field.makeCoordinator()
        let textField = FocusableAddressTextField()
        textField.delegate = coordinator
        textField.onFocusPerformed = { token in
            coordinator.lastHandledToken = token
            coordinator.isEditing = true
            coordinator.actionHandled = false
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(textField)
        window.makeKeyAndOrderFront(nil)

        textField.pendingFocusToken = 1
        textField.performPendingFocusIfNeeded()
        #expect(coordinator.isEditing)

        // Focus loss / Blur
        window.makeFirstResponder(nil)
        #expect(cancelCount == 1)
        #expect(submitCount == 0)
    }

    @Test("Submit does not trigger blur cancellation")
    func submitDoesNotTriggerBlurCancel() {
        var cancelCount = 0
        var submitCount = 0
        var text = "https://example.com"
        let binding = Binding(get: { text }, set: { text = $0 })

        let field = AddressNativeField(
            text: binding,
            editRequestToken: 1,
            onSubmit: { submitCount += 1 },
            onCancel: { cancelCount += 1 }
        )
        let coordinator = field.makeCoordinator()
        let textField = FocusableAddressTextField()
        textField.delegate = coordinator
        textField.onFocusPerformed = { token in
            coordinator.lastHandledToken = token
            coordinator.isEditing = true
            coordinator.actionHandled = false
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(textField)
        window.makeKeyAndOrderFront(nil)

        textField.pendingFocusToken = 1
        textField.performPendingFocusIfNeeded()
        #expect(coordinator.isEditing)

        let textView = textField.currentEditor() as! NSTextView
        _ = coordinator.control(textField, textView: textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(submitCount == 1)

        // Now end editing as text field resigns
        window.makeFirstResponder(nil)
        #expect(cancelCount == 0)
    }
}
