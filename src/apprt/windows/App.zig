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
const win32 = windows.win32;

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

/// Configuration
config: *const configpkg.Config,

/// Initialize the Windows application
pub fn init(core_app: *CoreApp, config: *const configpkg.Config) !App {
    const alloc = core_app.alloc;

    log.info("Initializing YStty Windows application", .{});

    // Get the module instance handle
    const hinstance = getModuleHandle() orelse return error.NoModuleHandle;

    // Register the window class
    const window_class = try registerWindowClass(hinstance);

    return App{
        .core_app = core_app,
        .alloc = alloc,
        .window_class = window_class,
        .hinstance = hinstance,
        .should_quit = false,
        .surfaces = .{},
        .config = config,
    };
}

/// Deinitialize the application
pub fn deinit(self: *App) void {
    log.info("Deinitializing YStty Windows application", .{});

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
    _ = try self.createSurface();

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
pub fn createSurface(self: *App) !*Surface {
    const surface = try self.alloc.create(Surface);
    errdefer self.alloc.destroy(surface);

    surface.* = try Surface.init(self);
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
    _ = self;

    // Sleep briefly to avoid busy-waiting
    std.time.sleep(1_000_000); // 1ms
}

/// Request application quit
pub fn quit(self: *App) void {
    self.should_quit = true;
    PostQuitMessage(0);
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
const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.C) LRESULT;

const PM_REMOVE = 0x0001;
const WM_QUIT = 0x0012;
const WM_DESTROY = 0x0002;
const WM_CLOSE = 0x0010;
const WM_SIZE = 0x0005;
const WM_PAINT = 0x000F;
const WM_KEYDOWN = 0x0100;
const WM_KEYUP = 0x0101;
const WM_CHAR = 0x0102;

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

extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.C) BOOL;
extern "user32" fn PeekMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(.C) BOOL;
extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.C) BOOL;
extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.C) LRESULT;
extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(.C) void;
extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.C) LRESULT;
extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.C) u16;
extern "user32" fn UnregisterClassW(lpClassName: [*:0]const u16, hInstance: ?HINSTANCE) callconv(.C) BOOL;
extern "user32" fn LoadCursorW(hInstance: ?HINSTANCE, lpCursorName: [*:0]const u16) callconv(.C) ?HCURSOR;
extern "user32" fn CreateWindowExW(
    dwExStyle: DWORD,
    lpClassName: [*:0]const u16,
    lpWindowName: [*:0]const u16,
    dwStyle: DWORD,
    X: i32,
    Y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: ?HWND,
    hMenu: ?HMENU,
    hInstance: ?HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.C) ?HWND;
extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.C) BOOL;
extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.C) BOOL;
extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.C) BOOL;
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.C) ?HINSTANCE;

const HMENU = std.os.windows.HANDLE;

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
fn windowProc(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.C) LRESULT {
    switch (msg) {
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        WM_CLOSE => {
            _ = DestroyWindow(hwnd);
            return 0;
        },
        WM_PAINT => {
            // TODO: Trigger D3D11 render
            return DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        WM_SIZE => {
            // TODO: Handle resize - update swap chain
            return 0;
        },
        WM_KEYDOWN, WM_KEYUP, WM_CHAR => {
            // TODO: Forward to terminal input handling
            return 0;
        },
        else => return DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

test {
    // Basic compilation test
    _ = App;
}
