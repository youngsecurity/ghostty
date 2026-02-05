//! Direct3D 11 Shaders
//!
//! HLSL shader management for the terminal renderer.
//! Includes vertex and pixel shaders for cell rendering, background,
//! images, and custom shadertoy-style effects.
//!
const shaders = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const math = @import("../../math.zig");

const log = std.log.scoped(.d3d11_shaders);

pub const Shaders = struct {
    alloc: Allocator,

    /// Cell rendering shaders (text/glyphs)
    cell_vs: ?CompiledShader,
    cell_ps: ?CompiledShader,

    /// Background rendering shaders
    bg_vs: ?CompiledShader,
    bg_ps: ?CompiledShader,

    /// Image rendering shaders
    image_vs: ?CompiledShader,
    image_ps: ?CompiledShader,

    /// Custom shaders (shadertoy-style)
    custom_shaders: []CompiledShader,

    pub fn init(alloc: Allocator, custom_shader_sources: []const [:0]const u8) !Shaders {
        var custom_shaders = try alloc.alloc(CompiledShader, custom_shader_sources.len);
        errdefer alloc.free(custom_shaders);

        for (custom_shader_sources, 0..) |source, i| {
            custom_shaders[i] = try compileShader(alloc, source, .pixel);
        }

        return Shaders{
            .alloc = alloc,
            .cell_vs = try compileShader(alloc, cell_vertex_shader, .vertex),
            .cell_ps = try compileShader(alloc, cell_pixel_shader, .pixel),
            .bg_vs = try compileShader(alloc, bg_vertex_shader, .vertex),
            .bg_ps = try compileShader(alloc, bg_pixel_shader, .pixel),
            .image_vs = try compileShader(alloc, image_vertex_shader, .vertex),
            .image_ps = try compileShader(alloc, image_pixel_shader, .pixel),
            .custom_shaders = custom_shaders,
        };
    }

    pub fn deinit(self: *Shaders, _: Allocator) void {
        if (self.cell_vs) |*s| s.deinit();
        if (self.cell_ps) |*s| s.deinit();
        if (self.bg_vs) |*s| s.deinit();
        if (self.bg_ps) |*s| s.deinit();
        if (self.image_vs) |*s| s.deinit();
        if (self.image_ps) |*s| s.deinit();

        for (self.custom_shaders) |*s| {
            s.deinit();
        }
        self.alloc.free(self.custom_shaders);

        self.* = undefined;
    }
};

// =============================================================================
// Uniform and Vertex Types (matching Metal/OpenGL)
// =============================================================================

/// The uniforms that are passed to our shaders via constant buffer.
pub const Uniforms = extern struct {
    /// The projection matrix for turning world coordinates to normalized.
    projection_matrix: math.Mat align(16),

    /// Size of the screen (render target) in pixels.
    screen_size: [2]f32 align(8),

    /// Size of a single cell in pixels, unscaled.
    cell_size: [2]f32 align(8),

    /// Size of the grid in columns and rows.
    grid_size: [2]u16 align(4),

    /// The padding around the terminal grid in pixels. In order:
    /// top, right, bottom, left.
    grid_padding: [4]f32 align(16),

    /// Bit mask defining which directions to extend cell colors in to the padding.
    padding_extend: PaddingExtend align(1),

    /// The minimum contrast ratio for text.
    min_contrast: f32 align(4),

    /// The cursor position and color.
    cursor_pos: [2]u16 align(4),
    cursor_color: [4]u8 align(4),

    /// The background color for the whole surface.
    bg_color: [4]u8 align(4),

    /// Various booleans.
    bools: extern struct {
        cursor_wide: bool align(1),
        use_display_p3: bool align(1),
        use_linear_blending: bool align(1),
        use_linear_correction: bool align(1) = false,
    },

    pub const PaddingExtend = packed struct(u8) {
        left: bool = false,
        right: bool = false,
        up: bool = false,
        down: bool = false,
        _padding: u4 = 0,
    };
};

