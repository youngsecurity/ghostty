//! Direct3D 11 Shaders
//!
//! HLSL shader management for the terminal renderer.
//! Includes vertex and pixel shaders for cell rendering, background,
//! images, and custom shadertoy-style effects.
//!
const shaders = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

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

    pub fn deinit(self: *Shaders) void {
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

pub const CompiledShader = struct {
    bytecode: []const u8,
    alloc: Allocator,

    pub fn deinit(self: *CompiledShader) void {
        self.alloc.free(self.bytecode);
        self.* = undefined;
    }
};

pub const ShaderType = enum {
    vertex,
    pixel,
    compute,
};

fn compileShader(alloc: Allocator, source: [:0]const u8, shader_type: ShaderType) !CompiledShader {
    _ = shader_type;

    // TODO: Use D3DCompile to compile HLSL at runtime
    // For now, we'll store the source and compile later
    // In a real implementation, you'd either:
    // 1. Compile at build time using fxc.exe or dxc.exe
    // 2. Compile at runtime using D3DCompile

    const bytecode = try alloc.dupe(u8, source);

    return CompiledShader{
        .bytecode = bytecode,
        .alloc = alloc,
    };
}

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
}
