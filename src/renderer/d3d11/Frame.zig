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
const Texture = @import("Texture.zig");

const Renderer = rendererpkg.GenericRenderer(Direct3D11);
const Health = rendererpkg.Health;

const log = std.log.scoped(.d3d11_frame);

/// The renderer that owns this frame
renderer: *Renderer,

/// The target we're rendering to
target: *Target,

/// Whether this frame should be presented synchronously
sync: bool = false,

pub const Options = struct {};

pub fn begin(opts: Options, renderer: *Renderer, target: *Target) !Frame {
    _ = opts;

    log.debug("Beginning frame {}x{}", .{ target.width, target.height });

    return Frame{
        .renderer = renderer,
        .target = target,
    };
}

/// Add a render pass to this frame with the provided attachments.
/// Returns a RenderPass which allows render steps to be added.
pub inline fn renderPass(
    self: *const Frame,
    attachments: []const RenderPass.Options.Attachment,
) RenderPass {
    return RenderPass.begin(.{
        .attachments = attachments,
        .renderer = self.renderer,
        .target = self.target,
    });
}

/// Complete this frame and present the target.
///
/// If `sync` is true, this will block until the frame is presented.
pub inline fn complete(self: *Frame, sync: bool) void {
    self.sync = sync;

    // Present the target
    self.renderer.api.present(self.target.*) catch |err| {
        log.err("Failed to present render target: err={}", .{err});
        self.renderer.frameCompleted(.unhealthy);
        return;
    };

    self.renderer.frameCompleted(.healthy);
}

test {
    _ = Frame;
}
