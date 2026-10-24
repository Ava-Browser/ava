/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Durable entities and manager for Spaces (TDD-Spaces.md).
 * All mutations write through to persistent storage immediately.
 */

import Foundation

public enum TabTier: String, Codable, Sendable, CaseIterable {
    case essential
    case pinned
    case normal
}

public struct GradientSpec: Codable, Equatable, Sendable {
    public var startColorHex: String
    public var endColorHex: String

    public init(startColorHex: String = "#3B82F6", endColorHex: String = "#8B5CF6") {
        self.startColorHex = startColorHex
        self.endColorHex = endColorHex
    }
}

public struct Workspace: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var icon: String // emoji or SF Symbol name
    public var theme: GradientSpec
    public var containerID: String?
    public var activeTabID: UUID?
    public var tabOrder: [UUID]

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "square.stack.3d.up",
        theme: GradientSpec = GradientSpec(),
        containerID: String? = nil,
        activeTabID: UUID? = nil,
        tabOrder: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.theme = theme
        self.containerID = containerID
        self.activeTabID = activeTabID
        self.tabOrder = tabOrder
    }
}

public struct TabDescriptor: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var workspaceID: UUID? // nil => Global Essential
    public var tier: TabTier
    public var url: String
    public var title: String
    public var faviconRef: String?
    public var scrollY: Double?
    public var folderID: UUID?

    public init(
        id: UUID = UUID(),
        workspaceID: UUID?,
        tier: TabTier = .normal,
        url: String,
        title: String = "",
        faviconRef: String? = nil,
        scrollY: Double? = nil,
        folderID: UUID? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.tier = tier
        self.url = url
        self.title = title
        self.faviconRef = faviconRef
        self.scrollY = scrollY
        self.folderID = folderID
    }
}

public struct TabFolder: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var workspaceID: UUID
    public var name: String
    public var isCollapsed: Bool
    public var order: Int

    public init(
        id: UUID = UUID(),
        workspaceID: UUID,
        name: String,
        isCollapsed: Bool = false,
        order: Int = 0
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.name = name
        self.isCollapsed = isCollapsed
        self.order = order
    }
}

public struct SpacesStoreState: Codable, Sendable {
    public var schemaVersion: Int
    public var activeWorkspaceID: UUID
    public var spaces: [Workspace]
    public var tabs: [TabDescriptor]
    public var folders: [TabFolder]

    public init(
        schemaVersion: Int = 1,
        activeWorkspaceID: UUID,
        spaces: [Workspace],
        tabs: [TabDescriptor],
        folders: [TabFolder] = []
    ) {
        self.schemaVersion = schemaVersion
        self.activeWorkspaceID = activeWorkspaceID
        self.spaces = spaces
        self.tabs = tabs
        self.folders = folders
    }
}

public protocol SpacesStore: Sendable {
    func load() -> SpacesStoreState?
    func save(_ state: SpacesStoreState)
}

public final class JSONSpacesStore: SpacesStore, @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else if let envPath = ProcessInfo.processInfo.environment["LADYBIRD_SPACES_STORE_PATH"] {
            self.fileURL = URL(fileURLWithPath: envPath)
        } else if ProcessInfo.processInfo.processName.contains("swiftpm-testing-helper") || ProcessInfo.processInfo.arguments.contains(where: { $0.contains(".xctest") || $0.contains("swift-testing") }) {
            // Tests run in isolated temporary locations so live user state is never touched
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LadybirdTests-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            self.fileURL = tempDir.appendingPathComponent("spaces-state.json")
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("LadybirdMac", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("spaces-state.json")
        }
    }

    public func load() -> SpacesStoreState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SpacesStoreState.self, from: data)
    }

    public func save(_ state: SpacesStoreState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
