/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import CLadybirdPort

// The header is a plain C module: importing it is all the bridging the shim needs. This file only has to exist so
// the target is non-empty and the symbols get referenced at link time.
