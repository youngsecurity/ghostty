//! Direct3D 11 Texture
//!
//! 2D texture for font atlases, images, and other texture data.
//!
const Texture = @This();

const std = @import("std");

/// D3D11 texture object
texture: ?*ID3D11Texture2D,

/// Shader resource view for sampling
srv: ?*ID3D11ShaderResourceView,

/// Texture dimensions
width: usize,
height: usize,

/// DXGI format
format: u32,

pub const Error = error{
    TextureCreationFailed,
    SRVCreationFailed,
};

pub const Options = struct {
    device: ?*anyopaque = null,
    format: u32 = DXGI_FORMAT_R8G8B8A8_UNORM,
    usage: Usage = .default,
    bind_flags: BindFlags = .{ .shader_resource = true },
    filter: Filter = .linear,
    address_mode: AddressMode = .clamp,
};

pub const Usage = enum {
    default,
    immutable,
    dynamic,
    staging,
};

pub const BindFlags = packed struct {
    shader_resource: bool = false,
    render_target: bool = false,
    depth_stencil: bool = false,
    unordered_access: bool = false,
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
    _ = opts;
    _ = data;

    // TODO: Create D3D11 texture via ID3D11Device::CreateTexture2D
    // TODO: Create shader resource view via ID3D11Device::CreateShaderResourceView

    return Texture{
        .texture = null,
        .srv = null,
        .width = width,
        .height = height,
        .format = DXGI_FORMAT_R8G8B8A8_UNORM,
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
}

/// Update texture data
pub fn update(self: *Texture, context: *anyopaque, data: []const u8, row_pitch: usize) !void {
    _ = self;
    _ = context;
    _ = data;
    _ = row_pitch;
    // TODO: Use Map/Unmap for dynamic textures
    // Or UpdateSubresource for default textures
}

/// Bind to pixel shader
pub fn bindToPixelShader(self: *const Texture, context: *ID3D11DeviceContext, slot: u32) void {
    if (self.srv) |srv| {
        const srvs = [_]?*ID3D11ShaderResourceView{srv};
        context.vtable.PSSetShaderResources(context, slot, 1, &srvs);
    }
}

/// Bind to vertex shader
pub fn bindToVertexShader(self: *const Texture, context: *ID3D11DeviceContext, slot: u32) void {
    if (self.srv) |srv| {
        const srvs = [_]?*ID3D11ShaderResourceView{srv};
        context.vtable.VSSetShaderResources(context, slot, 1, &srvs);
    }
}

// =============================================================================
// D3D11 Constants
// =============================================================================

const DXGI_FORMAT_R8G8B8A8_UNORM = 28;

// =============================================================================
// D3D11 Type Definitions
// =============================================================================

const HRESULT = i32;
const UINT = u32;
const GUID = extern struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };

const ID3D11Texture2DVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11Texture2D, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11Texture2D) callconv(.C) u32,
    Release: *const fn (*ID3D11Texture2D) callconv(.C) u32,
};

const ID3D11Texture2D = extern struct {
    vtable: *const ID3D11Texture2DVtbl,
};

const ID3D11ShaderResourceViewVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11ShaderResourceView, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11ShaderResourceView) callconv(.C) u32,
    Release: *const fn (*ID3D11ShaderResourceView) callconv(.C) u32,
};

const ID3D11ShaderResourceView = extern struct {
    vtable: *const ID3D11ShaderResourceViewVtbl,
};

const ID3D11DeviceContextVtbl = extern struct {
    QueryInterface: *const anyopaque,
    AddRef: *const anyopaque,
    Release: *const anyopaque,
    GetDevice: *const anyopaque,
    GetPrivateData: *const anyopaque,
    SetPrivateData: *const anyopaque,
    SetPrivateDataInterface: *const anyopaque,
    VSSetConstantBuffers: *const anyopaque,
    PSSetShaderResources: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11ShaderResourceView) callconv(.C) void,
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
    VSSetShaderResources: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11ShaderResourceView) callconv(.C) void,
};

const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVtbl,
};

test {
    _ = Texture;
}
