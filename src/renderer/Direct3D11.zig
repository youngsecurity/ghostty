//! Graphics API wrapper for Direct3D 11.
//!
//! This renderer backend provides GPU-accelerated terminal rendering on Windows
//! using Direct3D 11. It follows the same pattern as the OpenGL and Metal backends,
//! implementing the generic renderer interface.
//!
//! Part of the YStty (YoungSecurity TTY) project.
//!
pub const Direct3D11 = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const shadertoy = @import("shadertoy.zig");
const apprt = @import("../apprt.zig");
const font = @import("../font/main.zig");
const configpkg = @import("../config.zig");
const rendererpkg = @import("../renderer.zig");
const Renderer = rendererpkg.GenericRenderer(Direct3D11);

pub const GraphicsAPI = Direct3D11;
pub const Target = @import("d3d11/Target.zig");
pub const Frame = @import("d3d11/Frame.zig");
pub const RenderPass = @import("d3d11/RenderPass.zig");
pub const Pipeline = @import("d3d11/Pipeline.zig");
const bufferpkg = @import("d3d11/buffer.zig");
pub const Buffer = bufferpkg.Buffer;
pub const Sampler = @import("d3d11/Sampler.zig");
pub const Texture = @import("d3d11/Texture.zig");
pub const shaders = @import("d3d11/shaders.zig");

/// Custom shader target for shadertoy compatibility
pub const custom_shader_target: shadertoy.Target = .hlsl;

/// The fragCoord for HLSL shaders is +Y = down (same as Metal)
pub const custom_shader_y_is_down = true;

/// D3D11 uses flip model swap chain, so we use double buffering
pub const swap_chain_count = 2;

const log = std.log.scoped(.d3d11);

/// Minimum required feature level
pub const MIN_FEATURE_LEVEL = D3D_FEATURE_LEVEL_11_0;

alloc: std.mem.Allocator,

/// Alpha blending mode
blending: configpkg.Config.AlphaBlending,

/// D3D11 device
device: ?*ID3D11Device,

/// D3D11 immediate context
context: ?*ID3D11DeviceContext,

/// DXGI swap chain for presenting
swap_chain: ?*IDXGISwapChain,

/// Back buffer render target view
back_buffer_rtv: ?*ID3D11RenderTargetView,

/// The most recently presented target, in case we need to present it again.
last_target: ?Target,

pub fn init(alloc: Allocator, opts: rendererpkg.Options) error{D3D11InitFailed}!Direct3D11 {
    log.info("Initializing Direct3D11 renderer", .{});

    // Get D3D11 objects from the surface
    const surface = opts.rt_surface;

    // The surface stores D3D11 objects as anyopaque, we just keep them as-is
    // and cast when needed in methods
    const device: ?*ID3D11Device = if (surface.d3d_device) |d|
        @ptrCast(@alignCast(d))
    else
        null;

    const context: ?*ID3D11DeviceContext = if (surface.d3d_context) |c|
        @ptrCast(@alignCast(c))
    else
        null;

    const swap_chain: ?*IDXGISwapChain = if (surface.swap_chain) |s|
        @ptrCast(@alignCast(s))
    else
        null;

    const back_buffer_rtv: ?*ID3D11RenderTargetView = if (surface.render_target) |r|
        @ptrCast(@alignCast(r))
    else
        null;

    if (device == null or context == null) {
        log.err("D3D11 device or context not available from surface", .{});
        return error.D3D11InitFailed;
    }

    log.info("Got D3D11 objects from surface", .{});

    return .{
        .alloc = alloc,
        .blending = opts.config.blending,
        .device = device,
        .context = context,
        .swap_chain = swap_chain,
        .back_buffer_rtv = back_buffer_rtv,
        .last_target = null,
    };
}

pub fn deinit(self: *Direct3D11) void {
    log.info("Deinitializing Direct3D11 renderer", .{});

    // Note: We don't release device, context, swap_chain, or back_buffer_rtv here
    // because they're owned by the Surface and just borrowed by the renderer.
    // The Surface will release them when it's destroyed.
    self.device = null;
    self.context = null;
    self.swap_chain = null;
    self.back_buffer_rtv = null;

    self.* = undefined;
}

/// This is called early right after surface creation.
pub fn surfaceInit(surface: *apprt.Surface) !void {
    _ = surface;

    log.info("Direct3D11 surface initialization", .{});

    // D3D11 initialization is handled by the Windows apprt Surface
    // which creates the device and swap chain
}

/// This is called just prior to spinning up the renderer
/// thread for final main thread setup requirements.
pub fn finalizeSurfaceInit(self: *const Direct3D11, surface: *apprt.Surface) !void {
    _ = self;
    _ = surface;
}

