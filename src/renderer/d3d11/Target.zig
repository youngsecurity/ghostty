//! Direct3D 11 Render Target
//!
//! Represents a render target that can be drawn to and presented.
//! This wraps a D3D11 render target view and associated resources.
//!
const Target = @This();

const std = @import("std");

/// Render target view
rtv: ?*ID3D11RenderTargetView,

/// Associated texture
texture: ?*ID3D11Texture2D,

/// Target dimensions
width: usize,
height: usize,

/// Texture format
format: Format,

pub const Format = enum {
    rgba,
    srgba,

    pub fn toDXGI(self: Format) u32 {
        return switch (self) {
            .rgba => DXGI_FORMAT_R8G8B8A8_UNORM,
            .srgba => DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
        };
    }
};

pub const Options = struct {
    device: ?*anyopaque,
    format: Format,
    width: usize,
    height: usize,
};

pub const Error = error{
    TargetCreationFailed,
    RenderTargetViewCreationFailed,
};

pub fn init(opts: Options) Error!Target {
    const device: *ID3D11Device = @ptrCast(@alignCast(opts.device orelse return Error.TargetCreationFailed));

    // Create the texture
    const tex_desc = D3D11_TEXTURE2D_DESC{
        .Width = @intCast(opts.width),
        .Height = @intCast(opts.height),
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = opts.format.toDXGI(),
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .Usage = D3D11_USAGE_DEFAULT,
        .BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE,
        .CPUAccessFlags = 0,
        .MiscFlags = 0,
    };

    var texture: ?*ID3D11Texture2D = null;
    var hr = device.vtable.CreateTexture2D(device, &tex_desc, null, &texture);
    if (hr < 0 or texture == null) {
        return Error.TargetCreationFailed;
    }
    errdefer _ = texture.?.vtable.Release(texture.?);

    // Create the render target view
    const rtv_desc = D3D11_RENDER_TARGET_VIEW_DESC{
        .Format = opts.format.toDXGI(),
        .ViewDimension = D3D11_RTV_DIMENSION_TEXTURE2D,
        .u = .{ .Texture2D = .{ .MipSlice = 0 } },
    };

    var rtv: ?*ID3D11RenderTargetView = null;
    hr = device.vtable.CreateRenderTargetView(device, @ptrCast(texture), &rtv_desc, &rtv);
    if (hr < 0 or rtv == null) {
        return Error.RenderTargetViewCreationFailed;
    }

    return Target{
        .rtv = rtv,
        .texture = texture,
        .width = opts.width,
        .height = opts.height,
        .format = opts.format,
    };
}

pub fn deinit(self: *Target) void {
    if (self.rtv) |rtv| {
        _ = rtv.vtable.Release(rtv);
        self.rtv = null;
    }
    if (self.texture) |tex| {
        _ = tex.vtable.Release(tex);
        self.texture = null;
    }
}

/// Bind this render target for rendering
pub fn bind(self: *const Target, context: *ID3D11DeviceContext) void {
    if (self.rtv) |rtv| {
        const rtvs = [_]?*ID3D11RenderTargetView{rtv};
        context.vtable.OMSetRenderTargets(context, 1, &rtvs, null);
    }
}

/// Clear the render target
pub fn clear(self: *const Target, context: *ID3D11DeviceContext, color: [4]f32) void {
    if (self.rtv) |rtv| {
        context.vtable.ClearRenderTargetView(context, rtv, &color);
    }
}

// =============================================================================
// D3D11 Constants
// =============================================================================

const D3D11_USAGE_DEFAULT = 0;
const D3D11_BIND_RENDER_TARGET = 0x20;
const D3D11_BIND_SHADER_RESOURCE = 0x8;
const D3D11_RTV_DIMENSION_TEXTURE2D = 4;

// =============================================================================
// D3D11 Type Definitions
// =============================================================================

const UINT = u32;
const HRESULT = i32;
const GUID = extern struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };

const DXGI_FORMAT_R8G8B8A8_UNORM = 28;
const DXGI_FORMAT_R8G8B8A8_UNORM_SRGB = 29;

const DXGI_SAMPLE_DESC = extern struct {
    Count: UINT,
    Quality: UINT,
};

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

const D3D11_TEX2D_RTV = extern struct {
    MipSlice: UINT,
};

const D3D11_RENDER_TARGET_VIEW_DESC = extern struct {
    Format: UINT,
    ViewDimension: UINT,
    u: extern union {
        Buffer: extern struct { FirstElement: UINT, NumElements: UINT },
        Texture1D: extern struct { MipSlice: UINT },
        Texture1DArray: extern struct { MipSlice: UINT, FirstArraySlice: UINT, ArraySize: UINT },
        Texture2D: D3D11_TEX2D_RTV,
        Texture2DArray: extern struct { MipSlice: UINT, FirstArraySlice: UINT, ArraySize: UINT },
        Texture2DMS: extern struct { UnusedField_NothingToDefine: UINT },
        Texture2DMSArray: extern struct { FirstArraySlice: UINT, ArraySize: UINT },
        Texture3D: extern struct { MipSlice: UINT, FirstWSlice: UINT, WSize: UINT },
    },
};

