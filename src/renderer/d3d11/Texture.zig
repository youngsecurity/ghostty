//! Direct3D 11 Texture
//!
//! 2D texture for font atlases, images, and other texture data.
//! Supports both grayscale (R8) and BGRA formats for font rendering.
//!
const Texture = @This();

const std = @import("std");

const log = std.log.scoped(.d3d11_texture);

/// D3D11 texture object
texture: ?*ID3D11Texture2D,

/// Shader resource view for sampling
srv: ?*ID3D11ShaderResourceView,

/// D3D11 device (kept for resizing)
device: ?*ID3D11Device,

/// D3D11 device context (kept for updates)
context: ?*ID3D11DeviceContext,

/// Texture dimensions
width: usize,
height: usize,

/// Bytes per pixel
bpp: usize,

/// DXGI format
format: u32,

pub const Error = error{
    TextureCreationFailed,
    SRVCreationFailed,
};

pub const Options = struct {
    device: ?*ID3D11Device = null,
    context: ?*ID3D11DeviceContext = null,
    format: u32 = DXGI_FORMAT_R8G8B8A8_UNORM,
    usage: Usage = .default,
    bind_flags: BindFlags = .{ .shader_resource = true },
    filter: Filter = .linear,
    address_mode: AddressMode = .clamp,
};

pub const Usage = enum(u32) {
    default = 0,
    immutable = 1,
    dynamic = 2,
    staging = 3,
};

pub const BindFlags = packed struct(u32) {
    vertex_buffer: bool = false,
    index_buffer: bool = false,
    constant_buffer: bool = false,
    shader_resource: bool = false,
    stream_output: bool = false,
    render_target: bool = false,
    depth_stencil: bool = false,
    unordered_access: bool = false,
    _padding: u24 = 0,
};

pub const Filter = enum {
    point,
    linear,
    anisotropic,
};

pub const AddressMode = enum {
    wrap,
    mirror,
    clamp,
    border,
};

