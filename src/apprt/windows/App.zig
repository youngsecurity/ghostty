//! Windows Application
//!
//! This is the main application struct for the Windows runtime. It manages
//! the Win32 message loop and coordinates all surfaces (terminal windows).
//!
const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const apprt = @import("../../apprt.zig");
const configpkg = @import("../../config.zig");
const input = @import("../../input.zig");
const CoreApp = @import("../../App.zig");
const CoreSurface = @import("../../Surface.zig");

const Surface = @import("Surface.zig");
const windows = @import("../windows.zig");

const log = std.log.scoped(.windows_app);

/// Core Ghostty application
core_app: *CoreApp,

/// Allocator for app-level allocations
alloc: Allocator,

/// Window class atom (registered once per process)
window_class: u16,

/// Application instance handle
hinstance: std.os.windows.HINSTANCE,

/// Flag to signal the app should quit
should_quit: bool,

/// List of active surfaces
surfaces: std.ArrayListUnmanaged(*Surface),

/// Initialize the Windows application
/// This matches the interface expected by main_ghostty.zig
pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;
    const alloc = core_app.alloc;

    log.info("Initializing YStty Windows application", .{});

    // Get the module instance handle
    const hinstance = getModuleHandle() orelse return error.NoModuleHandle;

    // Register the window class
    const window_class = try registerWindowClass(hinstance);

    self.* = App{
        .core_app = core_app,
        .alloc = alloc,
        .window_class = window_class,
        .hinstance = hinstance,
        .should_quit = false,
        .surfaces = .{},
    };
}

/// Terminate the application (matches apprt interface)
pub fn terminate(self: *App) void {
    log.info("Terminating YStty Windows application", .{});

    // Close all surfaces
    for (self.surfaces.items) |surface| {
        surface.deinit();
        self.alloc.destroy(surface);
    }
    self.surfaces.deinit(self.alloc);

    // Unregister window class
    unregisterWindowClass(self.window_class, self.hinstance);
}

/// Run the application main loop
pub fn run(self: *App) !void {
    log.info("Starting YStty main loop", .{});

    // Create the initial surface/window
    _ = try self.createSurface(.{});

    // Win32 message loop
    while (!self.should_quit) {
        var msg: MSG = undefined;

        // Process all pending messages
        while (PeekMessageW(&msg, null, 0, 0, PM_REMOVE) != 0) {
            if (msg.message == WM_QUIT) {
                self.should_quit = true;
                break;
            }

            _ = TranslateMessage(&msg);
            _ = DispatchMessageW(&msg);
        }

        // If no messages, let the core app tick
        if (!self.should_quit) {
            try self.tick();
        }
    }

    log.info("YStty main loop ended", .{});
}

/// Create a new terminal surface/window
pub fn createSurface(self: *App, opts: Surface.Options) !*Surface {
    const surface = try self.alloc.create(Surface);
    errdefer self.alloc.destroy(surface);

    try surface.init(self, opts);
    errdefer surface.deinit();

    try self.surfaces.append(self.alloc, surface);

    return surface;
}

/// Remove a surface from tracking (called when surface is closed)
pub fn removeSurface(self: *App, surface: *Surface) void {
    for (self.surfaces.items, 0..) |s, i| {
        if (s == surface) {
            _ = self.surfaces.swapRemove(i);
            break;
        }
    }

    // If no more surfaces, quit the app
    if (self.surfaces.items.len == 0) {
        self.should_quit = true;
    }
}

/// Tick the application (process pending work)
fn tick(self: *App) !void {
    // Process any pending core app work
    self.core_app.tick(self);

    // Render all surfaces
    for (self.surfaces.items) |surface| {
        surface.render() catch |err| {
            log.warn("Render failed: {}", .{err});
        };
    }

    // Sleep briefly to avoid busy-waiting (target ~60fps)
    std.time.sleep(16_000_000); // ~16ms
}

/// Request application quit
pub fn quit(self: *App) void {
    self.should_quit = true;
    PostQuitMessage(0);
}

