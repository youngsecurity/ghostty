//! Direct3D 11 Frame
//!
//! Represents a single frame being rendered. This manages the lifecycle
//! of a frame from begin to end/present.
//!
const Frame = @This();

const std = @import("std");
const rendererpkg = @import("../../renderer.zig");
const Direct3D11 = @import("../Direct3D11.zig");
const Target = @import("Target.zig");
const RenderPass = @import("RenderPass.zig");

const Renderer = rendererpkg.GenericRenderer(Direct3D11);

/// The renderer that owns this frame
renderer: *Renderer,

/// The target we're rendering to
target: *Target,

pub const Options = struct {};

pub fn begin(opts: Options, renderer: *Renderer, target: *Target) !Frame {
    _ = opts;

    return Frame{
        .renderer = renderer,
        .target = target,
    };
}

/// Begin a render pass within this frame
pub fn beginRenderPass(self: *Frame, opts: RenderPass.Options) !RenderPass {
    return RenderPass.begin(self, opts);
}

/// End and present the frame
pub fn end(self: *Frame) !void {
    // Frame completion - the actual present happens in the Surface
    _ = self;
}

/// Cancel the frame without presenting
pub fn cancel(self: *Frame) void {
    _ = self;
}

test {
    _ = Frame;
}