pub fn init(opts: Options, width: usize, height: usize, data: ?[]const u8) Error!Texture {
    const device = opts.device orelse return Error.TextureCreationFailed;

    const bpp = bppFromFormat(opts.format);

    // Create texture descriptor
    const desc = D3D11_TEXTURE2D_DESC{
        .Width = @intCast(width),
        .Height = @intCast(height),
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = opts.format,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .Usage = @intFromEnum(opts.usage),
        .BindFlags = @bitCast(opts.bind_flags),
        .CPUAccessFlags = 0,
        .MiscFlags = 0,
    };

    // Initial data if provided
    var init_data: ?D3D11_SUBRESOURCE_DATA = null;
    var init_data_storage: D3D11_SUBRESOURCE_DATA = undefined;
    if (data) |d| {
        init_data_storage = .{
            .pSysMem = d.ptr,
            .SysMemPitch = @intCast(width * bpp),
            .SysMemSlicePitch = 0,
        };
        init_data = init_data_storage;
    }

    // Create the texture
    var texture: ?*ID3D11Texture2D = null;
    const hr = device.vtable.CreateTexture2D(
        device,
        &desc,
        if (init_data != null) &init_data_storage else null,
        &texture,
    );
    if (hr < 0 or texture == null) {
        log.err("CreateTexture2D failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
        return Error.TextureCreationFailed;
    }
    errdefer _ = texture.?.vtable.Release(texture.?);

    // Create shader resource view
    const srv_desc = D3D11_SHADER_RESOURCE_VIEW_DESC{
        .Format = opts.format,
        .ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D,
        .u = .{
            .Texture2D = .{
                .MostDetailedMip = 0,
                .MipLevels = 1,
            },
        },
    };

    var srv: ?*ID3D11ShaderResourceView = null;
    const srv_hr = device.vtable.CreateShaderResourceView(
        device,
        @ptrCast(texture),
        &srv_desc,
        &srv,
    );
    if (srv_hr < 0 or srv == null) {
        log.err("CreateShaderResourceView failed: hr=0x{x}", .{@as(u32, @bitCast(srv_hr))});
        return Error.SRVCreationFailed;
    }

    log.debug("Created texture {}x{} format={} bpp={}", .{ width, height, opts.format, bpp });

    return Texture{
        .texture = texture,
        .srv = srv,
        .device = device,
        .context = opts.context,
        .width = width,
        .height = height,
        .bpp = bpp,
        .format = opts.format,
    };
}

pub fn deinit(self: *Texture) void {
    if (self.srv) |srv| {
        _ = srv.vtable.Release(srv);
        self.srv = null;
    }
    if (self.texture) |tex| {
        _ = tex.vtable.Release(tex);
        self.texture = null;
    }
    self.device = null;
    self.context = null;
}

/// Replace a region of the texture with the provided data.
/// This is the D3D11 equivalent of Metal's replaceRegion.
///
/// The data must be tightly packed with row_pitch = width * bpp.
/// For updating a subregion, the data slice should contain exactly
/// width * height * bpp bytes.
///
/// Matches the Metal/OpenGL interface: (x, y, width, height, data)
pub fn replaceRegion(
    self: Texture,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    data: []const u8,
) error{}!void {
    const texture = self.texture orelse return;
    const context = self.context orelse return;

    // Calculate expected data size
    const expected_size = width * height * self.bpp;
    if (data.len < expected_size) {
        log.warn("replaceRegion: data too small, got {} expected {}", .{ data.len, expected_size });
        return;
    }

    // D3D11_BOX defines the region to update
    const box = D3D11_BOX{
        .left = @intCast(x),
        .top = @intCast(y),
        .front = 0,
        .right = @intCast(x + width),
        .bottom = @intCast(y + height),
        .back = 1,
    };

    // Row pitch is width * bytes per pixel
    const row_pitch: u32 = @intCast(width * self.bpp);

    // UpdateSubresource copies data from CPU to GPU
    context.vtable.UpdateSubresource(
        context,
        @ptrCast(texture),
        0, // subresource index
        &box,
        data.ptr,
        row_pitch,
        0, // depth pitch (not used for 2D textures)
    );
}

/// Update entire texture with new data
pub fn update(self: Texture, data: []const u8) void {
    self.replaceRegion(0, 0, self.width, self.height, data) catch {};
}

/// Bind to pixel shader at the specified slot
pub fn bindToPixelShader(self: *const Texture, context: *ID3D11DeviceContext, slot: u32) void {
    if (self.srv) |srv| {
        const srvs = [_]?*ID3D11ShaderResourceView{srv};
        context.vtable.PSSetShaderResources(context, slot, 1, &srvs);
    }
}

/// Bind to vertex shader at the specified slot
pub fn bindToVertexShader(self: *const Texture, context: *ID3D11DeviceContext, slot: u32) void {
    if (self.srv) |srv| {
        const srvs = [_]?*ID3D11ShaderResourceView{srv};
        context.vtable.VSSetShaderResources(context, slot, 1, &srvs);
    }
}

/// Returns bytes per pixel for the given DXGI format
fn bppFromFormat(format: u32) usize {
    return switch (format) {
        // 8-bit formats
        DXGI_FORMAT_R8_UNORM,
        DXGI_FORMAT_R8_SNORM,
        DXGI_FORMAT_R8_UINT,
        DXGI_FORMAT_R8_SINT,
        DXGI_FORMAT_A8_UNORM,
        => 1,

        // 16-bit formats
        DXGI_FORMAT_R16_UNORM,
        DXGI_FORMAT_R16_SNORM,
        DXGI_FORMAT_R16_UINT,
        DXGI_FORMAT_R16_SINT,
        DXGI_FORMAT_R16_FLOAT,
        DXGI_FORMAT_R8G8_UNORM,
        => 2,

        // 32-bit formats
        DXGI_FORMAT_R8G8B8A8_UNORM,
        DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
        DXGI_FORMAT_B8G8R8A8_UNORM,
        DXGI_FORMAT_B8G8R8A8_UNORM_SRGB,
        DXGI_FORMAT_R32_FLOAT,
        DXGI_FORMAT_R32_UINT,
        DXGI_FORMAT_R32_SINT,
        => 4,

        // 64-bit formats
        DXGI_FORMAT_R16G16B16A16_FLOAT,
        DXGI_FORMAT_R16G16B16A16_UNORM,
        => 8,

        // 128-bit formats
        DXGI_FORMAT_R32G32B32A32_FLOAT,
        => 16,

        else => {
            log.warn("Unknown DXGI format {}, assuming 4 bpp", .{format});
            return 4;
        },
    };
}

// =============================================================================
// DXGI Format Constants
// =============================================================================

pub const DXGI_FORMAT_R8_UNORM = 61;
pub const DXGI_FORMAT_R8_SNORM = 63;
pub const DXGI_FORMAT_R8_UINT = 62;
pub const DXGI_FORMAT_R8_SINT = 64;
pub const DXGI_FORMAT_A8_UNORM = 65;
pub const DXGI_FORMAT_R16_UNORM = 56;
pub const DXGI_FORMAT_R16_SNORM = 58;
pub const DXGI_FORMAT_R16_UINT = 57;
pub const DXGI_FORMAT_R16_SINT = 59;
pub const DXGI_FORMAT_R16_FLOAT = 54;
pub const DXGI_FORMAT_R8G8_UNORM = 49;
pub const DXGI_FORMAT_R8G8B8A8_UNORM = 28;
pub const DXGI_FORMAT_R8G8B8A8_UNORM_SRGB = 29;
pub const DXGI_FORMAT_B8G8R8A8_UNORM = 87;
pub const DXGI_FORMAT_B8G8R8A8_UNORM_SRGB = 91;
pub const DXGI_FORMAT_R32_FLOAT = 41;
pub const DXGI_FORMAT_R32_UINT = 42;
pub const DXGI_FORMAT_R32_SINT = 43;
pub const DXGI_FORMAT_R16G16B16A16_FLOAT = 10;
pub const DXGI_FORMAT_R16G16B16A16_UNORM = 11;
pub const DXGI_FORMAT_R32G32B32A32_FLOAT = 2;

// =============================================================================
// D3D11 Type Definitions
// =============================================================================

const HRESULT = i32;
const UINT = u32;
const GUID = extern struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };

