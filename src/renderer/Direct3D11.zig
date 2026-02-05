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

/// The most recently presented target, in case we need to present it again.
last_target: ?Target,

pub fn init(alloc: Allocator, opts: rendererpkg.Options) error{D3D11InitFailed}!Direct3D11 {
    log.info("Initializing Direct3D11 renderer", .{});

    return .{
        .alloc = alloc,
        .blending = opts.config.blending,
        .device = null,
        .context = null,
        .last_target = null,
    };
}

pub fn deinit(self: *Direct3D11) void {
    log.info("Deinitializing Direct3D11 renderer", .{});

    if (self.context) |ctx| {
        _ = ctx.vtable.Release(ctx);
        self.context = null;
    }

    if (self.device) |dev| {
        _ = dev.vtable.Release(dev);
        self.device = null;
    }

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
    // Present is handled by the swap chain in the Surface
    _ = target;

    // Keep track of this target in case we need to repeat it.
    self.last_target = target;
}

/// Present the last presented target again.
pub fn presentLastTarget(self: *Direct3D11) !void {
    if (self.last_target) |target| try self.present(target);
}

/// Returns the options to use when constructing buffers.
pub inline fn bufferOptions(self: Direct3D11) bufferpkg.Options {
    _ = self;
    return .{
        .usage = .dynamic,
        .cpu_access = .write,
    };
}

pub const instanceBufferOptions = bufferOptions;
pub const uniformBufferOptions = bufferOptions;
pub const fgBufferOptions = bufferOptions;
pub const bgBufferOptions = bufferOptions;
pub const imageBufferOptions = bufferOptions;
pub const bgImageBufferOptions = bufferOptions;

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
    _ = self;
    return .{
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

// COM interface definitions (simplified)
const ID3D11DeviceVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11Device, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11Device) callconv(.C) u32,
    Release: *const fn (*ID3D11Device) callconv(.C) u32,
    // Additional methods would go here
};

const ID3D11Device = extern struct {
    vtable: *const ID3D11DeviceVtbl,
};

const ID3D11DeviceContextVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11DeviceContext, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11DeviceContext) callconv(.C) u32,
    Release: *const fn (*ID3D11DeviceContext) callconv(.C) u32,
    // Additional methods would go here
};

const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVtbl,
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