/// Cell text vertex data for instanced rendering.
pub const CellText = extern struct {
    glyph_pos: [2]u32 align(8) = .{ 0, 0 },
    glyph_size: [2]u32 align(8) = .{ 0, 0 },
    bearings: [2]i16 align(4) = .{ 0, 0 },
    grid_pos: [2]u16 align(4),
    color: [4]u8 align(4),
    atlas: Atlas align(1),
    bools: packed struct(u8) {
        no_min_contrast: bool = false,
        is_cursor_glyph: bool = false,
        _padding: u6 = 0,
    } align(1) = .{},

    pub const Atlas = enum(u8) {
        grayscale = 0,
        color = 1,
    };

    test {
        try std.testing.expectEqual(32, @sizeOf(CellText));
    }
};

/// Cell background color (4 bytes RGBA).
pub const CellBg = [4]u8;

/// Image vertex data for instanced rendering.
pub const Image = extern struct {
    grid_pos: [2]f32,
    cell_offset: [2]f32,
    source_rect: [4]f32,
    dest_size: [2]f32,
};

/// Background image vertex data.
pub const BgImage = extern struct {
    opacity: f32 align(4),
    info: Info align(1),

    pub const Info = packed struct(u8) {
        position: Position,
        fit: Fit,
        repeat: bool,
        _padding: u1 = 0,

        pub const Position = enum(u4) {
            tl = 0,
            tc = 1,
            tr = 2,
            ml = 3,
            mc = 4,
            mr = 5,
            bl = 6,
            bc = 7,
            br = 8,
        };

        pub const Fit = enum(u2) {
            contain = 0,
            cover = 1,
            stretch = 2,
            none = 3,
        };
    };
};

pub const CompiledShader = struct {
    /// Compiled shader bytecode (DXBC format)
    bytecode: []const u8,

    /// Allocator used for bytecode
    alloc: Allocator,

    /// Whether this was compiled or is raw source
    is_compiled: bool,

    pub fn deinit(self: *CompiledShader) void {
        self.alloc.free(self.bytecode);
        self.* = undefined;
    }

    /// Get bytecode for CreateVertexShader/CreatePixelShader
    pub fn getBytecode(self: *const CompiledShader) []const u8 {
        return self.bytecode;
    }
};

pub const ShaderType = enum {
    vertex,
    pixel,
    compute,

    fn getTarget(self: ShaderType) [*:0]const u8 {
        return switch (self) {
            .vertex => "vs_5_0",
            .pixel => "ps_5_0",
            .compute => "cs_5_0",
        };
    }
};

/// Compile an HLSL shader using D3DCompile.
/// Falls back to storing source if D3DCompile is unavailable.
fn compileShader(alloc: Allocator, source: [:0]const u8, shader_type: ShaderType) !CompiledShader {
    // Try to compile using D3DCompile
    if (compileWithD3DCompile(source, shader_type)) |bytecode| {
        // D3DCompile returns a blob, we need to copy it
        defer bytecode.release();

        const size = bytecode.getBufferSize();
        const ptr = bytecode.getBufferPointer();

        const compiled = try alloc.alloc(u8, size);
        @memcpy(compiled, @as([*]const u8, @ptrCast(ptr))[0..size]);

        log.debug("Compiled {} shader, {} bytes", .{ shader_type, size });

        return CompiledShader{
            .bytecode = compiled,
            .alloc = alloc,
            .is_compiled = true,
        };
    } else |err| {
        // D3DCompile failed or unavailable, store source for later
        log.warn("D3DCompile failed: {}, storing source", .{err});

        const bytecode = try alloc.dupe(u8, source);
        return CompiledShader{
            .bytecode = bytecode,
            .alloc = alloc,
            .is_compiled = false,
        };
    }
}