/// D3D11_TEXTURE2D_DESC structure
const D3D11_TEXTURE2D_DESC = extern struct {
    Width: UINT,
    Height: UINT,
    MipLevels: UINT,
    ArraySize: UINT,
    Format: UINT,
    SampleDesc: DXGI_SAMPLE_DESC,
    Usage: UINT,
    BindFlags: UINT,
    CPUAccessFlags: UINT,
    MiscFlags: UINT,
};

const DXGI_SAMPLE_DESC = extern struct {
    Count: UINT,
    Quality: UINT,
};

/// D3D11_SUBRESOURCE_DATA for initial texture data
const D3D11_SUBRESOURCE_DATA = extern struct {
    pSysMem: ?*const anyopaque,
    SysMemPitch: UINT,
    SysMemSlicePitch: UINT,
};

/// D3D11_BOX for UpdateSubresource region
const D3D11_BOX = extern struct {
    left: UINT,
    top: UINT,
    front: UINT,
    right: UINT,
    bottom: UINT,
    back: UINT,
};

/// D3D11_SHADER_RESOURCE_VIEW_DESC
const D3D11_SRV_DIMENSION_TEXTURE2D = 4;

const D3D11_SHADER_RESOURCE_VIEW_DESC = extern struct {
    Format: UINT,
    ViewDimension: UINT,
    u: extern union {
        Texture2D: extern struct {
            MostDetailedMip: UINT,
            MipLevels: UINT,
        },
        _padding: [8]u32,
    },
};

