//! Windows Surface
//!
//! A Surface represents a single terminal window on Windows. It manages
//! the Win32 window handle, Direct3D11 swap chain, and terminal state.
//! This integrates with Ghostty's CoreSurface for terminal emulation.
//!
const Surface = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const apprt = @import("../../apprt.zig");
const configpkg = @import("../../config.zig");
const font = @import("../../font/main.zig");
const input = @import("../../input.zig");
const renderer = @import("../../renderer.zig");
const terminalpkg = @import("../../terminal/main.zig");
const CoreSurface = @import("../../Surface.zig");
const CoreApp = @import("../../App.zig");

const App = @import("App.zig");
const windows = @import("../windows.zig");
const internal_os = @import("../../os/main.zig");

const log = std.log.scoped(.windows_surface);

/// Parent application
app: *App,

/// Win32 window handle
hwnd: ?HWND,

/// Direct3D11 device (created per surface for simplicity)
d3d_device: ?*anyopaque,

/// Direct3D11 device context
d3d_context: ?*anyopaque,

/// DXGI swap chain
swap_chain: ?*anyopaque,

/// Render target view
render_target: ?*anyopaque,

/// Core Ghostty surface (terminal emulator)
core_surface: CoreSurface,

/// Surface dimensions in pixels
size: apprt.SurfaceSize,

/// Content scale (DPI scaling)
content_scale: apprt.ContentScale,

/// Current cursor position
cursor_pos: apprt.CursorPos,

/// Current window title
title: ?[:0]const u8,

/// Surface initialization options
pub const Options = struct {
    /// The scale factor of the screen (DPI)
    scale_factor: f64 = 1.0,

    /// The font size to inherit (0 = use default)
    font_size: f32 = 0,

    /// Working directory to start in
    working_directory: ?[:0]const u8 = null,

    /// Context for the new surface (window/tab/split)
    context: apprt.surface.NewSurfaceContext = .window,
};

/// Initialize a new surface
pub fn init(self: *Surface, app: *App, opts: Options) !void {
    log.info("Creating YStty surface", .{});

    // Initialize basic state
    self.* = .{
        .app = app,
        .hwnd = null,
        .d3d_device = null,
        .d3d_context = null,
        .swap_chain = null,
        .render_target = null,
        .core_surface = undefined,
        .size = .{ .width = 1280, .height = 720 },
        .content_scale = .{
            .x = @floatCast(opts.scale_factor),
            .y = @floatCast(opts.scale_factor),
        },
        .cursor_pos = .{ .x = -1, .y = -1 },
        .title = null,
    };

    // Create the Win32 window
    self.hwnd = createWindow(app, self) orelse return error.WindowCreationFailed;
    errdefer {
        if (self.hwnd) |hwnd| _ = DestroyWindow(hwnd);
    }

    // Get initial window size
    var rect: RECT = undefined;
    if (GetClientRect(self.hwnd.?, &rect) != 0) {
        self.size.width = @intCast(rect.right - rect.left);
        self.size.height = @intCast(rect.bottom - rect.top);
    }

    // Initialize Direct3D11
    try self.initD3D11();
    errdefer self.deinitD3D11();

    // Add ourselves to the list of surfaces on the app
    try app.core_app.addSurface(self);
    errdefer app.core_app.deleteSurface(self);

    // Create a configuration for this surface
    var config = try apprt.surface.newConfig(app.core_app, &app.config, opts.context);
    defer config.deinit();

    // Set working directory if provided
    if (opts.working_directory) |wd| {
        config.@"working-directory" = wd;
    }

    // Initialize the core surface (terminal emulator)
    try self.core_surface.init(
        app.core_app.alloc,
        &config,
        app.core_app,
        app,
        self,
    );
    errdefer self.core_surface.deinit();

    // If font size was specified, set it
    if (opts.font_size != 0) {
        var font_size = self.core_surface.font_size;
        font_size.points = opts.font_size;
        try self.core_surface.setFontSize(font_size);
    }

    // Show the window
    _ = ShowWindow(self.hwnd.?, SW_SHOW);
    _ = UpdateWindow(self.hwnd.?);

    log.info("YStty surface created: {}x{}", .{ self.size.width, self.size.height });
}

