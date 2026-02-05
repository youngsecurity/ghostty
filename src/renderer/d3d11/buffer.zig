//! Direct3D 11 Buffer
//!
//! GPU buffer for vertex data, index data, constant buffers, etc.
//!
const std = @import("std");

pub const Buffer = struct {
    /// D3D11 buffer object
    buffer: ?*ID3D11Buffer,

    /// Buffer size in bytes
    size: usize,

    /// Buffer usage
    usage: Usage,

    pub const Usage = enum {
        default,
        immutable,
        dynamic,
        staging,

        pub fn toD3D11(self: Usage) u32 {
            return switch (self) {
                .default => D3D11_USAGE_DEFAULT,
                .immutable => D3D11_USAGE_IMMUTABLE,
                .dynamic => D3D11_USAGE_DYNAMIC,
                .staging => D3D11_USAGE_STAGING,
            };
        }
    };

    pub const CPUAccess = enum {
        none,
        write,
        read,
        read_write,

        pub fn toD3D11(self: CPUAccess) u32 {
            return switch (self) {
                .none => 0,
                .write => D3D11_CPU_ACCESS_WRITE,
                .read => D3D11_CPU_ACCESS_READ,
                .read_write => D3D11_CPU_ACCESS_WRITE | D3D11_CPU_ACCESS_READ,
            };
        }
    };

    pub const BindFlags = packed struct {
        vertex_buffer: bool = false,
        index_buffer: bool = false,
        constant_buffer: bool = false,
        shader_resource: bool = false,
        stream_output: bool = false,
        render_target: bool = false,
        depth_stencil: bool = false,
        unordered_access: bool = false,

        pub fn toD3D11(self: BindFlags) u32 {
            var flags: u32 = 0;
            if (self.vertex_buffer) flags |= D3D11_BIND_VERTEX_BUFFER;
            if (self.index_buffer) flags |= D3D11_BIND_INDEX_BUFFER;
            if (self.constant_buffer) flags |= D3D11_BIND_CONSTANT_BUFFER;
            if (self.shader_resource) flags |= D3D11_BIND_SHADER_RESOURCE;
            if (self.stream_output) flags |= D3D11_BIND_STREAM_OUTPUT;
            if (self.render_target) flags |= D3D11_BIND_RENDER_TARGET;
            if (self.depth_stencil) flags |= D3D11_BIND_DEPTH_STENCIL;
            if (self.unordered_access) flags |= D3D11_BIND_UNORDERED_ACCESS;
            return flags;
        }
    };

    pub fn init(device: *anyopaque, size: usize, opts: Options, initial_data: ?[]const u8) !Buffer {
        _ = device;
        _ = initial_data;

        // TODO: Create D3D11 buffer via ID3D11Device::CreateBuffer

        return Buffer{
            .buffer = null,
            .size = size,
            .usage = opts.usage,
        };
    }

    pub fn deinit(self: *Buffer) void {
        if (self.buffer) |buf| {
            _ = buf.vtable.Release(buf);
            self.buffer = null;
        }
    }

    /// Update buffer contents (for dynamic buffers)
    pub fn update(self: *Buffer, context: *anyopaque, data: []const u8) !void {
        _ = self;
        _ = context;
        _ = data;
        // TODO: Map, copy, unmap for dynamic buffers
        // Or use UpdateSubresource for default buffers
    }

    /// Bind as vertex buffer
    pub fn bindAsVertexBuffer(self: *const Buffer, context: *ID3D11DeviceContext, slot: u32, stride: u32, offset: u32) void {
        if (self.buffer) |buf| {
            const buffers = [_]?*ID3D11Buffer{buf};
            const strides = [_]u32{stride};
            const offsets = [_]u32{offset};
            context.vtable.IASetVertexBuffers(context, slot, 1, &buffers, &strides, &offsets);
        }
    }

    /// Bind as index buffer
    pub fn bindAsIndexBuffer(self: *const Buffer, context: *ID3D11DeviceContext, format: u32, offset: u32) void {
        if (self.buffer) |buf| {
            context.vtable.IASetIndexBuffer(context, buf, format, offset);
        }
    }

    /// Bind as constant buffer to vertex shader
    pub fn bindAsVSConstantBuffer(self: *const Buffer, context: *ID3D11DeviceContext, slot: u32) void {
        if (self.buffer) |buf| {
            const buffers = [_]?*ID3D11Buffer{buf};
            context.vtable.VSSetConstantBuffers(context, slot, 1, &buffers);
        }
    }

    /// Bind as constant buffer to pixel shader
    pub fn bindAsPSConstantBuffer(self: *const Buffer, context: *ID3D11DeviceContext, slot: u32) void {
        if (self.buffer) |buf| {
            const buffers = [_]?*ID3D11Buffer{buf};
            context.vtable.PSSetConstantBuffers(context, slot, 1, &buffers);
        }
    }
};