/// Call D3DCompile to compile HLSL to bytecode
fn compileWithD3DCompile(source: [:0]const u8, shader_type: ShaderType) !*ID3DBlob {
    var shader_blob: ?*ID3DBlob = null;
    var error_blob: ?*ID3DBlob = null;

    const hr = D3DCompile(
        source.ptr,
        source.len,
        null, // source name
        null, // defines
        null, // include handler
        "main", // entry point
        shader_type.getTarget(),
        D3DCOMPILE_OPTIMIZATION_LEVEL3, // flags1
        0, // flags2
        &shader_blob,
        &error_blob,
    );

    // Log error message if compilation failed
    if (error_blob) |err| {
        defer err.release();
        const msg_ptr = err.getBufferPointer();
        const msg_len = err.getBufferSize();
        if (msg_ptr != null and msg_len > 0) {
            const msg = @as([*]const u8, @ptrCast(msg_ptr))[0..msg_len];
            log.err("Shader compilation error: {s}", .{msg});
        }
    }

    if (hr < 0 or shader_blob == null) {
        return error.ShaderCompilationFailed;
    }

    return shader_blob.?;
}

// =============================================================================
// D3DCompiler API
// =============================================================================

const D3DCOMPILE_DEBUG = 0x00000001;
const D3DCOMPILE_SKIP_VALIDATION = 0x00000002;
const D3DCOMPILE_SKIP_OPTIMIZATION = 0x00000004;
const D3DCOMPILE_OPTIMIZATION_LEVEL0 = 0x00004000;
const D3DCOMPILE_OPTIMIZATION_LEVEL1 = 0x00000000;
const D3DCOMPILE_OPTIMIZATION_LEVEL2 = 0x0000c000;
const D3DCOMPILE_OPTIMIZATION_LEVEL3 = 0x00008000;

const HRESULT = i32;

const ID3DBlobVtbl = extern struct {
    QueryInterface: *const anyopaque,
    AddRef: *const fn (*ID3DBlob) callconv(.C) u32,
    Release: *const fn (*ID3DBlob) callconv(.C) u32,
    GetBufferPointer: *const fn (*ID3DBlob) callconv(.C) ?*anyopaque,
    GetBufferSize: *const fn (*ID3DBlob) callconv(.C) usize,
};

const ID3DBlob = extern struct {
    vtable: *const ID3DBlobVtbl,

    pub fn release(self: *ID3DBlob) void {
        _ = self.vtable.Release(self);
    }

    pub fn getBufferPointer(self: *ID3DBlob) ?*anyopaque {
        return self.vtable.GetBufferPointer(self);
    }

    pub fn getBufferSize(self: *ID3DBlob) usize {
        return self.vtable.GetBufferSize(self);
    }
};

extern "d3dcompiler_47" fn D3DCompile(
    pSrcData: [*]const u8,
    SrcDataSize: usize,
    pSourceName: ?[*:0]const u8,
    pDefines: ?*anyopaque,
    pInclude: ?*anyopaque,
    pEntrypoint: [*:0]const u8,
    pTarget: [*:0]const u8,
    Flags1: u32,
    Flags2: u32,
    ppCode: *?*ID3DBlob,
    ppErrorMsgs: *?*ID3DBlob,
) callconv(.C) HRESULT;

// =============================================================================
// HLSL Shader Sources
// =============================================================================

/// Vertex shader for cell (text) rendering
const cell_vertex_shader: [:0]const u8 =
    \\// Cell Vertex Shader
    \\// Transforms cell vertices and passes UV coordinates to pixel shader
    \\
    \\cbuffer ConstantBuffer : register(b0)
    \\{
    \\    float4x4 projection;
    \\    float2 cell_size;
    \\    float2 atlas_size;
    \\};
    \\
    \\struct VS_INPUT
    \\{
    \\    float2 pos : POSITION;
    \\    float2 uv : TEXCOORD0;
    \\    float4 fg_color : COLOR0;
    \\    float4 bg_color : COLOR1;
    \\    uint cell_idx : BLENDINDICES;
    \\};
    \\
    \\struct VS_OUTPUT
    \\{
    \\    float4 pos : SV_POSITION;
    \\    float2 uv : TEXCOORD0;
    \\    float4 fg_color : COLOR0;
    \\    float4 bg_color : COLOR1;
    \\};
    \\
    \\VS_OUTPUT main(VS_INPUT input)
    \\{
    \\    VS_OUTPUT output;
    \\    output.pos = mul(projection, float4(input.pos, 0.0, 1.0));
    \\    output.uv = input.uv / atlas_size;
    \\    output.fg_color = input.fg_color;
    \\    output.bg_color = input.bg_color;
    \\    return output;
    \\}