/// Callback called by renderer.Thread when it begins.
pub fn threadEnter(self: *const Direct3D11, surface: *apprt.Surface) !void {
    _ = self;
    _ = surface;

    log.debug("Direct3D11 renderer thread entered", .{});
}

/// Callback called by renderer.Thread when it exits.
pub fn threadExit(self: *const Direct3D11) void {
    _ = self;

    log.debug("Direct3D11 renderer thread exiting", .{});
}

pub fn displayRealized(self: *const Direct3D11) void {
    _ = self;
}

/// Actions taken before doing anything in `drawFrame`.
pub fn drawFrameStart(self: *Direct3D11) void {
    _ = self;
}

/// Actions taken after `drawFrame` is done.
pub fn drawFrameEnd(self: *Direct3D11) void {
    _ = self;
}

pub fn initShaders(
    self: *const Direct3D11,
    alloc: Allocator,
    custom_shaders: []const [:0]const u8,
) !shaders.Shaders {
    _ = alloc;
    return try shaders.Shaders.init(
        self.alloc,
        custom_shaders,
    );
}

/// Get the current size of the runtime surface.
pub fn surfaceSize(self: *const Direct3D11) !struct { width: u32, height: u32 } {
    _ = self;
    // TODO: Query from swap chain or cached surface size
    return .{
        .width = 1280,
        .height = 720,
    };
}

/// Initialize a new render target which can be presented by this API.
pub fn initTarget(self: *const Direct3D11, width: usize, height: usize) !Target {
    return Target.init(.{
        .device = self.device,
        .format = if (self.blending.isLinear()) .srgba else .rgba,
        .width = width,
        .height = height,
    });
}

/// Present the provided target.
pub fn present(self: *Direct3D11, target: Target) !void {
    const context = self.context orelse return error.NoContext;
    const swap_chain = self.swap_chain orelse return error.NoSwapChain;
    // back_buffer_rtv kept for potential future use (clearing, etc.)
    _ = self.back_buffer_rtv orelse return error.NoBackBuffer;

    // Copy the target texture to the back buffer
    // First, we need to get the back buffer texture from the RTV
    // For now, we'll use CopyResource if the target has a texture
    if (target.texture) |target_tex| {
        // Get the back buffer texture from the swap chain
        var back_buffer: ?*ID3D11Texture2D = null;
        const hr = swap_chain.vtable.GetBuffer(swap_chain, 0, &IID_ID3D11Texture2D, @ptrCast(&back_buffer));
        if (hr >= 0 and back_buffer != null) {
            defer _ = back_buffer.?.vtable.Release(back_buffer.?);

            // Copy the target texture to the back buffer
            context.vtable.CopyResource(context, @ptrCast(back_buffer), @ptrCast(target_tex));
        }
    }

    // Present the swap chain
    const present_hr = swap_chain.vtable.Present(swap_chain, 1, 0);
    if (present_hr < 0) {
        log.warn("Present failed: 0x{x}", .{@as(u32, @bitCast(present_hr))});
    }

    // Keep track of this target in case we need to repeat it.
    self.last_target = target;
}

/// Present the last presented target again.
pub fn presentLastTarget(self: *Direct3D11) !void {
    if (self.last_target) |target| try self.present(target);
}

/// Returns the options to use when constructing buffers.
pub inline fn bufferOptions(self: Direct3D11) bufferpkg.Options {
    return .{
        .device = self.device,
        .context = self.context,
        .usage = .dynamic,
        .cpu_access = .write,
        .bind_flags = .{ .vertex_buffer = true },
    };
}

/// Returns the options to use when constructing instance buffers.
pub inline fn instanceBufferOptions(self: Direct3D11) bufferpkg.Options {
    return .{
        .device = self.device,
        .context = self.context,
        .usage = .dynamic,
        .cpu_access = .write,
        .bind_flags = .{ .vertex_buffer = true },
    };
}

/// Returns the options to use when constructing uniform/constant buffers.
pub inline fn uniformBufferOptions(self: Direct3D11) bufferpkg.Options {
    return .{
        .device = self.device,
        .context = self.context,
        .usage = .dynamic,
        .cpu_access = .write,
        .bind_flags = .{ .constant_buffer = true },
    };
}

/// Returns the options to use when constructing foreground cell buffers.
pub inline fn fgBufferOptions(self: Direct3D11) bufferpkg.Options {
    return .{
        .device = self.device,
        .context = self.context,
        .usage = .dynamic,
        .cpu_access = .write,
        .bind_flags = .{ .vertex_buffer = true },
    };
}

/// Returns the options to use when constructing background cell buffers.
pub inline fn bgBufferOptions(self: Direct3D11) bufferpkg.Options {
    return .{
        .device = self.device,
        .context = self.context,
        .usage = .dynamic,
        .cpu_access = .write,
        .bind_flags = .{ .vertex_buffer = true },
    };
}

