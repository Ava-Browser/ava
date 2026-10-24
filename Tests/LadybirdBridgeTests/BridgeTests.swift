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

@Suite("Address bar URL normalization")
struct URLNormalizationTests {
    @Test("A bare host gets https, not a guessed scheme")
    func bareHost() {
        #expect(PortApp.normalizedURL("example.com") == "https://example.com")
    }

    @Test("A host:port is not mistaken for a scheme")
    func hostWithPort() {
        // `URL::Parser::basic_parse` would read `localhost` as a scheme here, which is why the known-scheme list is
        // checked rather than "does it contain a colon".
        #expect(PortApp.normalizedURL("localhost:8080") == "https://localhost:8080")
    }

    @Test("Known schemes pass through untouched", arguments: [
        "https://example.com/x?y=1",
        "http://example.com",
        "about:blank",
        "data:text/html,<body>hi</body>",
        "file:///tmp/page.html",
        "view-source:https://example.com",
    ])
    func knownScheme(input: String) {
        #expect(PortApp.normalizedURL(input) == input)
    }

    @Test("Surrounding whitespace is dropped")
    func whitespace() {
        #expect(PortApp.normalizedURL("  example.com\n") == "https://example.com")
    }

    @Test("An unknown scheme is treated as a host, not trusted")
    func unknownScheme() {
        #expect(PortApp.normalizedURL("javascript:alert(1)") == "javascript:alert(1)")
        #expect(PortApp.normalizedURL("ftp://example.com") == "https://ftp://example.com")
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