/// Perform an action (called by surfaces or terminal)
pub fn performAction(
    self: *App,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool {
    switch (action) {
        .new_window => {
            _ = self.createSurface(.{}) catch |err| {
                log.err("Failed to create new window: {}", .{err});
                return false;
            };
            return true;
        },
        .close_surface => {
            _ = value;
            switch (target) {
                .focused => {
                    // Close the focused surface
                    if (self.core_app.focusedSurface()) |focused| {
                        focused.close(false);
                    }
                },
                .surface => |surface| {
                    surface.close(false);
                },
            }
            return true;
        },
        .quit => {
            _ = value;
            self.quit();
            return true;
        },
        .quit_timer => {
            _ = value;
            // Windows doesn't implement quit timer yet, just ignore
            return false;
        },
        else => {
            _ = value;
            log.debug("Unhandled action: {s}", .{@tagName(action)});
            return false;
        },
    }
}

/// Wakeup the event loop (for cross-thread signaling)
pub fn wakeup(self: *App) void {
    _ = self;
    // TODO: Use PostThreadMessage or similar to wake up the message loop
}

/// Perform IPC action. Windows doesn't support IPC yet.
pub fn performIpc(
    _: Allocator,
    _: apprt.ipc.Target,
    comptime action: apprt.ipc.Action.Key,
    _: apprt.ipc.Action.Value(action),
) !bool {
    return false;
}

// =============================================================================
// Win32 Bindings
// =============================================================================

const HINSTANCE = std.os.windows.HINSTANCE;
const HWND = std.os.windows.HANDLE;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;
const UINT = u32;
const DWORD = u32;
const BOOL = i32;
const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.c) LRESULT;

const PM_REMOVE = 0x0001;
const WM_QUIT = 0x0012;
const WM_DESTROY = 0x0002;
const WM_CLOSE = 0x0010;
const WM_SIZE = 0x0005;
const WM_PAINT = 0x000F;
const WM_KEYDOWN = 0x0100;
const WM_KEYUP = 0x0101;
const WM_CHAR = 0x0102;
const WM_MOUSEMOVE = 0x0200;
const WM_LBUTTONDOWN = 0x0201;
const WM_LBUTTONUP = 0x0202;
const WM_RBUTTONDOWN = 0x0204;
const WM_RBUTTONUP = 0x0205;
const WM_MBUTTONDOWN = 0x0207;
const WM_MBUTTONUP = 0x0208;
const WM_MOUSEWHEEL = 0x020A;
const WM_SETFOCUS = 0x0007;
const WM_KILLFOCUS = 0x0008;

const CS_HREDRAW = 0x0002;
const CS_VREDRAW = 0x0001;
const CS_OWNDC = 0x0020;

const WS_OVERLAPPEDWINDOW = 0x00CF0000;
const WS_VISIBLE = 0x10000000;

const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));

const IDC_ARROW = @as([*:0]const u16, @ptrFromInt(32512));

const MSG = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
};

const POINT = extern struct {
    x: i32,
    y: i32,
};

const WNDCLASSEXW = extern struct {
    cbSize: UINT = @sizeOf(WNDCLASSEXW),
    style: UINT = 0,
    lpfnWndProc: ?WNDPROC = null,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?HINSTANCE = null,
    hIcon: ?HICON = null,
    hCursor: ?HCURSOR = null,
    hbrBackground: ?HBRUSH = null,
    lpszMenuName: ?[*:0]const u16 = null,
    lpszClassName: ?[*:0]const u16 = null,
    hIconSm: ?HICON = null,
};

const HICON = std.os.windows.HANDLE;
const HCURSOR = std.os.windows.HANDLE;
const HBRUSH = std.os.windows.HANDLE;

extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.c) BOOL;
extern "user32" fn PeekMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(.c) BOOL;
extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.c) BOOL;
extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.c) LRESULT;
extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(.c) void;
extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.c) LRESULT;
extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.c) u16;
extern "user32" fn UnregisterClassW(lpClassName: [*:0]const u16, hInstance: ?HINSTANCE) callconv(.c) BOOL;
extern "user32" fn LoadCursorW(hInstance: ?HINSTANCE, lpCursorName: [*:0]const u16) callconv(.c) ?HCURSOR;
extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.c) BOOL;
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.c) ?HINSTANCE;

fn getModuleHandle() ?HINSTANCE {
    return GetModuleHandleW(null);
}

fn registerWindowClass(hinstance: HINSTANCE) !u16 {
    const wc = WNDCLASSEXW{
        .style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC,
        .lpfnWndProc = windowProc,
        .hInstance = hinstance,
        .hCursor = LoadCursorW(null, IDC_ARROW),
        .lpszClassName = windows.WINDOW_CLASS_NAME,
    };

    const atom = RegisterClassExW(&wc);
    if (atom == 0) {
        return error.WindowClassRegistrationFailed;
    }

    return atom;
}

fn unregisterWindowClass(atom: u16, hinstance: HINSTANCE) void {
    _ = atom;
    _ = UnregisterClassW(windows.WINDOW_CLASS_NAME, hinstance);
}