/// Returns the options to use when constructing image buffers.
pub inline fn imageBufferOptions(self: Direct3D11) bufferpkg.Options {
    return .{
        .device = self.device,
        .context = self.context,
        .usage = .dynamic,
        .cpu_access = .write,
        .bind_flags = .{ .vertex_buffer = true },
    };
}

/// Returns the options to use when constructing background image buffers.
pub inline fn bgImageBufferOptions(self: Direct3D11) bufferpkg.Options {
    return .{
        .device = self.device,
        .context = self.context,
        .usage = .dynamic,
        .cpu_access = .write,
        .bind_flags = .{ .vertex_buffer = true },
    };
}

/// Returns the options to use when constructing textures.
pub inline fn textureOptions(self: Direct3D11) Texture.Options {
    return .{
        .device = self.device,
        .context = self.context,
        .format = DXGI_FORMAT_R8G8B8A8_UNORM,
        .usage = .default,
        .bind_flags = .{ .shader_resource = true },
        .filter = .linear,
        .address_mode = .clamp,
    };
}

/// Returns the options to use when constructing samplers.
pub inline fn samplerOptions(self: Direct3D11) Sampler.Options {
    return .{
        .device = self.device,
        .filter = .linear,
        .address_u = .clamp,
        .address_v = .clamp,
        .address_w = .clamp,
    };
}

/// Pixel format for image texture options.
pub const ImageTextureFormat = enum {
    /// 1 byte per pixel grayscale.
    gray,
    /// 4 bytes per pixel RGBA.
    rgba,
    /// 4 bytes per pixel BGRA.
    bgra,

    fn toDXGIFormat(self: ImageTextureFormat, srgb: bool) u32 {
        return switch (self) {
            .gray => DXGI_FORMAT_R8_UNORM,
            .rgba => if (srgb) DXGI_FORMAT_R8G8B8A8_UNORM_SRGB else DXGI_FORMAT_R8G8B8A8_UNORM,
            .bgra => if (srgb) DXGI_FORMAT_B8G8R8A8_UNORM_SRGB else DXGI_FORMAT_B8G8R8A8_UNORM,
        };
    }
};

/// Returns the options to use when constructing textures for images.
pub inline fn imageTextureOptions(
    self: Direct3D11,
    format: ImageTextureFormat,
    srgb: bool,
) Texture.Options {
    return .{
        .device = self.device,
        .context = self.context,
        .format = format.toDXGIFormat(srgb),
        .usage = .default,
        .bind_flags = .{ .shader_resource = true },
        .filter = .linear,
        .address_mode = .clamp,
    };
}

/// Initializes a Texture suitable for the provided font atlas.
pub fn initAtlasTexture(
    self: *const Direct3D11,
    atlas: *const font.Atlas,
) Texture.Error!Texture {
    const format: u32 = switch (atlas.format) {
        .grayscale => DXGI_FORMAT_R8_UNORM,
        .bgra => DXGI_FORMAT_B8G8R8A8_UNORM_SRGB,
        else => @panic("unsupported atlas format for D3D11 texture"),
    };

    return try Texture.init(
        .{
            .device = self.device,
            .context = self.context,
            .format = format,
            .usage = .default,
            .bind_flags = .{ .shader_resource = true },
            .filter = .point, // Nearest neighbor for font atlas
            .address_mode = .clamp,
        },
        atlas.size,
        atlas.size,
        null,
    );
}

/// Begin a frame.
pub inline fn beginFrame(
    self: *const Direct3D11,
    renderer: *Renderer,
    target: *Target,
) !Frame {
    _ = self;
    return try Frame.begin(.{}, renderer, target);
}

// =============================================================================
// Direct3D 11 Type Definitions
// =============================================================================

const UINT = u32;
const HRESULT = i32;
const GUID = extern struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };

const D3D_FEATURE_LEVEL_11_0 = 0xb000;
const D3D_FEATURE_LEVEL_11_1 = 0xb100;

const DXGI_FORMAT_R8_UNORM = 61;
const DXGI_FORMAT_R8G8B8A8_UNORM = 28;
const DXGI_FORMAT_R8G8B8A8_UNORM_SRGB = 29;
const DXGI_FORMAT_B8G8R8A8_UNORM = 87;
const DXGI_FORMAT_B8G8R8A8_UNORM_SRGB = 91;

// IID constants
const IID_ID3D11Texture2D = GUID{
    .Data1 = 0x6f15aaf2,
    .Data2 = 0xd208,
    .Data3 = 0x4e89,
    .Data4 = .{ 0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c },
};

// COM interface definitions
const ID3D11DeviceVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11Device, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11Device) callconv(.c) u32,
    Release: *const fn (*ID3D11Device) callconv(.c) u32,
    // Additional methods would go here
};

