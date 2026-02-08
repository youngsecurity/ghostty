//! Direct3D 11 Buffer
//!
//! GPU buffer for vertex data, index data, constant buffers, etc.
//! This is a typed buffer similar to Metal's implementation.
//!
const std = @import("std");

const log = std.log.scoped(.d3d11_buffer);

/// Options for initializing a buffer.
pub const Options = struct {
    device: ?*ID3D11Device = null,
    context: ?*ID3D11DeviceContext = null,
    usage: Usage = .dynamic,
    cpu_access: CPUAccess = .write,
    bind_flags: BindFlags = .{ .vertex_buffer = true },
};

pub const Usage = enum(u32) {
    default = D3D11_USAGE_DEFAULT,
    immutable = D3D11_USAGE_IMMUTABLE,
    dynamic = D3D11_USAGE_DYNAMIC,
    staging = D3D11_USAGE_STAGING,
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

pub const Error = error{
    BufferCreationFailed,
    MapFailed,
};

/// Direct3D 11 typed buffer for vertex data, instance data, constant buffers, etc.
/// Similar to Metal's Buffer(T) pattern for type-safe GPU buffers.
pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The options this buffer was initialized with.
        opts: Options,

        /// D3D11 buffer object
        buffer: ?*ID3D11Buffer,

        /// The allocated length of the buffer (number of T elements).
        len: usize,

        /// Initialize a buffer with the given length pre-allocated.
        pub fn init(opts: Options, len: usize) Error!Self {
            const device = opts.device orelse return Error.BufferCreationFailed;

            const size_bytes = len * @sizeOf(T);

            const desc = D3D11_BUFFER_DESC{
                .ByteWidth = @intCast(size_bytes),
                .Usage = @intFromEnum(opts.usage),
                .BindFlags = @bitCast(opts.bind_flags),
                .CPUAccessFlags = opts.cpu_access.toD3D11(),
                .MiscFlags = 0,
                .StructureByteStride = 0,
            };

            var buffer: ?*ID3D11Buffer = null;
            const hr = device.vtable.CreateBuffer(device, &desc, null, &buffer);
            if (hr < 0 or buffer == null) {
                log.err("CreateBuffer failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
                return Error.BufferCreationFailed;
            }

            log.debug("Created buffer len={} size={} bytes", .{ len, size_bytes });

            return .{
                .opts = opts,
                .buffer = buffer,
                .len = len,
            };
        }

        /// Init the buffer filled with the given data.
        pub fn initFill(opts: Options, data: []const T) Error!Self {
            const device = opts.device orelse return Error.BufferCreationFailed;

            const size_bytes = data.len * @sizeOf(T);

            const desc = D3D11_BUFFER_DESC{
                .ByteWidth = @intCast(size_bytes),
                .Usage = @intFromEnum(opts.usage),
                .BindFlags = @bitCast(opts.bind_flags),
                .CPUAccessFlags = opts.cpu_access.toD3D11(),
                .MiscFlags = 0,
                .StructureByteStride = 0,
            };

            const init_data = D3D11_SUBRESOURCE_DATA{
                .pSysMem = @ptrCast(data.ptr),
                .SysMemPitch = 0,
                .SysMemSlicePitch = 0,
            };

            var buffer: ?*ID3D11Buffer = null;
            const hr = device.vtable.CreateBuffer(device, &desc, &init_data, &buffer);
            if (hr < 0 or buffer == null) {
                log.err("CreateBuffer with data failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
                return Error.BufferCreationFailed;
            }

            return .{
                .opts = opts,
                .buffer = buffer,
                .len = data.len,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.buffer) |buf| {
                _ = buf.vtable.Release(buf);
                self.buffer = null;
            }
        }

        /// Sync new contents to the buffer. The data is expected to be the
        /// complete contents of the buffer. If the amount of data is larger
        /// than the buffer length, the buffer will be reallocated.
        pub fn sync(self: *Self, data: []const T) Error!void {
            const context = self.opts.context orelse return;

            const req_bytes = data.len * @sizeOf(T);
            const avail_bytes = self.len * @sizeOf(T);

            // If we need more bytes than our buffer has, we need to reallocate.
            if (req_bytes > avail_bytes) {
                // Release the old buffer
                if (self.buffer) |buf| {
                    _ = buf.vtable.Release(buf);
                }

                // Allocate a new buffer with enough to hold double what we require.
                const new_len = data.len * 2;
                const new_size = new_len * @sizeOf(T);

                const device = self.opts.device orelse return Error.BufferCreationFailed;

                const desc = D3D11_BUFFER_DESC{
                    .ByteWidth = @intCast(new_size),
                    .Usage = @intFromEnum(self.opts.usage),
                    .BindFlags = @bitCast(self.opts.bind_flags),
                    .CPUAccessFlags = self.opts.cpu_access.toD3D11(),
                    .MiscFlags = 0,
                    .StructureByteStride = 0,
                };

                var buffer: ?*ID3D11Buffer = null;
                const hr = device.vtable.CreateBuffer(device, &desc, null, &buffer);
                if (hr < 0 or buffer == null) {
                    log.err("CreateBuffer realloc failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
                    return Error.BufferCreationFailed;
                }

                self.buffer = buffer;
                self.len = new_len;

                log.debug("Reallocated buffer to len={} size={} bytes", .{ new_len, new_size });
            }

            const buffer = self.buffer orelse return;

            // Map the buffer and copy data
            var mapped: D3D11_MAPPED_SUBRESOURCE = undefined;
            const hr = context.vtable.Map(
                context,
                @ptrCast(buffer),
                0,
                D3D11_MAP_WRITE_DISCARD,
                0,
                &mapped,
            );
            if (hr < 0 or mapped.pData == null) {
                log.err("Map failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
                return Error.MapFailed;
            }

            // Copy the data
            const dst: [*]u8 = @ptrCast(mapped.pData);
            const src: [*]const u8 = @ptrCast(data.ptr);
            @memcpy(dst[0..req_bytes], src[0..req_bytes]);

            // Unmap
            context.vtable.Unmap(context, @ptrCast(buffer), 0);
        }

        /// Like Buffer.sync but takes data from an array of ArrayLists,
        /// rather than a single array. Returns the number of items synced.
        pub fn syncFromArrayLists(self: *Self, lists: []const std.ArrayListUnmanaged(T)) Error!usize {
            const context = self.opts.context orelse return 0;

            var total_len: usize = 0;
            for (lists) |list| {
                total_len += list.items.len;
            }

            if (total_len == 0) return 0;

            const req_bytes = total_len * @sizeOf(T);
            const avail_bytes = self.len * @sizeOf(T);

            // If we need more bytes than our buffer has, we need to reallocate.
            if (req_bytes > avail_bytes) {
                // Release the old buffer
                if (self.buffer) |buf| {
                    _ = buf.vtable.Release(buf);
                }

                // Allocate a new buffer with enough to hold double what we require.
                const new_len = total_len * 2;
                const new_size = new_len * @sizeOf(T);

                const device = self.opts.device orelse return Error.BufferCreationFailed;

                const desc = D3D11_BUFFER_DESC{
                    .ByteWidth = @intCast(new_size),
                    .Usage = @intFromEnum(self.opts.usage),
                    .BindFlags = @bitCast(self.opts.bind_flags),
                    .CPUAccessFlags = self.opts.cpu_access.toD3D11(),
                    .MiscFlags = 0,
                    .StructureByteStride = 0,
                };

                var buffer: ?*ID3D11Buffer = null;
                const hr = device.vtable.CreateBuffer(device, &desc, null, &buffer);
                if (hr < 0 or buffer == null) {
                    log.err("CreateBuffer realloc failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
                    return Error.BufferCreationFailed;
                }

                self.buffer = buffer;
                self.len = new_len;
            }

            const buffer = self.buffer orelse return 0;

            // Map the buffer
            var mapped: D3D11_MAPPED_SUBRESOURCE = undefined;
            const hr = context.vtable.Map(
                context,
                @ptrCast(buffer),
                0,
                D3D11_MAP_WRITE_DISCARD,
                0,
                &mapped,
            );
            if (hr < 0 or mapped.pData == null) {
                log.err("Map failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
                return Error.MapFailed;
            }

            // Copy data from each list
            var offset: usize = 0;
            const dst: [*]u8 = @ptrCast(mapped.pData);
            for (lists) |list| {
                const item_bytes = list.items.len * @sizeOf(T);
                const src: [*]const u8 = @ptrCast(list.items.ptr);
                @memcpy(dst[offset .. offset + item_bytes], src[0..item_bytes]);
                offset += item_bytes;
            }

            // Unmap
            context.vtable.Unmap(context, @ptrCast(buffer), 0);

            return total_len;
        }

        /// Bind as vertex buffer
        pub fn bindAsVertexBuffer(self: *const Self, context_ptr: *anyopaque, slot: u32, offset: u32) void {
            const context: *ID3D11DeviceContext = @ptrCast(@alignCast(context_ptr));
            if (self.buffer) |buf| {
                const buffers = [_]?*ID3D11Buffer{buf};
                const stride: u32 = @sizeOf(T);
                const strides = [_]u32{stride};
                const offsets = [_]u32{offset};
                context.vtable.IASetVertexBuffers(context, slot, 1, &buffers, &strides, &offsets);
            }
        }

        /// Bind as index buffer
        pub fn bindAsIndexBuffer(self: *const Self, context_ptr: *anyopaque, format: u32, offset: u32) void {
            const context: *ID3D11DeviceContext = @ptrCast(@alignCast(context_ptr));
            if (self.buffer) |buf| {
                context.vtable.IASetIndexBuffer(context, buf, format, offset);
            }
        }

        /// Bind as constant buffer to vertex shader
        pub fn bindAsVSConstantBuffer(self: *const Self, context_ptr: *anyopaque, slot: u32) void {
            const context: *ID3D11DeviceContext = @ptrCast(@alignCast(context_ptr));
            if (self.buffer) |buf| {
                const buffers = [_]?*ID3D11Buffer{buf};
                context.vtable.VSSetConstantBuffers(context, slot, 1, &buffers);
            }
        }

        /// Bind as constant buffer to pixel shader
        pub fn bindAsPSConstantBuffer(self: *const Self, context_ptr: *anyopaque, slot: u32) void {
            const context: *ID3D11DeviceContext = @ptrCast(@alignCast(context_ptr));
            if (self.buffer) |buf| {
                const buffers = [_]?*ID3D11Buffer{buf};
                context.vtable.PSSetConstantBuffers(context, slot, 1, &buffers);
            }
        }
    };
}

// =============================================================================
// D3D11 Constants
// =============================================================================

const D3D11_USAGE_DEFAULT = 0;
const D3D11_USAGE_IMMUTABLE = 1;
const D3D11_USAGE_DYNAMIC = 2;
const D3D11_USAGE_STAGING = 3;

const D3D11_CPU_ACCESS_WRITE = 0x10000;
const D3D11_CPU_ACCESS_READ = 0x20000;

const D3D11_MAP_READ = 1;
const D3D11_MAP_WRITE = 2;
const D3D11_MAP_READ_WRITE = 3;
const D3D11_MAP_WRITE_DISCARD = 4;
const D3D11_MAP_WRITE_NO_OVERWRITE = 5;

// =============================================================================
// D3D11 Type Definitions
// =============================================================================

const HRESULT = i32;
const UINT = u32;
const GUID = extern struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };

/// D3D11_BUFFER_DESC
const D3D11_BUFFER_DESC = extern struct {
    ByteWidth: UINT,
    Usage: UINT,
    BindFlags: UINT,
    CPUAccessFlags: UINT,
    MiscFlags: UINT,
    StructureByteStride: UINT,
};

/// D3D11_SUBRESOURCE_DATA
const D3D11_SUBRESOURCE_DATA = extern struct {
    pSysMem: ?*const anyopaque,
    SysMemPitch: UINT,
    SysMemSlicePitch: UINT,
};

/// D3D11_MAPPED_SUBRESOURCE
const D3D11_MAPPED_SUBRESOURCE = extern struct {
    pData: ?*anyopaque,
    RowPitch: UINT,
    DepthPitch: UINT,
};

// ID3D11Buffer COM interface
const ID3D11BufferVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*ID3D11Buffer, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ID3D11Buffer) callconv(.c) u32,
    Release: *const fn (*ID3D11Buffer) callconv(.c) u32,
    // ID3D11DeviceChild
    GetDevice: *const anyopaque,
    GetPrivateData: *const anyopaque,
    SetPrivateData: *const anyopaque,
    SetPrivateDataInterface: *const anyopaque,
    // ID3D11Resource
    GetType: *const anyopaque,
    SetEvictionPriority: *const anyopaque,
    GetEvictionPriority: *const anyopaque,
    // ID3D11Buffer
    GetDesc: *const anyopaque,
};

pub const ID3D11Buffer = extern struct {
    vtable: *const ID3D11BufferVtbl,
};

// ID3D11Device COM interface (partial - methods we need)
const ID3D11DeviceVtbl = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const anyopaque,
    AddRef: *const anyopaque,
    Release: *const anyopaque,
    // ID3D11Device methods (3+)
    CreateBuffer: *const fn (
        *ID3D11Device,
        *const D3D11_BUFFER_DESC,
        ?*const D3D11_SUBRESOURCE_DATA,
        *?*ID3D11Buffer,
    ) callconv(.c) HRESULT,
    // ... more methods
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
    VSSetConstantBuffers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11Buffer) callconv(.c) void, // 7
    PSSetShaderResources: *const anyopaque, // 8
    PSSetShader: *const anyopaque, // 9
    PSSetSamplers: *const anyopaque, // 10
    VSSetShader: *const anyopaque, // 11
    DrawIndexed: *const anyopaque, // 12
    Draw: *const anyopaque, // 13
    Map: *const fn (*ID3D11DeviceContext, ?*anyopaque, UINT, UINT, UINT, *D3D11_MAPPED_SUBRESOURCE) callconv(.c) HRESULT, // 14
    Unmap: *const fn (*ID3D11DeviceContext, ?*anyopaque, UINT) callconv(.c) void, // 15
    PSSetConstantBuffers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11Buffer) callconv(.c) void, // 16
    IASetInputLayout: *const anyopaque, // 17
    IASetVertexBuffers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11Buffer, [*]const UINT, [*]const UINT) callconv(.c) void, // 18
    IASetIndexBuffer: *const fn (*ID3D11DeviceContext, *ID3D11Buffer, UINT, UINT) callconv(.c) void, // 19
    // ... more methods
};

pub const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVtbl,
};

test {
    _ = Buffer(u8);
    _ = Buffer(u32);
}
