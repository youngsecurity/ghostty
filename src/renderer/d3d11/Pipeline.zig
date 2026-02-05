//! Direct3D 11 Pipeline
//!
//! Represents a graphics pipeline configuration including shaders,
//! input layout, blend state, rasterizer state, etc.
//!
const Pipeline = @This();

const std = @import("std");

const log = std.log.scoped(.d3d11_pipeline);

/// Vertex shader
vertex_shader: ?*ID3D11VertexShader,

/// Pixel shader
pixel_shader: ?*ID3D11PixelShader,

/// Input layout
input_layout: ?*ID3D11InputLayout,

/// Blend state
blend_state: ?*ID3D11BlendState,

/// Rasterizer state
rasterizer_state: ?*ID3D11RasterizerState,

/// Depth stencil state
depth_stencil_state: ?*ID3D11DepthStencilState,

pub const Options = struct {
    device: ?*ID3D11Device = null,
    vertex_shader_bytecode: ?[]const u8 = null,
    pixel_shader_bytecode: ?[]const u8 = null,
    blend_enabled: bool = true,
    depth_test_enabled: bool = false,
};

pub fn init(opts: Options) !Pipeline {
    const device = opts.device orelse return error.NoDevice;

    var pipeline = Pipeline{
        .vertex_shader = null,
        .pixel_shader = null,
        .input_layout = null,
        .blend_state = null,
        .rasterizer_state = null,
        .depth_stencil_state = null,
    };
    errdefer pipeline.deinit();

    // Create vertex shader
    if (opts.vertex_shader_bytecode) |bytecode| {
        const hr = device.vtable.CreateVertexShader(
            device,
            bytecode.ptr,
            bytecode.len,
            null, // class linkage
            &pipeline.vertex_shader,
        );
        if (hr < 0) {
            log.err("CreateVertexShader failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
            return error.ShaderCreationFailed;
        }
    }

    // Create pixel shader
    if (opts.pixel_shader_bytecode) |bytecode| {
        const hr = device.vtable.CreatePixelShader(
            device,
            bytecode.ptr,
            bytecode.len,
            null, // class linkage
            &pipeline.pixel_shader,
        );
        if (hr < 0) {
            log.err("CreatePixelShader failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
            return error.ShaderCreationFailed;
        }
    }

    // Create blend state
    if (opts.blend_enabled) {
        const blend_desc = D3D11_BLEND_DESC{
            .AlphaToCoverageEnable = 0,
            .IndependentBlendEnable = 0,
            .RenderTarget = .{
                .{
                    .BlendEnable = 1,
                    .SrcBlend = D3D11_BLEND_SRC_ALPHA,
                    .DestBlend = D3D11_BLEND_INV_SRC_ALPHA,
                    .BlendOp = D3D11_BLEND_OP_ADD,
                    .SrcBlendAlpha = D3D11_BLEND_ONE,
                    .DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA,
                    .BlendOpAlpha = D3D11_BLEND_OP_ADD,
                    .RenderTargetWriteMask = 0x0F,
                },
            } ++ [_]D3D11_RENDER_TARGET_BLEND_DESC{.{}} ** 7,
        };

        const hr = device.vtable.CreateBlendState(device, &blend_desc, &pipeline.blend_state);
        if (hr < 0) {
            log.err("CreateBlendState failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
            return error.StateCreationFailed;
        }
    }

    // Create rasterizer state
    {
        const raster_desc = D3D11_RASTERIZER_DESC{
            .FillMode = D3D11_FILL_SOLID,
            .CullMode = D3D11_CULL_NONE,
            .FrontCounterClockwise = 0,
            .DepthBias = 0,
            .DepthBiasClamp = 0.0,
            .SlopeScaledDepthBias = 0.0,
            .DepthClipEnable = 1,
            .ScissorEnable = 0,
            .MultisampleEnable = 0,
            .AntialiasedLineEnable = 0,
        };

        const hr = device.vtable.CreateRasterizerState(device, &raster_desc, &pipeline.rasterizer_state);
        if (hr < 0) {
            log.err("CreateRasterizerState failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
            return error.StateCreationFailed;
        }
    }

    log.debug("Created pipeline", .{});
    return pipeline;
}

pub fn deinit(self: *Pipeline) void {
    if (self.vertex_shader) |vs| {
        _ = vs.vtable.Release(vs);
        self.vertex_shader = null;
    }
    if (self.pixel_shader) |ps| {
        _ = ps.vtable.Release(ps);
        self.pixel_shader = null;
    }
    if (self.input_layout) |il| {
        _ = il.vtable.Release(il);
        self.input_layout = null;
    }
    if (self.blend_state) |bs| {
        _ = bs.vtable.Release(bs);
        self.blend_state = null;
    }
    if (self.rasterizer_state) |rs| {
        _ = rs.vtable.Release(rs);
        self.rasterizer_state = null;
    }
    if (self.depth_stencil_state) |dss| {
        _ = dss.vtable.Release(dss);
        self.depth_stencil_state = null;
    }
}

/// Bind this pipeline to the device context
pub fn bind(self: *const Pipeline, context: *ID3D11DeviceContext) void {
    // Set vertex shader
    if (self.vertex_shader) |vs| {
        context.vtable.VSSetShader(context, vs, null, 0);
    }

    // Set pixel shader
    if (self.pixel_shader) |ps| {
        context.vtable.PSSetShader(context, ps, null, 0);
    }

    // Set input layout
    if (self.input_layout) |il| {
        context.vtable.IASetInputLayout(context, il);
    }

    // Set blend state
    if (self.blend_state) |bs| {
        const blend_factor = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
        context.vtable.OMSetBlendState(context, bs, &blend_factor, 0xFFFFFFFF);
    }

    // Set rasterizer state
    if (self.rasterizer_state) |rs| {
        context.vtable.RSSetState(context, rs);
    }

    // Set depth stencil state
    if (self.depth_stencil_state) |dss| {
        context.vtable.OMSetDepthStencilState(context, dss, 0);
    }
}

// =============================================================================
// D3D11 Constants
// =============================================================================

const D3D11_BLEND_ZERO = 1;
const D3D11_BLEND_ONE = 2;
const D3D11_BLEND_SRC_ALPHA = 5;
const D3D11_BLEND_INV_SRC_ALPHA = 6;

const D3D11_BLEND_OP_ADD = 1;

const D3D11_FILL_SOLID = 3;
const D3D11_CULL_NONE = 1;

// =============================================================================
// D3D11 Type Definitions
// =============================================================================

const HRESULT = i32;
const UINT = u32;
const BOOL = i32;
const FLOAT = f32;
const UINT8 = u8;
const GUID = extern struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };

const IUnknownVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
};

pub const ID3D11VertexShader = extern struct {
    vtable: *const IUnknownVtbl,
};

pub const ID3D11PixelShader = extern struct {
    vtable: *const IUnknownVtbl,
};

pub const ID3D11InputLayout = extern struct {
    vtable: *const IUnknownVtbl,
};

pub const ID3D11BlendState = extern struct {
    vtable: *const IUnknownVtbl,
};

pub const ID3D11RasterizerState = extern struct {
    vtable: *const IUnknownVtbl,
};

pub const ID3D11DepthStencilState = extern struct {
    vtable: *const IUnknownVtbl,
};

const D3D11_RENDER_TARGET_BLEND_DESC = extern struct {
    BlendEnable: BOOL = 0,
    SrcBlend: UINT = D3D11_BLEND_ONE,
    DestBlend: UINT = D3D11_BLEND_ZERO,
    BlendOp: UINT = D3D11_BLEND_OP_ADD,
    SrcBlendAlpha: UINT = D3D11_BLEND_ONE,
    DestBlendAlpha: UINT = D3D11_BLEND_ZERO,
    BlendOpAlpha: UINT = D3D11_BLEND_OP_ADD,
    RenderTargetWriteMask: UINT8 = 0x0F,
};

const D3D11_BLEND_DESC = extern struct {
    AlphaToCoverageEnable: BOOL,
    IndependentBlendEnable: BOOL,
    RenderTarget: [8]D3D11_RENDER_TARGET_BLEND_DESC,
};

const D3D11_RASTERIZER_DESC = extern struct {
    FillMode: UINT,
    CullMode: UINT,
    FrontCounterClockwise: BOOL,
    DepthBias: i32,
    DepthBiasClamp: FLOAT,
    SlopeScaledDepthBias: FLOAT,
    DepthClipEnable: BOOL,
    ScissorEnable: BOOL,
    MultisampleEnable: BOOL,
    AntialiasedLineEnable: BOOL,
};

// ID3D11Device COM interface
const ID3D11DeviceVtbl = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const anyopaque,
    AddRef: *const anyopaque,
    Release: *const anyopaque,
    // ID3D11Device (3+)
    CreateBuffer: *const anyopaque, // 3
    CreateTexture1D: *const anyopaque, // 4
    CreateTexture2D: *const anyopaque, // 5
    CreateTexture3D: *const anyopaque, // 6
    CreateShaderResourceView: *const anyopaque, // 7
    CreateUnorderedAccessView: *const anyopaque, // 8
    CreateRenderTargetView: *const anyopaque, // 9
    CreateDepthStencilView: *const anyopaque, // 10
    CreateInputLayout: *const anyopaque, // 11
    CreateVertexShader: *const fn (*ID3D11Device, [*]const u8, usize, ?*anyopaque, *?*ID3D11VertexShader) callconv(.c) HRESULT, // 12
    CreateGeometryShader: *const anyopaque, // 13
    CreateGeometryShaderWithStreamOutput: *const anyopaque, // 14
    CreatePixelShader: *const fn (*ID3D11Device, [*]const u8, usize, ?*anyopaque, *?*ID3D11PixelShader) callconv(.c) HRESULT, // 15
    CreateHullShader: *const anyopaque, // 16
    CreateDomainShader: *const anyopaque, // 17
    CreateComputeShader: *const anyopaque, // 18
    CreateClassLinkage: *const anyopaque, // 19
    CreateBlendState: *const fn (*ID3D11Device, *const D3D11_BLEND_DESC, *?*ID3D11BlendState) callconv(.c) HRESULT, // 20
    CreateDepthStencilState: *const anyopaque, // 21
    CreateRasterizerState: *const fn (*ID3D11Device, *const D3D11_RASTERIZER_DESC, *?*ID3D11RasterizerState) callconv(.c) HRESULT, // 22
    // ... more methods
};

pub const ID3D11Device = extern struct {
    vtable: *const ID3D11DeviceVtbl,
};

// ID3D11DeviceContext COM interface
const ID3D11DeviceContextVtbl = extern struct {
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
    PSSetShaderResources: *const anyopaque, // 8
    PSSetShader: *const fn (*ID3D11DeviceContext, ?*ID3D11PixelShader, ?*anyopaque, UINT) callconv(.c) void, // 9
    PSSetSamplers: *const anyopaque, // 10
    VSSetShader: *const fn (*ID3D11DeviceContext, ?*ID3D11VertexShader, ?*anyopaque, UINT) callconv(.c) void, // 11
    DrawIndexed: *const anyopaque, // 12
    Draw: *const anyopaque, // 13
    Map: *const anyopaque, // 14
    Unmap: *const anyopaque, // 15
    PSSetConstantBuffers: *const anyopaque, // 16
    IASetInputLayout: *const fn (*ID3D11DeviceContext, ?*ID3D11InputLayout) callconv(.c) void, // 17
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
    OMSetBlendState: *const fn (*ID3D11DeviceContext, ?*ID3D11BlendState, ?*const [4]f32, UINT) callconv(.c) void, // 35
    OMSetDepthStencilState: *const fn (*ID3D11DeviceContext, ?*ID3D11DepthStencilState, UINT) callconv(.c) void, // 36
    SOSetTargets: *const anyopaque, // 37
    DrawAuto: *const anyopaque, // 38
    DrawIndexedInstancedIndirect: *const anyopaque, // 39
    DrawInstancedIndirect: *const anyopaque, // 40
    Dispatch: *const anyopaque, // 41
    DispatchIndirect: *const anyopaque, // 42
    RSSetState: *const fn (*ID3D11DeviceContext, ?*ID3D11RasterizerState) callconv(.c) void, // 43
    // ... more methods
};

pub const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVtbl,
};

test {
    _ = Pipeline;
}
