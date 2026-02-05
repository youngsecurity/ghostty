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
    QueryInterface: *const fn (*ID3D11RenderTargetView, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11RenderTargetView) callconv(.C) u32,
    Release: *const fn (*ID3D11RenderTargetView) callconv(.C) u32,
};

pub const ID3D11RenderTargetView = extern struct {
    vtable: *const ID3D11RenderTargetViewVtbl,
};

const ID3D11Texture2DVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11Texture2D, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11Texture2D) callconv(.C) u32,
    Release: *const fn (*ID3D11Texture2D) callconv(.C) u32,
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
    CreateTexture2D: *const fn (*ID3D11Device, *const D3D11_TEXTURE2D_DESC, ?*anyopaque, *?*ID3D11Texture2D) callconv(.C) HRESULT, // 5
    CreateTexture3D: *const anyopaque, // 6
    CreateShaderResourceView: *const anyopaque, // 7
    CreateUnorderedAccessView: *const anyopaque, // 8
    CreateRenderTargetView: *const fn (*ID3D11Device, *anyopaque, ?*const D3D11_RENDER_TARGET_VIEW_DESC, *?*ID3D11RenderTargetView) callconv(.C) HRESULT, // 9
    // ... more methods
};

pub const ID3D11Device = extern struct {
    vtable: *const ID3D11DeviceVtbl,
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
    OMSetRenderTargets: *const fn (*ID3D11DeviceContext, UINT, [*]const ?*ID3D11RenderTargetView, ?*anyopaque) callconv(.C) void,
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
};

const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVtbl,
};

test {
    _ = Target;
}
