const std = @import("std");

/// Runtime is the runtime to use for Ghostty. All runtimes do not provide
/// equivalent feature sets.
pub const Runtime = enum {
    /// Will not produce an executable at all when `zig build` is called.
    /// This is only useful if you're only interested in the lib only (macOS).
    none,

    /// GTK4. Rich windowed application. This uses a full GObject-based
    /// approach to building the application.
    gtk,

    /// Windows. Native Win32 application with Direct3D11 rendering.
    /// Part of the YStty (YoungSecurity TTY) project.
    windows,

    pub fn default(target: std.Target) Runtime {
        return switch (target.os.tag) {
            // The Linux and FreeBSD default is GTK because it is a full
            // featured application.
            .linux, .freebsd => .gtk,
            // Windows uses the native Win32 runtime with Direct3D11.
            .windows => .windows,
            // Otherwise, we do NONE so we don't create an exe and we create
            // libghostty. On macOS, Xcode is used to build the app that links
            // to libghostty.
            else => .none,
        };
    }
};

test {
    _ = Runtime;
}
