/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Integration tests link the engine, so they need LADYBIRD_BINARY_PATH and the shim dylib. The URL normalization and
 * surface casts are unit-tested in LadybirdBridgeTests, which needs neither.
 */

import Testing

@testable import LadybirdEngine

// Placeholder until a probe covers something only the real engine can show: creating a tab, or a paint arriving after
// load. Both need helper processes, so they belong in a test that launches them, not here.