/// Deinitialize the surface
pub fn deinit(self: *Surface) void {
    log.info("Destroying YStty surface", .{});

    // Free the title if we have one
    if (self.title) |t| {
        self.app.core_app.alloc.free(t);
        self.title = null;
    }

    // Remove ourselves from the app's surface list
    self.app.core_app.deleteSurface(self);

    // Deinitialize the core surface
    self.core_surface.deinit();

    // Cleanup D3D11
    self.deinitD3D11();

    // Destroy the window
    if (self.hwnd) |hwnd| {
        _ = DestroyWindow(hwnd);
        self.hwnd = null;
    }
}

// =============================================================================
// CoreSurface Interface Methods
// These are called by the core terminal emulator
// =============================================================================

/// Get the core surface
pub fn core(self: *Surface) *CoreSurface {
    return &self.core_surface;
}

/// Get the runtime app
pub fn rtApp(self: *const Surface) *App {
    return self.app;
}

/// Get the content scale (DPI scaling)
pub fn getContentScale(self: *const Surface) !apprt.ContentScale {
    return self.content_scale;
}

/// Get the surface size in pixels
pub fn getSize(self: *const Surface) !apprt.SurfaceSize {
    return self.size;
}

/// Get the current cursor position
pub fn getCursorPos(self: *const Surface) !apprt.CursorPos {
    return self.cursor_pos;
}

/// Get the current window title
pub fn getTitle(self: *Surface) ?[:0]const u8 {
    return self.title;
}

/// Check if a clipboard type is supported
pub fn supportsClipboard(self: *const Surface, clipboard_type: apprt.Clipboard) bool {
    _ = self;
    return switch (clipboard_type) {
        .standard => true,
        .selection, .primary => false, // Windows doesn't have X11-style selection
    };
}

/// Request clipboard contents
pub fn clipboardRequest(
    self: *Surface,
    clipboard_type: apprt.Clipboard,
    state: apprt.ClipboardRequest,
) !bool {
    _ = state;

    if (!self.supportsClipboard(clipboard_type)) {
        return false;
    }

    // TODO: Implement Windows clipboard reading
    // - OpenClipboard(hwnd)
    // - GetClipboardData(CF_UNICODETEXT)
    // - CloseClipboard()
    // - Call state.complete() with the data

    return false;
}

/// Write to the clipboard
pub fn setClipboard(
    self: *const Surface,
    clipboard_type: apprt.Clipboard,
    contents: []const apprt.ClipboardContent,
    confirm: bool,
) !void {
    _ = contents;
    _ = confirm;

    if (!self.supportsClipboard(clipboard_type)) {
        return;
    }

    // TODO: Implement Windows clipboard writing
    // - OpenClipboard(hwnd)
    // - EmptyClipboard()
    // - GlobalAlloc + copy data
    // - SetClipboardData(CF_UNICODETEXT, hMem)
    // - CloseClipboard()
}

/// Close the surface
pub fn close(self: *const Surface, process_alive: bool) void {
    _ = process_alive;

    if (self.hwnd) |hwnd| {
        _ = PostMessageW(hwnd, WM_CLOSE, 0, 0);
    }
}