const ID3D11Device = extern struct {
    vtable: *const ID3D11DeviceVtbl,
};

const ID3D11DeviceContextVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11DeviceContext, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11DeviceContext) callconv(.c) u32,
    Release: *const fn (*ID3D11DeviceContext) callconv(.c) u32,
    // ID3D11DeviceChild methods (3-6)
    GetDevice: *const anyopaque,
    GetPrivateData: *const anyopaque,
    SetPrivateData: *const anyopaque,
    SetPrivateDataInterface: *const anyopaque,
    // ID3D11DeviceContext methods (7+)
    VSSetConstantBuffers: *const anyopaque, // 7
    PSSetShaderResources: *const anyopaque, // 8
    PSSetShader: *const anyopaque, // 9
    PSSetSamplers: *const anyopaque, // 10
    VSSetShader: *const anyopaque, // 11
    DrawIndexed: *const anyopaque, // 12
    Draw: *const anyopaque, // 13
    Map: *const anyopaque, // 14
    Unmap: *const anyopaque, // 15
    PSSetConstantBuffers: *const anyopaque, // 16
    IASetInputLayout: *const anyopaque, // 17
    IASetVertexBuffers: *const anyopaque, // 18
    IASetIndexBuffer: *const anyopaque, // 19
    DrawIndexedInstanced: *const anyopaque, // 20
    DrawInstanced: *const anyopaque, // 21
    GSSetConstantBuffers: *const anyopaque, // 22
    GSSetShader: *const anyopaque, // 23
    IASetPrimitiveTopology: *const anyopaque, // 24
    VSSetShaderResources: *const anyopaque, // 25
    VSSetSamplers: *const anyopaque, // 26
    Begin: *const anyopaque, // 27
    End: *const anyopaque, // 28
    GetData: *const anyopaque, // 29
    SetPredication: *const anyopaque, // 30
    GSSetShaderResources: *const anyopaque, // 31
    GSSetSamplers: *const anyopaque, // 32
    OMSetRenderTargets: *const anyopaque, // 33
    OMSetRenderTargetsAndUnorderedAccessViews: *const anyopaque, // 34
    OMSetBlendState: *const anyopaque, // 35
    OMSetDepthStencilState: *const anyopaque, // 36
    SOSetTargets: *const anyopaque, // 37
    DrawAuto: *const anyopaque, // 38
    DrawIndexedInstancedIndirect: *const anyopaque, // 39
    DrawInstancedIndirect: *const anyopaque, // 40
    Dispatch: *const anyopaque, // 41
    DispatchIndirect: *const anyopaque, // 42
    RSSetState: *const anyopaque, // 43
    RSSetViewports: *const anyopaque, // 44
    RSSetScissorRects: *const anyopaque, // 45
    CopySubresourceRegion: *const anyopaque, // 46
    CopyResource: *const fn (*ID3D11DeviceContext, *anyopaque, *anyopaque) callconv(.c) void, // 47
};

const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVtbl,
};

const ID3D11Texture2DVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11Texture2D, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11Texture2D) callconv(.c) u32,
    Release: *const fn (*ID3D11Texture2D) callconv(.c) u32,
};

const ID3D11Texture2D = extern struct {
    vtable: *const ID3D11Texture2DVtbl,
};

const ID3D11RenderTargetViewVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11RenderTargetView, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11RenderTargetView) callconv(.c) u32,
    Release: *const fn (*ID3D11RenderTargetView) callconv(.c) u32,
};

const ID3D11RenderTargetView = extern struct {
    vtable: *const ID3D11RenderTargetViewVtbl,
};

const IDXGISwapChainVtbl = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const fn (*IDXGISwapChain, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*IDXGISwapChain) callconv(.c) u32,
    Release: *const fn (*IDXGISwapChain) callconv(.c) u32,
    // IDXGIObject (3-6)
    SetPrivateData: *const anyopaque,
    SetPrivateDataInterface: *const anyopaque,
    GetPrivateData: *const anyopaque,
    GetParent: *const anyopaque,
    // IDXGIDeviceSubObject (7)
    GetDevice: *const anyopaque,
    // IDXGISwapChain (8+)
    Present: *const fn (*IDXGISwapChain, UINT, UINT) callconv(.c) HRESULT,
    GetBuffer: *const fn (*IDXGISwapChain, UINT, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    SetFullscreenState: *const anyopaque,
    GetFullscreenState: *const anyopaque,
    GetDesc: *const anyopaque,
    ResizeBuffers: *const anyopaque,
};

const IDXGISwapChain = extern struct {
    vtable: *const IDXGISwapChainVtbl,
};

test {
    _ = Direct3D11;
    _ = Target;
    _ = Frame;
    _ = RenderPass;
    _ = Pipeline;
    _ = Buffer;
    _ = Sampler;
    _ = Texture;
    _ = shaders;
}
