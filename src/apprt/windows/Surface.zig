//! Windows Surface
//!
//! A Surface represents a single terminal window on Windows. It manages
//! the Win32 window handle, Direct3D11 swap chain, and terminal state.
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

const App = @import("App.zig");
const windows = @import("../windows.zig");

const log = std.log.scoped(.windows_surface);

/// Parent application
app: *App,

/// Win32 window handle
hwnd: ?windows.HWND,

/// Direct3D11 device (created per surface for simplicity)
d3d_device: ?*anyopaque,

/// Direct3D11 device context
d3d_context: ?*anyopaque,

/// DXGI swap chain
swap_chain: ?*anyopaque,

/// Render target view
render_target: ?*anyopaque,

/// Core Ghostty surface
core_surface: ?*CoreSurface,

/// Surface dimensions
width: u32,
height: u32,

/// Content scale (DPI scaling)
content_scale: f32,

/// Initialize a new surface
pub fn init(app: *App) !Surface {
    log.info("Creating YStty surface", .{});

    // Create the Win32 window
    const hwnd = createWindow(app) orelse return error.WindowCreationFailed;
    errdefer _ = DestroyWindow(hwnd);

    // Show the window
    _ = ShowWindow(hwnd, SW_SHOW);
    _ = UpdateWindow(hwnd);

    // Get initial window size
    var rect: RECT = undefined;
    _ = GetClientRect(hwnd, &rect);
    const width: u32 = @intCast(rect.right - rect.left);
    const height: u32 = @intCast(rect.bottom - rect.top);

    // Initialize Direct3D11
    var surface = Surface{
        .app = app,
        .hwnd = hwnd,
        .d3d_device = null,
        .d3d_context = null,
        .swap_chain = null,
        .render_target = null,
        .core_surface = null,
        .width = width,
        .height = height,
        .content_scale = 1.0,
    };

    try surface.initD3D11();

    log.info("YStty surface created: {}x{}", .{ width, height });

    return surface;
}

/// Deinitialize the surface
pub fn deinit(self: *Surface) void {
    log.info("Destroying YStty surface", .{});

    self.deinitD3D11();

    if (self.hwnd) |hwnd| {
        _ = DestroyWindow(hwnd);
        self.hwnd = null;
    }
}

/// Initialize Direct3D11 resources
fn initD3D11(self: *Surface) !void {
    const hwnd = self.hwnd orelse return error.NoWindow;

    log.info("Initializing Direct3D11 for surface", .{});

    // Create device, context, and swap chain
    var swap_chain_desc = DXGI_SWAP_CHAIN_DESC{
        .BufferDesc = .{
            .Width = self.width,
            .Height = self.height,
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
        null, // adapter
        D3D_DRIVER_TYPE_HARDWARE,
        null, // software
        flags,
        &feature_levels,
        feature_levels.len,
        D3D11_SDK_VERSION,
        &swap_chain_desc,
        &swap_chain,
        &device,
        null, // feature level out
        &context,
    );

    if (hr < 0) {
        log.err("D3D11CreateDeviceAndSwapChain failed: 0x{x}", .{@as(u32, @bitCast(hr))});
        return error.D3D11InitFailed;
    }

    self.d3d_device = device;
    self.d3d_context = context;
    self.swap_chain = swap_chain;

    // Create render target view
    try self.createRenderTarget();

    log.info("Direct3D11 initialized successfully", .{});
}

/// Create render target view from swap chain back buffer
fn createRenderTarget(self: *Surface) !void {
    const swap_chain: *IDXGISwapChain = @ptrCast(@alignCast(self.swap_chain orelse return error.NoSwapChain));
    const device: *ID3D11Device = @ptrCast(@alignCast(self.d3d_device orelse return error.NoDevice));

    // Get back buffer
    var back_buffer: ?*ID3D11Texture2D = null;
    var hr = swap_chain.vtable.GetBuffer(swap_chain, 0, &IID_ID3D11Texture2D, @ptrCast(&back_buffer));
    if (hr < 0) {
        return error.GetBufferFailed;
    }
    defer _ = back_buffer.?.vtable.Release(back_buffer.?);

    // Create render target view
    var rtv: ?*ID3D11RenderTargetView = null;
    hr = device.vtable.CreateRenderTargetView(device, @ptrCast(back_buffer), null, &rtv);
    if (hr < 0) {
        return error.CreateRenderTargetViewFailed;
    }

    self.render_target = rtv;
}

/// Release render target view
fn releaseRenderTarget(self: *Surface) void {
    if (self.render_target) |rt| {
        const rtv: *ID3D11RenderTargetView = @ptrCast(@alignCast(rt));
        _ = rtv.vtable.Release(rtv);
        self.render_target = null;
    }
}

/// Deinitialize Direct3D11 resources
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

/// Handle window resize
pub fn resize(self: *Surface, new_width: u32, new_height: u32) !void {
    if (new_width == 0 or new_height == 0) return;

    log.info("Resizing surface: {}x{} -> {}x{}", .{ self.width, self.height, new_width, new_height });

    self.width = new_width;
    self.height = new_height;

    // Release old render target
    self.releaseRenderTarget();

    // Resize swap chain buffers
    if (self.swap_chain) |sc| {
        const swap_chain: *IDXGISwapChain = @ptrCast(@alignCast(sc));
        const hr = swap_chain.vtable.ResizeBuffers(swap_chain, 0, new_width, new_height, DXGI_FORMAT_UNKNOWN, 0);
        if (hr < 0) {
            log.err("ResizeBuffers failed: 0x{x}", .{@as(u32, @bitCast(hr))});
            return error.ResizeBuffersFailed;
        }
    }

    // Recreate render target
    try self.createRenderTarget();
}

/// Render a frame
pub fn render(self: *Surface) !void {
    const context: *ID3D11DeviceContext = @ptrCast(@alignCast(self.d3d_context orelse return));
    const swap_chain: *IDXGISwapChain = @ptrCast(@alignCast(self.swap_chain orelse return));
    const rtv: *ID3D11RenderTargetView = @ptrCast(@alignCast(self.render_target orelse return));

    // Clear to a dark background color (typical terminal background)
    const clear_color = [4]f32{ 0.1, 0.1, 0.1, 1.0 };
    context.vtable.ClearRenderTargetView(context, rtv, &clear_color);

    // TODO: Render terminal cells using the generic renderer

    // Present
    const hr = swap_chain.vtable.Present(swap_chain, 1, 0); // VSync enabled
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
const GUID = extern struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };
const REFIID = *const GUID;

const SW_SHOW = 5;

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
) callconv(.C) ?HWND;
extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.C) BOOL;
extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.C) BOOL;
extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.C) BOOL;
extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.C) BOOL;