/// Perform an action requested by the terminal
pub fn performAction(
    self: *Surface,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool {
    return self.app.performAction(target, action, value);
}

/// Get the default environment for terminal IO
pub fn defaultTermioEnv(self: *const Surface) !std.process.EnvMap {
    const alloc = self.app.core_app.alloc;
    return try internal_os.getEnvMap(alloc);
}

/// Get the cgroup path (not applicable on Windows)
pub fn cgroupPath(self: *const Surface) ?[]const u8 {
    _ = self;
    return null;
}

// =============================================================================
// Input Handling
// =============================================================================

/// Handle a key event from Win32
pub fn handleKeyEvent(
    self: *Surface,
    action: input.Action,
    vk: u32,
    scancode: u32,
    mods: input.Mods,
) !void {
    // Convert Win32 virtual key to Ghostty physical key
    const physical_key = mapVirtualKey(vk, scancode);

    const event = input.KeyEvent{
        .action = action,
        .key = physical_key,
        .mods = mods,
        .consumed_mods = .{},
        .composing = false,
        .utf8 = "",
        .unshifted_codepoint = 0,
    };

    _ = try self.core_surface.keyCallback(event);
}

/// Handle a mouse button event from Win32
pub fn handleMouseButton(
    self: *Surface,
    action: input.MouseButtonState,
    button: input.MouseButton,
    mods: input.Mods,
) void {
    _ = self.core_surface.mouseButtonCallback(action, button, mods) catch |err| {
        log.warn("Mouse button callback failed: {}", .{err});
    };
}

/// Handle mouse movement from Win32
pub fn handleMouseMove(self: *Surface, x: f64, y: f64, mods: input.Mods) void {
    self.cursor_pos = .{ .x = @floatCast(x), .y = @floatCast(y) };
    self.core_surface.cursorPosCallback(self.cursor_pos, mods) catch |err| {
        log.warn("Cursor pos callback failed: {}", .{err});
    };
}

/// Handle mouse scroll from Win32
pub fn handleScroll(self: *Surface, x: f64, y: f64, mods: input.Mods) void {
    // Convert Mods to ScrollMods
    const scroll_mods: input.ScrollMods = .{
        .shift = mods.shift,
        .ctrl = mods.ctrl,
        .alt = mods.alt,
        .precision = false,
    };
    self.core_surface.scrollCallback(x, y, scroll_mods);
}

/// Handle focus change
pub fn handleFocus(self: *Surface, focused: bool) void {
    self.core_surface.focusCallback(focused) catch |err| {
        log.warn("Focus callback failed: {}", .{err});
    };
}

/// Handle window resize
pub fn handleResize(self: *Surface, width: u32, height: u32) !void {
    if (width == 0 or height == 0) return;

    log.info("Resizing surface: {}x{} -> {}x{}", .{
        self.size.width,
        self.size.height,
        width,
        height,
    });

    self.size.width = width;
    self.size.height = height;

    // Resize D3D11 swap chain
    try self.resizeSwapChain(width, height);

    // Notify the core surface
    try self.core_surface.sizeCallback(self.size);
}

/// Handle text input (for IME support)
pub fn handleTextInput(self: *Surface, text: []const u8) !void {
    try self.core_surface.textCallback(text);
}

// =============================================================================
// Virtual Key Mapping
// =============================================================================

fn mapVirtualKey(vk: u32, scancode: u32) input.Key {
    _ = scancode;

    return switch (vk) {
        // Letters (VK_A through VK_Z: 0x41-0x5A)
        0x41 => .key_a,
        0x42 => .key_b,
        0x43 => .key_c,
        0x44 => .key_d,
        0x45 => .key_e,
        0x46 => .key_f,
        0x47 => .key_g,
        0x48 => .key_h,
        0x49 => .key_i,
        0x4A => .key_j,
        0x4B => .key_k,
        0x4C => .key_l,
        0x4D => .key_m,
        0x4E => .key_n,
        0x4F => .key_o,
        0x50 => .key_p,
        0x51 => .key_q,
        0x52 => .key_r,
        0x53 => .key_s,
        0x54 => .key_t,
        0x55 => .key_u,
        0x56 => .key_v,
        0x57 => .key_w,
        0x58 => .key_x,
        0x59 => .key_y,
        0x5A => .key_z,

        // Numbers (VK_0 through VK_9: 0x30-0x39)
        0x30 => .digit_0,
        0x31 => .digit_1,
        0x32 => .digit_2,
        0x33 => .digit_3,
        0x34 => .digit_4,
        0x35 => .digit_5,
        0x36 => .digit_6,
        0x37 => .digit_7,
        0x38 => .digit_8,
        0x39 => .digit_9,

        // Function keys (VK_F1 through VK_F12: 0x70-0x7B)
        0x70 => .f1,
        0x71 => .f2,
        0x72 => .f3,
        0x73 => .f4,
        0x74 => .f5,
        0x75 => .f6,
        0x76 => .f7,
        0x77 => .f8,
        0x78 => .f9,
        0x79 => .f10,
        0x7A => .f11,
        0x7B => .f12,

        // Control keys
        0x08 => .backspace, // VK_BACK
        0x09 => .tab, // VK_TAB
        0x0D => .enter, // VK_RETURN
        0x1B => .escape, // VK_ESCAPE
        0x20 => .space, // VK_SPACE
        0x2E => .delete, // VK_DELETE
        0x2D => .insert, // VK_INSERT
        0x24 => .home, // VK_HOME
        0x23 => .end, // VK_END
        0x21 => .page_up, // VK_PRIOR
        0x22 => .page_down, // VK_NEXT

        // Arrow keys
        0x25 => .arrow_left, // VK_LEFT
        0x26 => .arrow_up, // VK_UP
        0x27 => .arrow_right, // VK_RIGHT
        0x28 => .arrow_down, // VK_DOWN

        // Modifiers
        0x10 => .shift_left, // VK_SHIFT (generic, left assumed)
        0x11 => .control_left, // VK_CONTROL (generic, left assumed)
        0x12 => .alt_left, // VK_MENU (generic, left assumed)

        else => .unidentified,
    };
}

// =============================================================================
// Direct3D11 Management
// =============================================================================

fn initD3D11(self: *Surface) !void {
    const hwnd = self.hwnd orelse return error.NoWindow;

    log.info("Initializing Direct3D11 for surface", .{});

    var swap_chain_desc = DXGI_SWAP_CHAIN_DESC{
        .BufferDesc = .{
            .Width = self.size.width,
            .Height = self.size.height,
            .RefreshRate = .{ .Numerator = 60, .Denominator = 1 },
            .Format = DXGI_FORMAT_R8G8B8A8_UNORM,
            .ScanlineOrdering = DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED,
            .Scaling = DXGI_MODE_SCALING_UNSPECIFIED,
        },
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT,
        .BufferCount = 2,
        .OutputWindow = hwnd,
        .Windowed = 1,
        .SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD,
        .Flags = 0,
    };

    var device: ?*ID3D11Device = null;
    var context: ?*ID3D11DeviceContext = null;
    var swap_chain: ?*IDXGISwapChain = null;

    const feature_levels = [_]D3D_FEATURE_LEVEL{
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
    };

    var flags: UINT = 0;
    if (builtin.mode == .Debug) {
        flags |= D3D11_CREATE_DEVICE_DEBUG;
    }

    const hr = D3D11CreateDeviceAndSwapChain(
        null,
        D3D_DRIVER_TYPE_HARDWARE,
        null,
        flags,
        &feature_levels,
        feature_levels.len,
        D3D11_SDK_VERSION,
        &swap_chain_desc,
        &swap_chain,
        &device,
        null,
        &context,
    );

    if (hr < 0) {
        log.err("D3D11CreateDeviceAndSwapChain failed: 0x{x}", .{@as(u32, @bitCast(hr))});
        return error.D3D11InitFailed;
    }

    self.d3d_device = device;
    self.d3d_context = context;
    self.swap_chain = swap_chain;

    try self.createRenderTarget();

    log.info("Direct3D11 initialized successfully", .{});
}

fn createRenderTarget(self: *Surface) !void {
    const swap_chain: *IDXGISwapChain = @ptrCast(@alignCast(self.swap_chain orelse return error.NoSwapChain));
    const device: *ID3D11Device = @ptrCast(@alignCast(self.d3d_device orelse return error.NoDevice));

    var back_buffer: ?*ID3D11Texture2D = null;
    var hr = swap_chain.vtable.GetBuffer(swap_chain, 0, &IID_ID3D11Texture2D, @ptrCast(&back_buffer));
    if (hr < 0) {
        return error.GetBufferFailed;
    }
    defer _ = back_buffer.?.vtable.Release(back_buffer.?);

    var rtv: ?*ID3D11RenderTargetView = null;
    hr = device.vtable.CreateRenderTargetView(device, @ptrCast(back_buffer), null, &rtv);
    if (hr < 0) {
        return error.CreateRenderTargetViewFailed;
    }

    self.render_target = rtv;
}

fn releaseRenderTarget(self: *Surface) void {
    if (self.render_target) |rt| {
        const rtv: *ID3D11RenderTargetView = @ptrCast(@alignCast(rt));
        _ = rtv.vtable.Release(rtv);
        self.render_target = null;
    }
}

fn resizeSwapChain(self: *Surface, width: u32, height: u32) !void {
    self.releaseRenderTarget();

    if (self.swap_chain) |sc| {
        const swap_chain: *IDXGISwapChain = @ptrCast(@alignCast(sc));
        const hr = swap_chain.vtable.ResizeBuffers(swap_chain, 0, width, height, DXGI_FORMAT_UNKNOWN, 0);
        if (hr < 0) {
            log.err("ResizeBuffers failed: 0x{x}", .{@as(u32, @bitCast(hr))});
            return error.ResizeBuffersFailed;
        }
    }

    try self.createRenderTarget();
}

fn deinitD3D11(self: *Surface) void {
    log.info("Deinitializing Direct3D11", .{});

    self.releaseRenderTarget();

    if (self.swap_chain) |sc| {
        const swap_chain: *IDXGISwapChain = @ptrCast(@alignCast(sc));
        _ = swap_chain.vtable.Release(swap_chain);
        self.swap_chain = null;
    }

    if (self.d3d_context) |ctx| {
        const context: *ID3D11DeviceContext = @ptrCast(@alignCast(ctx));
        _ = context.vtable.Release(context);
        self.d3d_context = null;
    }

    if (self.d3d_device) |dev| {
        const device: *ID3D11Device = @ptrCast(@alignCast(dev));
        _ = device.vtable.Release(device);
        self.d3d_device = null;
    }
}

/// Render a frame
pub fn render(self: *Surface) !void {
    const context: *ID3D11DeviceContext = @ptrCast(@alignCast(self.d3d_context orelse return));
    const swap_chain: *IDXGISwapChain = @ptrCast(@alignCast(self.swap_chain orelse return));
    const rtv: *ID3D11RenderTargetView = @ptrCast(@alignCast(self.render_target orelse return));

    // Clear to a dark background color
    const clear_color = [4]f32{ 0.1, 0.1, 0.1, 1.0 };
    context.vtable.ClearRenderTargetView(context, rtv, &clear_color);

    // TODO: Call core_surface.draw() to render terminal cells

    // Present
    const hr = swap_chain.vtable.Present(swap_chain, 1, 0);
    if (hr < 0) {
        log.warn("Present failed: 0x{x}", .{@as(u32, @bitCast(hr))});
    }
}

// =============================================================================
// Win32 Bindings
// =============================================================================

const HWND = std.os.windows.HANDLE;
const HINSTANCE = std.os.windows.HINSTANCE;
const UINT = u32;
const DWORD = u32;
const BOOL = i32;
const HRESULT = i32;
const WPARAM = usize;
const LPARAM = isize;
const GUID = extern struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };

const SW_SHOW = 5;
const WM_CLOSE = 0x0010;

const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

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
) callconv(.c) ?HWND;
extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.c) BOOL;
extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.c) BOOL;
extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.c) BOOL;
extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.c) BOOL;
extern "user32" fn PostMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.c) BOOL;
extern "user32" fn SetWindowLongPtrW(hWnd: HWND, nIndex: i32, dwNewLong: isize) callconv(.c) isize;
extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: i32) callconv(.c) isize;

const HMENU = std.os.windows.HANDLE;
const GWLP_USERDATA = -21;

const WS_OVERLAPPEDWINDOW = 0x00CF0000;
const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));

fn createWindow(app: *App, surface: *Surface) ?HWND {
    const hwnd = CreateWindowExW(
        0,
        windows.WINDOW_CLASS_NAME,
        windows.APP_TITLE,
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        1280,
        720,
        null,
        null,
        app.hinstance,
        null,
    );

    if (hwnd) |h| {
        // Store the surface pointer in the window's user data
        _ = SetWindowLongPtrW(h, GWLP_USERDATA, @bitCast(@intFromPtr(surface)));
    }

    return hwnd;
}

/// Get the Surface from a window handle
pub fn fromHwnd(hwnd: HWND) ?*Surface {
    const ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    if (ptr == 0) return null;
    return @ptrFromInt(@as(usize, @bitCast(ptr)));
}

