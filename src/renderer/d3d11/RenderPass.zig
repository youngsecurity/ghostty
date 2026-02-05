//! Direct3D 11 Render Pass
//!
//! Encapsulates a render pass - a sequence of draw commands targeting
//! a specific render target with specific clear/load operations.
//!
const RenderPass = @This();

const std = @import("std");
const Frame = @import("Frame.zig");
const Pipeline = @import("Pipeline.zig");

/// The frame this render pass belongs to
frame: *Frame,

/// Clear color (if clearing)
clear_color: ?[4]f32,

pub const Options = struct {
    clear_color: ?[4]f32 = null,
};

pub fn begin(frame: *Frame, opts: Options) !RenderPass {
    // If we have a clear color, clear the render target
    if (opts.clear_color) |color| {
        frame.target.clear(undefined, color);
    }

    return RenderPass{
        .frame = frame,
        .clear_color = opts.clear_color,
    };
}

/// Set the pipeline (shaders, blend state, etc.) for subsequent draw calls
pub fn setPipeline(self: *RenderPass, pipeline: *const Pipeline) void {
    _ = self;
    _ = pipeline;
    // TODO: Bind shaders, input layout, blend state, etc.
}

/// Draw primitives
pub fn draw(self: *RenderPass, vertex_count: u32, instance_count: u32) void {
    _ = self;
    _ = vertex_count;
    _ = instance_count;
    // TODO: Issue draw call via ID3D11DeviceContext
}

/// Draw indexed primitives
pub fn drawIndexed(self: *RenderPass, index_count: u32, instance_count: u32, first_index: u32) void {
    _ = self;
    _ = index_count;
    _ = instance_count;
    _ = first_index;
    // TODO: Issue indexed draw call via ID3D11DeviceContext
}

/// End the render pass
pub fn end(self: *RenderPass) void {
    _ = self;
    // Render pass cleanup if needed
}

test {
    _ = RenderPass;
}
