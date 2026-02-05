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

pub fn init(opts: Options) !Target {
    // TODO: Create D3D11 render target texture and view
    return Target{
        .rtv = null,
        .texture = null,
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
// D3D11 Type Definitions
// =============================================================================

const UINT = u32;
const HRESULT = i32;
const GUID = extern struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };

const DXGI_FORMAT_R8G8B8A8_UNORM = 28;
const DXGI_FORMAT_R8G8B8A8_UNORM_SRGB = 29;

const ID3D11RenderTargetViewVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11RenderTargetView, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11RenderTargetView) callconv(.C) u32,
    Release: *const fn (*ID3D11RenderTargetView) callconv(.C) u32,
};

const ID3D11RenderTargetView = extern struct {
    vtable: *const ID3D11RenderTargetViewVtbl,
};

const ID3D11Texture2DVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11Texture2D, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11Texture2D) callconv(.C) u32,
    Release: *const fn (*ID3D11Texture2D) callconv(.C) u32,
};

const ID3D11Texture2D = extern struct {
    vtable: *const ID3D11Texture2DVtbl,
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