// =============================================================================
// Direct3D11 Bindings
// =============================================================================

const D3D_DRIVER_TYPE_HARDWARE = 1;
const D3D_FEATURE_LEVEL_11_0 = 0xb000;
const D3D_FEATURE_LEVEL_11_1 = 0xb100;
const D3D_FEATURE_LEVEL = u32;

const D3D11_SDK_VERSION = 7;
const D3D11_CREATE_DEVICE_DEBUG = 0x02;

const DXGI_FORMAT_R8G8B8A8_UNORM = 28;
const DXGI_FORMAT_UNKNOWN = 0;
const DXGI_USAGE_RENDER_TARGET_OUTPUT = 0x00000020;
const DXGI_SWAP_EFFECT_FLIP_DISCARD = 4;
const DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED = 0;
const DXGI_MODE_SCALING_UNSPECIFIED = 0;

const DXGI_RATIONAL = extern struct {
    Numerator: UINT,
    Denominator: UINT,
};

const DXGI_MODE_DESC = extern struct {
    Width: UINT,
    Height: UINT,
    RefreshRate: DXGI_RATIONAL,
    Format: UINT,
    ScanlineOrdering: UINT,
    Scaling: UINT,
};

const DXGI_SAMPLE_DESC = extern struct {
    Count: UINT,
    Quality: UINT,
};

