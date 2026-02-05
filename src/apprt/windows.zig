//! Windows Application Runtime (YStty)
//!
//! This module provides the Windows-native application runtime for Ghostty,
//! using Win32 APIs for window management and Direct3D11 for rendering.
//! This is part of the YStty (YoungSecurity TTY) project.
//!
//! Architecture:
//! - Win32 for window creation and event handling
//! - Direct3D11 for GPU-accelerated terminal rendering
//! - ConPTY for Windows pseudo-terminal support
//!
const windows = @This();

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const configpkg = @import("../config.zig");
const inputpkg = @import("../input.zig");
const rendererpkg = @import("../renderer.zig");
const terminalpkg = @import("../terminal/main.zig");
const CoreSurface = @import("../Surface.zig");

pub const App = @import("windows/App.zig");
pub const Surface = @import("windows/Surface.zig");

const log = std.log.scoped(.windows_apprt);

/// Windows API bindings
pub const win32 = @import("../os/windows.zig");

/// HWND handle type
pub const HWND = std.os.windows.HANDLE;

/// Window class name for YStty windows
pub const WINDOW_CLASS_NAME = std.unicode.utf8ToUtf16LeStringLiteral("YSttyWindowClass");

/// Application title
pub const APP_TITLE = std.unicode.utf8ToUtf16LeStringLiteral("YStty - Ghostty for Windows");

/// Must draw from app thread (Win32 message loop requirement)
pub const must_draw_from_app_thread = true;

/// D3D11 device and context are managed per-surface
pub const ThreadLocalData = struct {
    /// The surface that owns this thread-local data
    surface: *Surface,
};

/// Initialize the Windows runtime
pub fn init() !void {
    log.info("Initializing YStty Windows runtime", .{});
}

/// Deinitialize the Windows runtime
pub fn deinit() void {
    log.info("Deinitializing YStty Windows runtime", .{});
}

test {
    _ = App;
    _ = Surface;
}