/// Window procedure - handles all window messages
fn windowProc(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT {
    // Get the surface from window user data
    const surface = Surface.fromHwnd(hwnd);

    switch (msg) {
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        WM_CLOSE => {
            if (surface) |s| {
                s.close(false);
            } else {
                _ = DestroyWindow(hwnd);
            }
            return 0;
        },
        WM_SIZE => {
            if (surface) |s| {
                const width: u32 = @intCast(lparam & 0xFFFF);
                const height: u32 = @intCast((lparam >> 16) & 0xFFFF);
                s.handleResize(width, height) catch |err| {
                    log.warn("Resize failed: {}", .{err});
                };
            }
            return 0;
        },
        WM_PAINT => {
            if (surface) |s| {
                s.render() catch |err| {
                    log.warn("Render failed: {}", .{err});
                };
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        WM_KEYDOWN => {
            if (surface) |s| {
                const mods = getModifiers();
                s.handleKeyEvent(.press, @intCast(wparam), 0, mods) catch {};
            }
            return 0;
        },
        WM_KEYUP => {
            if (surface) |s| {
                const mods = getModifiers();
                s.handleKeyEvent(.release, @intCast(wparam), 0, mods) catch {};
            }
            return 0;
        },
        WM_CHAR => {
            if (surface) |s| {
                // Convert UTF-16 codepoint to UTF-8
                var buf: [4]u8 = undefined;
                const codepoint: u21 = @intCast(wparam);
                const len = std.unicode.utf8Encode(codepoint, &buf) catch 0;
                if (len > 0) {
                    s.handleTextInput(buf[0..len]);
                }
            }
            return 0;
        },
        WM_MOUSEMOVE => {
            if (surface) |s| {
                const x: f64 = @floatFromInt(@as(i16, @truncate(lparam)));
                const y: f64 = @floatFromInt(@as(i16, @truncate(lparam >> 16)));
                const mods = getModifiers();
                s.handleMouseMove(x, y, mods);
            }
            return 0;
        },
        WM_LBUTTONDOWN => {
            if (surface) |s| {
                const mods = getModifiers();
                s.handleMouseButton(.press, .left, mods);
            }
            return 0;
        },
        WM_LBUTTONUP => {
            if (surface) |s| {
                const mods = getModifiers();
                s.handleMouseButton(.release, .left, mods);
            }
            return 0;
        },
        WM_RBUTTONDOWN => {
            if (surface) |s| {
                const mods = getModifiers();
                s.handleMouseButton(.press, .right, mods);
            }
            return 0;
        },
        WM_RBUTTONUP => {
            if (surface) |s| {
                const mods = getModifiers();
                s.handleMouseButton(.release, .right, mods);
            }
            return 0;
        },
        WM_MBUTTONDOWN => {
            if (surface) |s| {
                const mods = getModifiers();
                s.handleMouseButton(.press, .middle, mods);
            }
            return 0;
        },
        WM_MBUTTONUP => {
            if (surface) |s| {
                const mods = getModifiers();
                s.handleMouseButton(.release, .middle, mods);
            }
            return 0;
        },
        WM_MOUSEWHEEL => {
            if (surface) |s| {
                const delta: i16 = @bitCast(@as(u16, @truncate(wparam >> 16)));
                const scroll_y: f64 = @as(f64, @floatFromInt(delta)) / 120.0;
                const mods = getModifiers();
                s.handleScroll(0, scroll_y, mods);
            }
            return 0;
        },
        WM_SETFOCUS => {
            if (surface) |s| {
                s.handleFocus(true);
            }
            return 0;
        },
        WM_KILLFOCUS => {
            if (surface) |s| {
                s.handleFocus(false);
            }
            return 0;
        },
        else => return DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

/// Get current modifier key state
fn getModifiers() input.Mods {
    var mods: input.Mods = .{};

    if ((GetKeyState(VK_SHIFT) & 0x8000) != 0) mods.shift = true;
    if ((GetKeyState(VK_CONTROL) & 0x8000) != 0) mods.ctrl = true;
    if ((GetKeyState(VK_MENU) & 0x8000) != 0) mods.alt = true;
    if ((GetKeyState(VK_LWIN) & 0x8000) != 0 or (GetKeyState(VK_RWIN) & 0x8000) != 0) mods.super = true;

    return mods;
}

const VK_SHIFT = 0x10;
const VK_CONTROL = 0x11;
const VK_MENU = 0x12;
const VK_LWIN = 0x5B;
const VK_RWIN = 0x5C;

extern "user32" fn GetKeyState(nVirtKey: i32) callconv(.c) i16;

test {
    _ = App;
}
