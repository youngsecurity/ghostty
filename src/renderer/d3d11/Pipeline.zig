//! Direct3D 11 Pipeline
//!
//! Represents a graphics pipeline configuration including shaders,
//! input layout, blend state, rasterizer state, etc.
//!
const Pipeline = @This();

const std = @import("std");

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
    vertex_shader_bytecode: ?[]const u8 = null,
    pixel_shader_bytecode: ?[]const u8 = null,
    blend_enabled: bool = true,
    depth_test_enabled: bool = false,
};

pub fn init(device: *anyopaque, opts: Options) !Pipeline {
    _ = device;
    _ = opts;

    // TODO: Create shaders, input layout, states from device

    return Pipeline{
        .vertex_shader = null,
        .pixel_shader = null,
        .input_layout = null,
        .blend_state = null,
        .rasterizer_state = null,
        .depth_stencil_state = null,
    };
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
    _ = self;
    _ = context;
    // TODO: Set shaders, input layout, states on context
}

// =============================================================================
// D3D11 Type Definitions
// =============================================================================

const HRESULT = i32;
const GUID = extern struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };

const IUnknownVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.C) u32,
    Release: *const fn (*anyopaque) callconv(.C) u32,
};

const ID3D11VertexShader = extern struct {
    vtable: *const IUnknownVtbl,
};

const ID3D11PixelShader = extern struct {
    vtable: *const IUnknownVtbl,
};

const ID3D11InputLayout = extern struct {
    vtable: *const IUnknownVtbl,
};

const ID3D11BlendState = extern struct {
    vtable: *const IUnknownVtbl,
};

const ID3D11RasterizerState = extern struct {
    vtable: *const IUnknownVtbl,
};

const ID3D11DepthStencilState = extern struct {
    vtable: *const IUnknownVtbl,
};

const ID3D11DeviceContext = extern struct {
    vtable: *const anyopaque,
};

test {
    _ = Pipeline;
}