const DXGI_SWAP_CHAIN_DESC = extern struct {
    BufferDesc: DXGI_MODE_DESC,
    SampleDesc: DXGI_SAMPLE_DESC,
    BufferUsage: UINT,
    BufferCount: UINT,
    OutputWindow: HWND,
    Windowed: BOOL,
    SwapEffect: UINT,
    Flags: UINT,
};

const IID_ID3D11Texture2D = GUID{
    .Data1 = 0x6f15aaf2,
    .Data2 = 0xd208,
    .Data3 = 0x4e89,
    .Data4 = .{ 0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c },
};

const ID3D11DeviceVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11Device, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11Device) callconv(.c) u32,
    Release: *const fn (*ID3D11Device) callconv(.c) u32,
    CreateBuffer: *const anyopaque,
    CreateTexture1D: *const anyopaque,
    CreateTexture2D: *const anyopaque,
    CreateTexture3D: *const anyopaque,
    CreateShaderResourceView: *const anyopaque,
    CreateUnorderedAccessView: *const anyopaque,
    CreateRenderTargetView: *const fn (*ID3D11Device, *anyopaque, ?*anyopaque, *?*ID3D11RenderTargetView) callconv(.c) HRESULT,
};

const ID3D11Device = extern struct {
    vtable: *const ID3D11DeviceVtbl,
};

