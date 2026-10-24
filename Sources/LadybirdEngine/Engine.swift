import CLadybirdPort

/// Proves the package links against the shim dylib and the C ABI is reachable.
/// Replace with the real session/tab model — this is deliberately not an abstraction.
public func printLinkInformation() {
    // Touching a real symbol is what forces the link. Calling a function would create an engine at
    // import time; reading a struct initializer is enough to prove the dylib resolves.
    var surface = LbSurface()
    surface.painted_width = -1
    print("LadybirdEngine linked against LibPort (LbSurface.painted_width = \(surface.painted_width))")
}
