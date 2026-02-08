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
    s.pipeline.bind(@ptrCast(context));

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
            tex.bindToPixelShader(@ptrCast(context), @intCast(i));
        }
    }

    // Bind samplers
    for (s.samplers, 0..) |maybe_sampler, i| {
        if (maybe_sampler) |sampler| {
            sampler.bindToPixelShader(@ptrCast(context), @intCast(i));
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
// D3D11 Type Definitions - use Target's public definitions (DRY)
// =============================================================================

const D3D11_VIEWPORT = Target.D3D11_VIEWPORT;

test {
    _ = RenderPass;
}
