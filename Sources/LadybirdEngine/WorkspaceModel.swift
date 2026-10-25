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

    public static func isValidHex(_ hex: String) -> Bool {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard cleaned.count == 6 else { return false }
        return cleaned.range(of: #"^[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil
    }

    public static func normalizedHex(_ hex: String) -> String? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard isValidHex(cleaned) else { return nil }
        return "#" + cleaned.uppercased()
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

    public var isSymbol: Bool {
        Self.isSymbolIcon(icon)
    }

    public static func isSymbolIcon(_ icon: String) -> Bool {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if isValidEmoji(trimmed) { return false }
        return standardSymbols.contains(trimmed) || trimmed.range(of: #"^[a-zA-Z0-9.-]+$"#, options: .regularExpression) != nil
    }

    public static func isValidIcon(_ icon: String) -> Bool {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if standardSymbols.contains(trimmed) { return true }
        return isValidEmoji(trimmed)
    }

    public static func isValidEmoji(_ string: String) -> Bool {
        guard string.count == 1 else { return false }
        // Reject ASCII characters, numbers, and symbols like #, *, 0-9 which Unicode flags as emoji
        guard !string.allSatisfy(\.isASCII) else { return false }
        return string.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && !scalar.isASCII)
        }
    }

    public static let standardSymbols: [String] = [
        "circle.grid.2x2.fill",
        "house.fill",
        "briefcase.fill",
        "book.fill",
        "heart.fill",
        "star.fill",
        "globe",
        "sparkles",
        "folder.fill",
        "bookmark.fill",
        "gearshape.fill",
        "person.fill",
        "terminal.fill",
        "tray.fill",
        "wrench.and.screwdriver.fill",
        "graduationcap.fill",
        "cart.fill",
        "gamecontroller.fill",
        "tv.fill",
        "music.note",
        "camera.fill",
        "doc.text.fill",
        "tag.fill",
        "list.bullet"
    ]

    public static let standardEmojis: [String] = [
        "🚀", "💼", "📚", "🎨", "🔬", "🎮",
        "☕️", "✨", "🛠️", "💡", "🎯", "🏠"
    ]

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
    public enum LoadResult: Sendable {
        case empty
        case loaded(PersistedGraph)
        case unreadableBackupFailed(any Error)
        case unreadablePreserved(backupURL: URL)
    }

    public let url: URL
    private let now: @Sendable () -> Date

    public init(url: URL, now: @escaping @Sendable () -> Date = Date.init) {
        self.url = url
        self.now = now
    }

    /// `~/Library/Application Support/LadybirdMac/spaces.json` — one root for all profiles, which is the Chrome layout
    /// and stays compatible with per-profile stores later (TDD-Spaces §2.1).
    public static func applicationDefault() -> GraphStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return GraphStore(url: base.appendingPathComponent("LadybirdMac/spaces.json"))
    }

    /// Loads the stored document.
    ///
    /// Invariants (M5 hygiene):
    /// - Corrupted or newer-schema files are backed up to a timestamped file `.unreadable-YYYYMMDDTHHMMSSZ` so repeated
    ///   launches accumulate unreadable versions rather than clobbering the previous backup.
    /// - If the backup fails to write, load reports `unreadableBackupFailed` and callers MUST abort overwriting the file.
    public func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        guard let data = try? Data(contentsOf: url) else {
            return .empty
        }

        if let graph = try? JSONDecoder().decode(PersistedGraph.self, from: data),
           graph.schemaVersion <= PersistedGraph.currentSchemaVersion {
            return .loaded(graph)
        }

        // Unreadable or newer schema. Preserve bytes before anything can replace them.
        let timestamp = Self.formattedTimestamp(from: now())
        let backupURL = url.deletingPathExtension()
            .appendingPathExtension("unreadable-\(timestamp).json")

        do {
            try FileManager.default.createDirectory(
                at: backupURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: backupURL, options: .withoutOverwriting)
            return .unreadablePreserved(backupURL: backupURL)
        } catch {
            return .unreadableBackupFailed(error)
        }
    }

    private static func formattedTimestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        return formatter.string(from: date)
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
