/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The durable half of the browser: workspaces and their tabs, as pure data.
 *
 * Nothing here knows the engine exists. Engine tab handles are a render cache of this graph (TDD-Spaces §1), so every
 * type below is Codable and every mutation is written through to disk by WorkspaceManager. That is what makes
 * "persistent tabs", "unload a workspace" and "crash recovery" one policy instead of three features.
 */

import Foundation

/// A tab's identity, independent of any engine handle.
///
/// Deliberately not `UUID` itself: `Workspace.ID` is also a UUID, and mixing the two compiles. The engine handle is a
/// *third* id (u64, changes per launch) and lives in the runtime cache, never here.
public struct TabID: Hashable, Codable, Sendable {
    public let raw: UUID

    public init(raw: UUID = UUID()) {
        self.raw = raw
    }
}

/// Which of the three sidebar sections a tab belongs to (TDD-Spaces §3).
///
/// Essentials are a tier, not "pinned everywhere": an essential has no workspace and closes only from its own section.
public enum TabTier: String, Codable, Sendable, CaseIterable {
    case essential
    case pinned
    case normal
}

/// Two hex colours for a space's dock icon. Kept this shallow on purpose — mesh gradients are a later polish pass and
/// the dock only needs something to fill a capsule today.
public struct GradientSpec: Codable, Hashable, Sendable {
    public var startHex: String
    public var endHex: String

    public init(startHex: String, endHex: String) {
        self.startHex = startHex
        self.endHex = endHex
    }

    /// Cycles through a fixed palette so a new space is visibly not like its neighbours without asking the user.
    public static let palette: [GradientSpec] = [
        .init(startHex: "#5B8DEF", endHex: "#9B6BFF"),
        .init(startHex: "#FF7A59", endHex: "#FFB259"),
        .init(startHex: "#2ECC9B", endHex: "#5BD6A8"),
        .init(startHex: "#F45B9C", endHex: "#FF86B3"),
        .init(startHex: "#8E8E93", endHex: "#B9B9C0"),
    ]
}

public struct Workspace: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Emoji or SF Symbol name; the dock renders it as text so either works.
    public var icon: String
    public var theme: GradientSpec
    /// Dormant until the containers probe (M5.5) passes; the column ships now so adding containers is not a migration.
    public var containerID: String?
    /// Per-space selection memory: switching away and back restores what you were looking at.
    public var activeTabID: TabID?
    /// Order of this space's tabs. Essentials are ordered globally, not here.
    public var tabOrder: [TabID]

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        theme: GradientSpec,
        containerID: String? = nil,
        activeTabID: TabID? = nil,
        tabOrder: [TabID] = []
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

/// One tab as stored. Everything needed to rebuild the row and reload the page after a relaunch.
public struct TabDescriptor: Codable, Identifiable, Hashable, Sendable {
    public var id: TabID
    /// nil means Global Essential — it appears in every space's essentials section.
    public var workspaceID: UUID?
    public var tier: TabTier
    public var url: String
    public var title: String
    public var faviconRef: String?
    /// Best-effort; captured at unload (M6). There is no exact-restore API upstream, so this is a hint, not a promise.
    public var scrollY: Double?
    /// Ships dormant, like containerID: single-level folders are the shipped UI, nesting is schema-only for now.
    public var folderID: UUID?
    public var containerID: String?

    public init(
        id: TabID = TabID(),
        workspaceID: UUID?,
        tier: TabTier,
        url: String = "about:blank",
        title: String = "New Tab",
        faviconRef: String? = nil,
        scrollY: Double? = nil,
        folderID: UUID? = nil,
        containerID: String? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.tier = tier
        self.url = url
        self.title = title
        self.faviconRef = faviconRef
        self.scrollY = scrollY
        self.folderID = folderID
        self.containerID = containerID
    }
}

/// The whole persisted document (TDD-Spaces §4).
///
/// One document, one atomic write per mutation. A single JSON file is the smallest thing that satisfies the contract:
/// both stores the TDD names (SwiftData, SQLite) would add a dependency or a schema-migration story to serve ≤ a few
/// dozen rows, and the contract here is the *shape*, which the TDD leaves to the implementer. Unknown fields decode as
/// defaults, so adding `folderID`/`containerID` later stays a non-event.
public struct PersistedGraph: Codable, Sendable {
    /// Bumped when a change cannot be expressed as "a new optional field".
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Which space the app was showing; restored on launch.
    public var activeSpaceID: UUID?
    /// Global essentials, ordered. They belong to no space, so their order is not any space's `tabOrder`.
    public var essentialOrder: [TabID]
    public var workspaces: [Workspace]
    public var tabs: [TabDescriptor]

    public init(
        schemaVersion: Int = PersistedGraph.currentSchemaVersion,
        activeSpaceID: UUID? = nil,
        essentialOrder: [TabID] = [],
        workspaces: [Workspace] = [],
        tabs: [TabDescriptor] = []
    ) {
        self.schemaVersion = schemaVersion
        self.activeSpaceID = activeSpaceID
        self.essentialOrder = essentialOrder
        self.workspaces = workspaces
        self.tabs = tabs
    }
}

/// Reads and writes the graph document.
///
/// Synchronous and main-thread by design: the graph is small, and a background write would reintroduce exactly the
/// thread hop S3 exists to forbid.
public struct GraphStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/LadybirdMac/spaces.json` — one root for all profiles, which is the Chrome layout
    /// and stays compatible with per-profile stores later (TDD-Spaces §2.1).
    public static func applicationDefault() -> GraphStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return GraphStore(url: base.appendingPathComponent("LadybirdMac/spaces.json"))
    }

    public func load() -> PersistedGraph? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let graph = try? JSONDecoder().decode(PersistedGraph.self, from: data),
              graph.schemaVersion <= PersistedGraph.currentSchemaVersion else {
            // The next mutation will create a fresh document. Preserve the bytes first: silently overwriting a corrupt
            // or newer-schema graph would turn a recoverable launch into permanent data loss.
            try? data.write(to: url.appendingPathExtension("unreadable"), options: .atomic)
            return nil
        }
        return graph
    }

    public func save(_ graph: PersistedGraph) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // `.atomic` is the whole durability story: a crash mid-write leaves the previous document intact, so there is
        // no torn state to recover from and no journal to replay.
        try encoder.encode(graph).write(to: url, options: .atomic)
    }
}