// ID3D11Texture2D COM interface
const ID3D11Texture2DVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*ID3D11Texture2D, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11Texture2D) callconv(.c) u32,
    Release: *const fn (*ID3D11Texture2D) callconv(.c) u32,
    // ID3D11DeviceChild
    GetDevice: *const anyopaque,
    GetPrivateData: *const anyopaque,
    SetPrivateData: *const anyopaque,
    SetPrivateDataInterface: *const anyopaque,
    // ID3D11Resource
    GetType: *const anyopaque,
    SetEvictionPriority: *const anyopaque,
    GetEvictionPriority: *const anyopaque,
    // ID3D11Texture2D
    GetDesc: *const anyopaque,
};

const ID3D11Texture2D = extern struct {
    vtable: *const ID3D11Texture2DVtbl,
};

// ID3D11ShaderResourceView COM interface
const ID3D11ShaderResourceViewVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*ID3D11ShaderResourceView, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11ShaderResourceView) callconv(.c) u32,
    Release: *const fn (*ID3D11ShaderResourceView) callconv(.c) u32,
    // ID3D11DeviceChild
    GetDevice: *const anyopaque,
    GetPrivateData: *const anyopaque,
    SetPrivateData: *const anyopaque,
    SetPrivateDataInterface: *const anyopaque,
    // ID3D11View
    GetResource: *const anyopaque,
    // ID3D11ShaderResourceView
    GetDesc: *const anyopaque,
};

pub const ID3D11ShaderResourceView = extern struct {
    vtable: *const ID3D11ShaderResourceViewVtbl,
};

// ID3D11Device COM interface (partial - methods we need)
const ID3D11DeviceVtbl = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const fn (*ID3D11Device, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11Device) callconv(.c) u32,
    Release: *const fn (*ID3D11Device) callconv(.c) u32,
    // ID3D11Device methods (3+)
    CreateBuffer: *const anyopaque,
    CreateTexture1D: *const anyopaque,
    CreateTexture2D: *const fn (
        *ID3D11Device,
        *const D3D11_TEXTURE2D_DESC,
        ?*const D3D11_SUBRESOURCE_DATA,
        *?*ID3D11Texture2D,
    ) callconv(.c) HRESULT,
    CreateTexture3D: *const anyopaque,
    CreateShaderResourceView: *const fn (
        *ID3D11Device,
        ?*anyopaque, // ID3D11Resource*
        ?*const D3D11_SHADER_RESOURCE_VIEW_DESC,
        *?*ID3D11ShaderResourceView,
    ) callconv(.c) HRESULT,
    // ... more methods not needed here
};

pub const ID3D11Device = extern struct {
    vtable: *const ID3D11DeviceVtbl,
};

// ID3D11DeviceContext COM interface (partial - methods we need)
pub const ID3D11DeviceContextVtbl = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const anyopaque,
    AddRef: *const anyopaque,
    Release: *const anyopaque,
    // ID3D11DeviceChild (3-6)
    GetDevice: *const anyopaque,
    GetPrivateData: *const anyopaque,
    SetPrivateData: *const anyopaque,
    SetPrivateDataInterface: *const anyopaque,
    // ID3D11DeviceContext (7+)
    VSSetConstantBuffers: *const anyopaque, // 7
    PSSetShaderResources: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11ShaderResourceView) callconv(.c) void, // 8
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
    VSSetShaderResources: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11ShaderResourceView) callconv(.c) void, // 25
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
    CopyResource: *const anyopaque, // 47
    UpdateSubresource: *const fn (
        *ID3D11DeviceContext,
        ?*anyopaque, // ID3D11Resource*
        UINT, // subresource
        ?*const D3D11_BOX,
        ?*const anyopaque, // pSrcData
        UINT, // SrcRowPitch
        UINT, // SrcDepthPitch
    ) callconv(.c) void, // 48
    // ... more methods after this
};

pub const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVtbl,
};

test {
    _ = Texture;
    // Verify struct sizes match Windows expectations
    if (@sizeOf(D3D11_TEXTURE2D_DESC) != 44) {
        @compileError("D3D11_TEXTURE2D_DESC size mismatch");
    }
}
