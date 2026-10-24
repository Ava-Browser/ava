/*
 * Forwarding header for the C ABI.
 *
 * The real header lives in the fork, next to its implementation, because the two must stay in
 * lockstep and the implementation needs the Lagom link line to build. SwiftPM needs a C target to
 * expose a module, so this forwards to it with a path relative to this file.
 */
#pragma once

#include "../../../Extern/ladybird/Libraries/LibPort/ladybird_port.h"
