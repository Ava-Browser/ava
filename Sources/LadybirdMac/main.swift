/*
 * Temporary entry point. The real app (window, chrome, tabs) belongs to whoever ports the spike's
 * main.swift next — see Documentation/Architecture.md. This exists so the package builds and links
 * against the shim end to end.
 */

import LadybirdEngine

LadybirdEngine.printLinkInformation()
