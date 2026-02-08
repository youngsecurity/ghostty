//! Direct3D 11 Render Pass
//!
//! Encapsulates a render pass - a sequence of draw commands targeting
//! a specific render target with specific clear/load operations.
//!
const RenderPass = @This();

const std = @import("std");
const rendererpkg = @import("../../renderer.zig");
const Direct3D11 = @import("../Direct3D11.zig");
const Pipeline = @import("Pipeline.zig");
const Sampler = @import("Sampler.zig");
const Texture = @import("Texture.zig");
const Target = @import("Target.zig");
const bufferpkg = @import("buffer.zig");

const Renderer = rendererpkg.GenericRenderer(Direct3D11);

const log = std.log.scoped(.d3d11_renderpass);

/// The renderer
renderer: *Renderer,

/// The target we're rendering to
target: *Target,

pub const Options = struct {
    /// Attachments for this render pass.
    attachments: []const Attachment,

    /// The renderer
    renderer: *Renderer,

    /// The target
    target: *Target,

    /// Describes a color attachment.
    pub const Attachment = struct {
        target: union(enum) {
            texture: Texture,
            target: Target,
        },
        clear_color: ?[4]f64 = null,
    };
};

/// Describes a step in a render pass.
pub const Step = struct {
    pipeline: Pipeline,
    uniforms: ?*anyopaque = null,
    buffers: []const ?*anyopaque = &.{},
    textures: []const ?Texture = &.{},
    samplers: []const ?Sampler = &.{},
    draw: Draw,

    /// Describes the draw call for this step.
    pub const Draw = struct {
        type: PrimitiveType,
        vertex_count: usize,
        instance_count: usize = 1,
    };

    pub const PrimitiveType = enum {
        triangle,
        triangle_strip,
        line,
        line_strip,
        point,

        pub fn toD3D11(self: PrimitiveType) u32 {
            return switch (self) {
                .triangle => D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST,
                .triangle_strip => D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP,
                .line => D3D11_PRIMITIVE_TOPOLOGY_LINELIST,
                .line_strip => D3D11_PRIMITIVE_TOPOLOGY_LINESTRIP,
                .point => D3D11_PRIMITIVE_TOPOLOGY_POINTLIST,
            };
        }
    };
};

/// Begin a render pass.
pub fn begin(opts: Options) RenderPass {
    // Process attachments - clear if needed
    for (opts.attachments) |at| {
        if (at.clear_color) |c| {
            const color = [4]f32{
                @floatCast(c[0]),
                @floatCast(c[1]),
                @floatCast(c[2]),
                @floatCast(c[3]),
            };
            switch (at.target) {
                .target => |t| {
                    if (opts.renderer.api.context) |ctx| {
                        const context: *Target.ID3D11DeviceContext = @ptrCast(@alignCast(ctx));
                        t.clear(context, color);
                    }
                },
                .texture => {
                    // Textures don't have clear operations in this model
                },
            }
        }
    }

    return .{
        .renderer = opts.renderer,
        .target = opts.target,
    };
}

/// Add a step to this render pass.
pub fn step(self: *const RenderPass, s: Step) void {
    if (s.draw.instance_count == 0) return;

    const context_ptr = self.renderer.api.context orelse return;
    const context: *Target.ID3D11DeviceContext = @ptrCast(@alignCast(context_ptr));

    // Bind render target
    self.target.bind(context);

    // Set viewport
    const viewport = D3D11_VIEWPORT{
        .TopLeftX = 0,
        .TopLeftY = 0,
        .Width = @floatFromInt(self.target.width),
        .Height = @floatFromInt(self.target.height),
        .MinDepth = 0.0,
        .MaxDepth = 1.0,
    };
    context.vtable.RSSetViewports(context, 1, &[_]D3D11_VIEWPORT{viewport});

    // Bind pipeline (shaders, states)
    s.pipeline.bind(context);

    // Set primitive topology
    context.vtable.IASetPrimitiveTopology(context, s.draw.type.toD3D11());

    // Bind uniforms (constant buffer)
    if (s.uniforms) |uniforms| {
        const buffers = [_]?*anyopaque{uniforms};
        context.vtable.VSSetConstantBuffers(context, 0, 1, @ptrCast(&buffers));
        context.vtable.PSSetConstantBuffers(context, 0, 1, @ptrCast(&buffers));
    }

    // Bind textures
    for (s.textures, 0..) |maybe_tex, i| {
        if (maybe_tex) |tex| {
            tex.bindToPixelShader(context, @intCast(i));
        }
    }

    // Bind samplers
    for (s.samplers, 0..) |maybe_sampler, i| {
        if (maybe_sampler) |sampler| {
            sampler.bindToPixelShader(context, @intCast(i));
        }
    }

    // Issue draw call
    if (s.draw.instance_count > 1) {
        context.vtable.DrawInstanced(
            context,
            @intCast(s.draw.vertex_count),
            @intCast(s.draw.instance_count),
            0,
            0,
        );
    } else {
        context.vtable.Draw(context, @intCast(s.draw.vertex_count), 0);
    }
}

/// Complete the render pass
pub fn complete(self: *const RenderPass) void {
    _ = self;
    // D3D11 doesn't have explicit render pass end - state is immediate
}

// =============================================================================
// D3D11 Constants
// =============================================================================

const D3D11_PRIMITIVE_TOPOLOGY_POINTLIST = 1;
const D3D11_PRIMITIVE_TOPOLOGY_LINELIST = 2;
const D3D11_PRIMITIVE_TOPOLOGY_LINESTRIP = 3;
const D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST = 4;
const D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP = 5;

// =============================================================================
// D3D11 Type Definitions
// =============================================================================

const UINT = u32;
const FLOAT = f32;

const D3D11_VIEWPORT = extern struct {
    TopLeftX: FLOAT,
    TopLeftY: FLOAT,
    Width: FLOAT,
    Height: FLOAT,
    MinDepth: FLOAT,
    MaxDepth: FLOAT,
};

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
    OMSetRenderTargets: *const anyopaque, // 33
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
    // ... more methods
};

pub const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVtbl,
};

test {
    _ = RenderPass;
}
