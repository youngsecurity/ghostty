//! Direct3D 11 Sampler
//!
//! Texture sampler state for controlling texture filtering and addressing.
//!
const Sampler = @This();

const std = @import("std");

/// D3D11 sampler state object
sampler: ?*ID3D11SamplerState,

pub const Options = struct {
    filter: Filter = .linear,
    address_u: AddressMode = .clamp,
    address_v: AddressMode = .clamp,
    address_w: AddressMode = .clamp,
    max_anisotropy: u32 = 1,
    comparison_func: ComparisonFunc = .never,
    border_color: [4]f32 = .{ 0, 0, 0, 0 },
    min_lod: f32 = 0,
    max_lod: f32 = std.math.floatMax(f32),
};

pub const Filter = enum {
    point,
    linear,
    anisotropic,

    pub fn toD3D11(self: Filter) u32 {
        return switch (self) {
            .point => D3D11_FILTER_MIN_MAG_MIP_POINT,
            .linear => D3D11_FILTER_MIN_MAG_MIP_LINEAR,
            .anisotropic => D3D11_FILTER_ANISOTROPIC,
        };
    }
};

pub const AddressMode = enum {
    wrap,
    mirror,
    clamp,
    border,
    mirror_once,

    pub fn toD3D11(self: AddressMode) u32 {
        return switch (self) {
            .wrap => D3D11_TEXTURE_ADDRESS_WRAP,
            .mirror => D3D11_TEXTURE_ADDRESS_MIRROR,
            .clamp => D3D11_TEXTURE_ADDRESS_CLAMP,
            .border => D3D11_TEXTURE_ADDRESS_BORDER,
            .mirror_once => D3D11_TEXTURE_ADDRESS_MIRROR_ONCE,
        };
    }
};

pub const ComparisonFunc = enum {
    never,
    less,
    equal,
    less_equal,
    greater,
    not_equal,
    greater_equal,
    always,

    pub fn toD3D11(self: ComparisonFunc) u32 {
        return switch (self) {
            .never => D3D11_COMPARISON_NEVER,
            .less => D3D11_COMPARISON_LESS,
            .equal => D3D11_COMPARISON_EQUAL,
            .less_equal => D3D11_COMPARISON_LESS_EQUAL,
            .greater => D3D11_COMPARISON_GREATER,
            .not_equal => D3D11_COMPARISON_NOT_EQUAL,
            .greater_equal => D3D11_COMPARISON_GREATER_EQUAL,
            .always => D3D11_COMPARISON_ALWAYS,
        };
    }
};

pub fn init(device: *anyopaque, opts: Options) !Sampler {
    _ = device;
    _ = opts;

    // TODO: Create D3D11 sampler state via ID3D11Device::CreateSamplerState

    return Sampler{
        .sampler = null,
    };
}

pub fn deinit(self: *Sampler) void {
    if (self.sampler) |s| {
        _ = s.vtable.Release(s);
        self.sampler = null;
    }
}

/// Bind to pixel shader
pub fn bindToPixelShader(self: *const Sampler, context: *ID3D11DeviceContext, slot: u32) void {
    if (self.sampler) |s| {
        const samplers = [_]?*ID3D11SamplerState{s};
        context.vtable.PSSetSamplers(context, slot, 1, &samplers);
    }
}

/// Bind to vertex shader
pub fn bindToVertexShader(self: *const Sampler, context: *ID3D11DeviceContext, slot: u32) void {
    if (self.sampler) |s| {
        const samplers = [_]?*ID3D11SamplerState{s};
        context.vtable.VSSetSamplers(context, slot, 1, &samplers);
    }
}

// =============================================================================
// D3D11 Constants
// =============================================================================

const D3D11_FILTER_MIN_MAG_MIP_POINT = 0;
const D3D11_FILTER_MIN_MAG_MIP_LINEAR = 0x15;
const D3D11_FILTER_ANISOTROPIC = 0x55;

const D3D11_TEXTURE_ADDRESS_WRAP = 1;
const D3D11_TEXTURE_ADDRESS_MIRROR = 2;
const D3D11_TEXTURE_ADDRESS_CLAMP = 3;
const D3D11_TEXTURE_ADDRESS_BORDER = 4;
const D3D11_TEXTURE_ADDRESS_MIRROR_ONCE = 5;

const D3D11_COMPARISON_NEVER = 1;
const D3D11_COMPARISON_LESS = 2;
const D3D11_COMPARISON_EQUAL = 3;
const D3D11_COMPARISON_LESS_EQUAL = 4;
const D3D11_COMPARISON_GREATER = 5;
const D3D11_COMPARISON_NOT_EQUAL = 6;
const D3D11_COMPARISON_GREATER_EQUAL = 7;
const D3D11_COMPARISON_ALWAYS = 8;

// =============================================================================
// D3D11 Type Definitions
// =============================================================================

const HRESULT = i32;
const UINT = u32;
const GUID = extern struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };

const ID3D11SamplerStateVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11SamplerState, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11SamplerState) callconv(.C) u32,
    Release: *const fn (*ID3D11SamplerState) callconv(.C) u32,
};

const ID3D11SamplerState = extern struct {
    vtable: *const ID3D11SamplerStateVtbl,
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
    PSSetSamplers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11SamplerState) callconv(.C) void,
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
    VSSetSamplers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11SamplerState) callconv(.C) void,
};

const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVtbl,
};

test {
    _ = Sampler;
}