const ID3D11DeviceContextVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11DeviceContext, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11DeviceContext) callconv(.c) u32,
    Release: *const fn (*ID3D11DeviceContext) callconv(.c) u32,
    GetDevice: *const anyopaque,
    GetPrivateData: *const anyopaque,
    SetPrivateData: *const anyopaque,
    SetPrivateDataInterface: *const anyopaque,
    VSSetConstantBuffers: *const anyopaque,
    PSSetShaderResources: *const anyopaque,
    PSSetShader: *const anyopaque,
    PSSetSamplers: *const anyopaque,
    VSSetShader: *const anyopaque,
    DrawIndexed: *const anyopaque,
    Draw: *const anyopaque,
    Map: *const anyopaque,
    Unmap: *const anyopaque,
    PSSetConstantBuffers: *const anyopaque,
    IASetInputLayout: *const anyopaque,
    IASetVertexBuffers: *const anyopaque,
    IASetIndexBuffer: *const anyopaque,
    DrawIndexedInstanced: *const anyopaque,
    DrawInstanced: *const anyopaque,
    GSSetConstantBuffers: *const anyopaque,
    GSSetShader: *const anyopaque,
    IASetPrimitiveTopology: *const anyopaque,
    VSSetShaderResources: *const anyopaque,
    VSSetSamplers: *const anyopaque,
    Begin: *const anyopaque,
    End: *const anyopaque,
    GetData: *const anyopaque,
    SetPredication: *const anyopaque,
    GSSetShaderResources: *const anyopaque,
    GSSetSamplers: *const anyopaque,
    OMSetRenderTargets: *const anyopaque,
    OMSetRenderTargetsAndUnorderedAccessViews: *const anyopaque,
    OMSetBlendState: *const anyopaque,
    OMSetDepthStencilState: *const anyopaque,
    SOSetTargets: *const anyopaque,
    DrawAuto: *const anyopaque,
    DrawIndexedInstancedIndirect: *const anyopaque,
    DrawInstancedIndirect: *const anyopaque,
    Dispatch: *const anyopaque,
    DispatchIndirect: *const anyopaque,
    RSSetState: *const anyopaque,
    RSSetViewports: *const anyopaque,
    RSSetScissorRects: *const anyopaque,
    CopySubresourceRegion: *const anyopaque,
    CopyResource: *const anyopaque,
    UpdateSubresource: *const anyopaque,
    CopyStructureCount: *const anyopaque,
    ClearRenderTargetView: *const fn (*ID3D11DeviceContext, *ID3D11RenderTargetView, *const [4]f32) callconv(.c) void,
};

const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVtbl,
};

const ID3D11RenderTargetViewVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11RenderTargetView, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11RenderTargetView) callconv(.c) u32,
    Release: *const fn (*ID3D11RenderTargetView) callconv(.c) u32,
};

const ID3D11RenderTargetView = extern struct {
    vtable: *const ID3D11RenderTargetViewVtbl,
};

const ID3D11Texture2DVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11Texture2D, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11Texture2D) callconv(.c) u32,
    Release: *const fn (*ID3D11Texture2D) callconv(.c) u32,
};

const ID3D11Texture2D = extern struct {
    vtable: *const ID3D11Texture2DVtbl,
};

const IDXGISwapChainVtbl = extern struct {
    QueryInterface: *const fn (*IDXGISwapChain, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*IDXGISwapChain) callconv(.c) u32,
    Release: *const fn (*IDXGISwapChain) callconv(.c) u32,
    SetPrivateData: *const anyopaque,
    SetPrivateDataInterface: *const anyopaque,
    GetPrivateData: *const anyopaque,
    GetParent: *const anyopaque,
    GetDevice: *const anyopaque,
    Present: *const fn (*IDXGISwapChain, UINT, UINT) callconv(.c) HRESULT,
    GetBuffer: *const fn (*IDXGISwapChain, UINT, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    SetFullscreenState: *const anyopaque,
    GetFullscreenState: *const anyopaque,
    GetDesc: *const anyopaque,
    ResizeBuffers: *const fn (*IDXGISwapChain, UINT, UINT, UINT, UINT, UINT) callconv(.c) HRESULT,
};

const IDXGISwapChain = extern struct {
    vtable: *const IDXGISwapChainVtbl,
};

extern "d3d11" fn D3D11CreateDeviceAndSwapChain(
    pAdapter: ?*anyopaque,
    DriverType: u32,
    Software: ?*anyopaque,
    Flags: UINT,
    pFeatureLevels: [*]const D3D_FEATURE_LEVEL,
    FeatureLevels: UINT,
    SDKVersion: UINT,
    pSwapChainDesc: *const DXGI_SWAP_CHAIN_DESC,
    ppSwapChain: *?*IDXGISwapChain,
    ppDevice: *?*ID3D11Device,
    pFeatureLevel: ?*D3D_FEATURE_LEVEL,
    ppImmediateContext: *?*ID3D11DeviceContext,
) callconv(.c) HRESULT;

test {
    _ = Surface;
}
