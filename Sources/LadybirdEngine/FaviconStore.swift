/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Favicon PNGs on disk, keyed by the engine's SHA-256 hash, so a relaunch shows icons before the engine wakes.
 */

import AppKit
import Foundation

/// One directory of `<sha256>.png` files. The graph already carries `TabDescriptor.faviconRef`, so the file is found
/// by hash alone; nothing here needs the tab or the network.
///
/// Synchronous and main-thread by design (S3). A 32×32 PNG is a few hundred bytes, so the file cost is a read about
/// equal to decoding the icon itself.
///
/// Lives beside the graph rather than in `~/Library/Caches`: these icons are what a restored, unloaded tab draws,
/// and macOS is free to purge Caches under disk pressure, which would silently undo exactly that.
public struct FaviconStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/LadybirdMac/Favicons`
    public static func applicationDefault() -> FaviconStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return FaviconStore(directory: base.appendingPathComponent("LadybirdMac/Favicons", isDirectory: true))
    }

    public func image(for hash: String) -> NSImage? {
        guard let url = url(for: hash) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Best effort: a cache that cannot be written only costs a placeholder on the next launch.
    public func store(_ data: Data, for hash: String) {
        guard !data.isEmpty, let url = url(for: hash) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {}
    }

    /// Drops icons no tab references any more, so the directory is bounded by the tab count rather than by history.
    public func prune(keeping hashes: Set<String>) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasSuffix(".png") && !hashes.contains(String(name.dropLast(4))) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// The hash arrives from the ABI, so it is validated as hex: it is about to become a file name.
    private func url(for hash: String) -> URL? {
        guard !hash.isEmpty, hash.allSatisfy(\.isHexDigit) else { return nil }
        return directory.appendingPathComponent("\(hash).png")
    }
}
