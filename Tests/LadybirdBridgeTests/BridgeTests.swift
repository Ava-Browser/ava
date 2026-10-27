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

@Suite("Address bar input resolution")
struct InputResolutionTests {
    @Test("A URL stays a URL")
    func url() {
        #expect(PortApp.resolveUserInput("https://example.com/path?q=1") == "https://example.com/path?q=1")
    }

    @Test("A bare host resolves as a host")
    func bareHost() {
        #expect(PortApp.resolveUserInput("example.com")?.contains("example.com") == true)
    }

    @Test("A host and port are not mistaken for a scheme")
    func hostWithPort() {
        #expect(PortApp.resolveUserInput("localhost:8080")?.contains(":8080") == true)
    }

    @Test("Prose becomes a search URL")
    func search() {
        let resolved = PortApp.resolveUserInput("ladybird browser")
        #expect(resolved?.contains("?q=") == true)
        #expect(resolved?.contains("ladybird%20browser") == true)
    }

    @Test("Surrounding whitespace is ignored")
    func whitespace() {
        #expect(PortApp.resolveUserInput("  example.com\n")?.contains("example.com") == true)
    }
}

@Suite("Select dropdown decoding")
struct SelectDropdownDecodingTests {
    @Test("Options, separators, and groups preserve engine ids")
    func items() {
        let json = #"[{"type":"option","id":1,"label":"Bing","enabled":true,"selected":true},{"type":"separator"},{"type":"group","label":"More","items":[{"type":"option","id":2,"label":"DuckDuckGo","enabled":false,"selected":false}]}]"#
        let decoded = json.withCString { decodeSelectItems($0, json.utf8.count) }
        #expect(decoded == [
            .option(PortSelectOption(id: 1, label: "Bing", enabled: true, selected: true)),
            .separator,
            .group(label: "More", options: [PortSelectOption(id: 2, label: "DuckDuckGo", enabled: false, selected: false)]),
        ])
    }

    @Test("Malformed payload is rejected")
    func malformed() {
        let json = #"[{"type":"option","label":"missing id","enabled":true}]"#
        #expect(json.withCString { decodeSelectItems($0, json.utf8.count) } == nil)
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