pub const Options = struct {
    usage: Buffer.Usage = .dynamic,
    cpu_access: Buffer.CPUAccess = .write,
    bind_flags: Buffer.BindFlags = .{ .vertex_buffer = true },
};

// =============================================================================
// D3D11 Constants
// =============================================================================

const D3D11_USAGE_DEFAULT = 0;
const D3D11_USAGE_IMMUTABLE = 1;
const D3D11_USAGE_DYNAMIC = 2;
const D3D11_USAGE_STAGING = 3;

const D3D11_CPU_ACCESS_WRITE = 0x10000;
const D3D11_CPU_ACCESS_READ = 0x20000;

const D3D11_BIND_VERTEX_BUFFER = 0x1;
const D3D11_BIND_INDEX_BUFFER = 0x2;
const D3D11_BIND_CONSTANT_BUFFER = 0x4;
const D3D11_BIND_SHADER_RESOURCE = 0x8;
const D3D11_BIND_STREAM_OUTPUT = 0x10;
const D3D11_BIND_RENDER_TARGET = 0x20;
const D3D11_BIND_DEPTH_STENCIL = 0x40;
const D3D11_BIND_UNORDERED_ACCESS = 0x80;

// =============================================================================
// D3D11 Type Definitions
// =============================================================================

const HRESULT = i32;
const UINT = u32;
const GUID = extern struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };

const ID3D11BufferVtbl = extern struct {
    QueryInterface: *const fn (*ID3D11Buffer, *const GUID, *?*anyopaque) callconv(.C) HRESULT,
    AddRef: *const fn (*ID3D11Buffer) callconv(.C) u32,
    Release: *const fn (*ID3D11Buffer) callconv(.C) u32,
    // ... more methods
};

const ID3D11Buffer = extern struct {
    vtable: *const ID3D11BufferVtbl,
};

const ID3D11DeviceContextVtbl = extern struct {
    QueryInterface: *const anyopaque,
    AddRef: *const anyopaque,
    Release: *const anyopaque,
    GetDevice: *const anyopaque,
    GetPrivateData: *const anyopaque,
    SetPrivateData: *const anyopaque,
    SetPrivateDataInterface: *const anyopaque,
    VSSetConstantBuffers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11Buffer) callconv(.C) void,
    PSSetShaderResources: *const anyopaque,
    PSSetShader: *const anyopaque,
    PSSetSamplers: *const anyopaque,
    VSSetShader: *const anyopaque,
    DrawIndexed: *const anyopaque,
    Draw: *const anyopaque,
    Map: *const anyopaque,
    Unmap: *const anyopaque,
    PSSetConstantBuffers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11Buffer) callconv(.C) void,
    IASetInputLayout: *const anyopaque,
    IASetVertexBuffers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11Buffer, [*]const UINT, [*]const UINT) callconv(.C) void,
    IASetIndexBuffer: *const fn (*ID3D11DeviceContext, *ID3D11Buffer, UINT, UINT) callconv(.C) void,
    // ... more methods
};

const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVtbl,
};

test {
    _ = Buffer;
}