const ID3D11RenderTargetViewVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11RenderTargetView, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11RenderTargetView) callconv(.c) u32,
    Release: *const fn (*ID3D11RenderTargetView) callconv(.c) u32,
};

pub const ID3D11RenderTargetView = extern struct {
    vtable: *const ID3D11RenderTargetViewVtbl,
};

const ID3D11Texture2DVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11Texture2D, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11Texture2D) callconv(.c) u32,
    Release: *const fn (*ID3D11Texture2D) callconv(.c) u32,
};

pub const ID3D11Texture2D = extern struct {
    vtable: *const ID3D11Texture2DVtbl,
};

const ID3D11DeviceVtbl = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const anyopaque,
    AddRef: *const anyopaque,
    Release: *const anyopaque,
    // ID3D11Device (3+)
    CreateBuffer: *const anyopaque, // 3
    CreateTexture1D: *const anyopaque, // 4
    CreateTexture2D: *const fn (*ID3D11Device, *const D3D11_TEXTURE2D_DESC, ?*anyopaque, *?*ID3D11Texture2D) callconv(.c) HRESULT, // 5
    CreateTexture3D: *const anyopaque, // 6
    CreateShaderResourceView: *const anyopaque, // 7
    CreateUnorderedAccessView: *const anyopaque, // 8
    CreateRenderTargetView: *const fn (*ID3D11Device, *anyopaque, ?*const D3D11_RENDER_TARGET_VIEW_DESC, *?*ID3D11RenderTargetView) callconv(.c) HRESULT, // 9
    // ... more methods
};

pub const ID3D11Device = extern struct {
    vtable: *const ID3D11DeviceVtbl,
};

/// ID3D11DeviceContext vtable - public so other D3D11 modules can use it (DRY)
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
    VSSetConstantBuffers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*anyopaque) callconv(.c) void, // 7
    PSSetShaderResources: *const anyopaque, // 8
    PSSetShader: *const anyopaque, // 9
    PSSetSamplers: *const anyopaque, // 10
    VSSetShader: *const anyopaque, // 11
    DrawIndexed: *const anyopaque, // 12
    Draw: *const fn (*ID3D11DeviceContext, UINT, UINT) callconv(.c) void, // 13
    Map: *const anyopaque, // 14
    Unmap: *const anyopaque, // 15
    PSSetConstantBuffers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*anyopaque) callconv(.c) void, // 16
    IASetInputLayout: *const anyopaque, // 17
    IASetVertexBuffers: *const anyopaque, // 18
    IASetIndexBuffer: *const anyopaque, // 19
    DrawIndexedInstanced: *const anyopaque, // 20
    DrawInstanced: *const fn (*ID3D11DeviceContext, UINT, UINT, UINT, UINT) callconv(.c) void, // 21
    GSSetConstantBuffers: *const anyopaque, // 22
    GSSetShader: *const anyopaque, // 23
    IASetPrimitiveTopology: *const fn (*ID3D11DeviceContext, UINT) callconv(.c) void, // 24
    VSSetShaderResources: *const anyopaque, // 25
    VSSetSamplers: *const anyopaque, // 26
    Begin: *const anyopaque, // 27
    End: *const anyopaque, // 28
    GetData: *const anyopaque, // 29
    SetPredication: *const anyopaque, // 30
    GSSetShaderResources: *const anyopaque, // 31
    GSSetSamplers: *const anyopaque, // 32
    OMSetRenderTargets: *const fn (*ID3D11DeviceContext, UINT, [*]const ?*ID3D11RenderTargetView, ?*anyopaque) callconv(.c) void, // 33
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
    RSSetViewports: *const fn (*ID3D11DeviceContext, UINT, [*]const D3D11_VIEWPORT) callconv(.c) void, // 44
    RSSetScissorRects: *const anyopaque, // 45
    CopySubresourceRegion: *const anyopaque, // 46
    CopyResource: *const fn (*ID3D11DeviceContext, *anyopaque, *anyopaque) callconv(.c) void, // 47
    UpdateSubresource: *const anyopaque, // 48
    CopyStructureCount: *const anyopaque, // 49
    ClearRenderTargetView: *const fn (*ID3D11DeviceContext, *ID3D11RenderTargetView, *const [4]f32) callconv(.c) void, // 50
};

/// D3D11 viewport structure - public for RenderPass
pub const D3D11_VIEWPORT = extern struct {
    TopLeftX: f32,
    TopLeftY: f32,
    Width: f32,
    Height: f32,
    MinDepth: f32,
    MaxDepth: f32,
};

pub const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVtbl,
};

test {
    _ = Target;
}