;

/// Pixel shader for cell (text) rendering
const cell_pixel_shader: [:0]const u8 =
    \\// Cell Pixel Shader
    \\// Samples the font atlas and applies foreground color
    \\
    \\Texture2D fontAtlas : register(t0);
    \\SamplerState fontSampler : register(s0);
    \\
    \\struct PS_INPUT
    \\{
    \\    float4 pos : SV_POSITION;
    \\    float2 uv : TEXCOORD0;
    \\    float4 fg_color : COLOR0;
    \\    float4 bg_color : COLOR1;
    \\};
    \\
    \\float4 main(PS_INPUT input) : SV_TARGET
    \\{
    \\    float4 texel = fontAtlas.Sample(fontSampler, input.uv);
    \\
    \\    // For grayscale atlas, use red channel as alpha
    \\    float alpha = texel.r;
    \\
    \\    // Blend foreground over background
    \\    float4 result = lerp(input.bg_color, input.fg_color, alpha);
    \\    return result;
    \\}
;

/// Vertex shader for background rendering
const bg_vertex_shader: [:0]const u8 =
    \\// Background Vertex Shader
    \\
    \\cbuffer ConstantBuffer : register(b0)
    \\{
    \\    float4x4 projection;
    \\    float2 cell_size;
    \\    float2 padding;
    \\};
    \\
    \\struct VS_INPUT
    \\{
    \\    float2 pos : POSITION;
    \\    float4 color : COLOR0;
    \\};
    \\
    \\struct VS_OUTPUT
    \\{
    \\    float4 pos : SV_POSITION;
    \\    float4 color : COLOR0;
    \\};
    \\
    \\VS_OUTPUT main(VS_INPUT input)
    \\{
    \\    VS_OUTPUT output;
    \\    output.pos = mul(projection, float4(input.pos, 0.0, 1.0));
    \\    output.color = input.color;
    \\    return output;
    \\}
;

/// Pixel shader for background rendering
const bg_pixel_shader: [:0]const u8 =
    \\// Background Pixel Shader
    \\
    \\struct PS_INPUT
    \\{
    \\    float4 pos : SV_POSITION;
    \\    float4 color : COLOR0;
    \\};
    \\
    \\float4 main(PS_INPUT input) : SV_TARGET
    \\{
    \\    return input.color;
    \\}
;

/// Vertex shader for image rendering
const image_vertex_shader: [:0]const u8 =
    \\// Image Vertex Shader
    \\
    \\cbuffer ConstantBuffer : register(b0)
    \\{
    \\    float4x4 projection;
    \\};
    \\
    \\struct VS_INPUT
    \\{
    \\    float2 pos : POSITION;
    \\    float2 uv : TEXCOORD0;
    \\};
    \\
    \\struct VS_OUTPUT
    \\{
    \\    float4 pos : SV_POSITION;
    \\    float2 uv : TEXCOORD0;
    \\};
    \\
    \\VS_OUTPUT main(VS_INPUT input)
    \\{
    \\    VS_OUTPUT output;
    \\    output.pos = mul(projection, float4(input.pos, 0.0, 1.0));
    \\    output.uv = input.uv;
    \\    return output;
    \\}
;

/// Pixel shader for image rendering
const image_pixel_shader: [:0]const u8 =
    \\// Image Pixel Shader
    \\
    \\Texture2D imageTexture : register(t0);
    \\SamplerState imageSampler : register(s0);
    \\
    \\struct PS_INPUT
    \\{
    \\    float4 pos : SV_POSITION;
    \\    float2 uv : TEXCOORD0;
    \\};
    \\
    \\float4 main(PS_INPUT input) : SV_TARGET
    \\{
    \\    return imageTexture.Sample(imageSampler, input.uv);
    \\}
;

test {
    _ = Shaders;
    _ = CompiledShader;
    _ = Uniforms;
    _ = CellText;
    _ = CellBg;
    _ = Image;
    _ = BgImage;
}
