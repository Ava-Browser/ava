/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * No window and no engine: this target is the reason the bridge must not import AppKit.
 */

import IOSurface
import Testing

@testable import LadybirdBridge

@Suite("Address bar URL resolution")
struct URLResolutionTests {
    @Test("A bare host gets resolved to https")
    func bareHost() {
        #expect(PortApp.resolveUserInput("example.com") == "https://example.com/")
    }

    @Test("A host:port is resolved")
    func hostWithPort() {
        #expect(PortApp.resolveUserInput("localhost:8080") == "http://localhost:8080/")
    }

    @Test("Known schemes pass through untouched", arguments: [
        ("https://example.com/x?y=1", "https://example.com/x?y=1"),
        ("http://example.com", "http://example.com/"),
        ("about:blank", "about:blank"),
        ("data:text/html,<body>hi</body>", "data:text/html,<body>hi</body>"),
        ("file:///tmp/page.html", "file:///tmp/page.html"),
    ])
    func knownScheme(input: String, expected: String) {
        #expect(PortApp.resolveUserInput(input) == expected)
    }

    @Test("Surrounding whitespace is dropped")
    func whitespace() {
        #expect(PortApp.resolveUserInput("  example.com\n") == "https://example.com/")
    }

    @Test("Search queries resolve to search engine URL")
    func searchResolution() {
        // Query text is transformed into a search URL containing the query parameter
        let resolved = PortApp.resolveUserInput("ladybird browser")
        #expect(resolved?.contains("ladybird%20browser") == true || resolved?.contains("ladybird+browser") == true)
    }
}

@Suite("Surface ref conversion")
struct SurfaceRefTests {
    /// The one place a bare `void*` becomes a CF type (S1). Round-trips a real IOSurface so the cast is exercised
    /// rather than merely compiled.
    @Test("The borrowed pointer resolves back to the same IOSurface")
    func refRoundTrip() {
        let surface = IOSurface(properties: [
            .width: 4,
            .height: 4,
            .bytesPerElement: 4,
        ])
        let original = try! #require(surface)

        let portSurface = PortSurface(
            iosurface: Unmanaged.passUnretained(original).toOpaque(),
            paintedWidth: 4,
            paintedHeight: 4,
            surfaceWidth: 4,
            surfaceHeight: 4
        )
        #expect(CFEqual(portSurface.ref, original))
    }
}