const HMENU = std.os.windows.HANDLE;

const WS_OVERLAPPEDWINDOW = 0x00CF0000;
const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));

fn createWindow(app: *App) ?HWND {
    return CreateWindowExW(
        0, // dwExStyle
        windows.WINDOW_CLASS_NAME,
        windows.APP_TITLE,
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        1280, // Initial width
        720, // Initial height
        null, // hWndParent
        null, // hMenu
        app.hinstance,
        null, // lpParam
    );
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

// COM interface GUIDs
const IID_ID3D11Texture2D = GUID{
    .Data1 = 0x6f15aaf2,
    .Data2 = 0xd208,
    .Data3 = 0x4e89,
    .Data4 = .{ 0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c },
};

// COM interface vtables (simplified)
const IUnknownVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.C) u32,
    Release: *const fn (*anyopaque) callconv(.C) u32,
};

const ID3D11DeviceVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*ID3D11Device, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11Device) callconv(.C) u32,
    Release: *const fn (*ID3D11Device) callconv(.C) u32,
    // ID3D11Device methods (partial - only what we need)
    CreateBuffer: *const anyopaque,
    CreateTexture1D: *const anyopaque,
    CreateTexture2D: *const anyopaque,
    CreateTexture3D: *const anyopaque,
    CreateShaderResourceView: *const anyopaque,
    CreateUnorderedAccessView: *const anyopaque,
    CreateRenderTargetView: *const fn (*ID3D11Device, *anyopaque, ?*anyopaque, *?*ID3D11RenderTargetView) callconv(.C) HRESULT,
    // ... more methods
};

const ID3D11Device = extern struct {
    vtable: *const ID3D11DeviceVtbl,
};

const ID3D11DeviceContextVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*ID3D11DeviceContext, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11DeviceContext) callconv(.C) u32,
    Release: *const fn (*ID3D11DeviceContext) callconv(.C) u32,
    // ID3D11DeviceChild
    GetDevice: *const anyopaque,
    GetPrivateData: *const anyopaque,
    SetPrivateData: *const anyopaque,
    SetPrivateDataInterface: *const anyopaque,
    // ID3D11DeviceContext methods (partial)
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
    ClearRenderTargetView: *const fn (*ID3D11DeviceContext, *ID3D11RenderTargetView, *const [4]f32) callconv(.C) void,
    // ... more methods
};

const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVtbl,
};

const ID3D11RenderTargetViewVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11RenderTargetView, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11RenderTargetView) callconv(.C) u32,
    Release: *const fn (*ID3D11RenderTargetView) callconv(.C) u32,
    // ... more methods
};

const ID3D11RenderTargetView = extern struct {
    vtable: *const ID3D11RenderTargetViewVtbl,
};

const ID3D11Texture2DVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11Texture2D, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11Texture2D) callconv(.C) u32,
    Release: *const fn (*ID3D11Texture2D) callconv(.C) u32,
    // ... more methods
};

const ID3D11Texture2D = extern struct {
    vtable: *const ID3D11Texture2DVtbl,
};

const IDXGISwapChainVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*IDXGISwapChain, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*IDXGISwapChain) callconv(.C) u32,
    Release: *const fn (*IDXGISwapChain) callconv(.C) u32,
    // IDXGIObject
    SetPrivateData: *const anyopaque,
    SetPrivateDataInterface: *const anyopaque,
    GetPrivateData: *const anyopaque,
    GetParent: *const anyopaque,
    // IDXGIDeviceSubObject
    GetDevice: *const anyopaque,
    // IDXGISwapChain
    Present: *const fn (*IDXGISwapChain, UINT, UINT) callconv(.C) HRESULT,
    GetBuffer: *const fn (*IDXGISwapChain, UINT, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    SetFullscreenState: *const anyopaque,
    GetFullscreenState: *const anyopaque,
    GetDesc: *const anyopaque,
    ResizeBuffers: *const fn (*IDXGISwapChain, UINT, UINT, UINT, UINT, UINT) callconv(.C) HRESULT,
    // ... more methods
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
) callconv(.C) HRESULT;

test {
    _ = Surface;
}
