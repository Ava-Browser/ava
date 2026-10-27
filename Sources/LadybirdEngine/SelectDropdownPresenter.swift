/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import AppKit
import LadybirdBridge

@MainActor
final class SelectDropdownPresenter: NSObject {
    private var menu: NSMenu?
    private weak var view: NSView?
    private var point = NSPoint.zero
    private var completion: ((UInt32?) -> Void)?

    func present(
        items: [PortSelectItem],
        minimumWidth: Int32,
        at point: NSPoint,
        in view: NSView,
        completion: @escaping (UInt32?) -> Void
    ) {
        self.completion = completion

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = CGFloat(max(0, minimumWidth))
        for item in items {
            switch item {
            case .option(let option):
                menu.addItem(menuItem(for: option))
            case .separator:
                menu.addItem(.separator())
            case .group(let label, let options):
                let heading = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                heading.isEnabled = false
                menu.addItem(heading)
                for option in options {
                    let item = menuItem(for: option)
                    item.indentationLevel = 1
                    menu.addItem(item)
                }
            }
        }
        self.menu = menu
        self.view = view
        self.point = point

        // The engine callback must return before AppKit enters menu tracking. The common-mode pump keeps rendering and
        // input alive while the native menu is open.
        perform(#selector(showMenu), with: nil, afterDelay: 0, inModes: [.common])
    }

    func cancel() {
        menu?.cancelTracking()
        finish(nil)
    }

    private func menuItem(for option: PortSelectOption) -> NSMenuItem {
        let item = NSMenuItem(title: option.label, action: #selector(selectItem(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = option.enabled
        item.state = option.selected ? .on : .off
        item.representedObject = NSNumber(value: option.id)
        return item
    }

    @objc private func showMenu() {
        guard let menu, let view, completion != nil else { return }
        menu.popUp(positioning: menu.items.first(where: { $0.state == .on }), at: point, in: view)
        finish(nil)
    }

    @objc private func selectItem(_ sender: NSMenuItem) {
        finish((sender.representedObject as? NSNumber)?.uint32Value)
    }

    private func finish(_ selection: UInt32?) {
        guard let completion else { return }
        self.completion = nil
        menu = nil
        completion(selection)
    }
}
