# YStty - Windows Native Terminal

**YStty** (YoungSecurity TTY) is the Windows-native frontend for Ghostty, providing a high-performance terminal emulator using Win32 and Direct3D 11.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    YStty Application                         │
├─────────────────────────────────────────────────────────────┤
│  Windows App Runtime (src/apprt/windows/)                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   App.zig   │  │ Surface.zig │  │  Win32 Bindings     │  │
│  │  (Win32     │  │  (Window +  │  │  (user32, kernel32) │  │
│  │  msg loop)  │  │  D3D11 ctx) │  │                     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  Direct3D 11 Renderer (src/renderer/d3d11/)                 │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────────┐   │
│  │ Target   │ │ Frame    │ │ Pipeline │ │ Shaders (HLSL)│   │
│  │ (RTV)    │ │ (render) │ │ (state)  │ │               │   │
│  └──────────┘ └──────────┘ └──────────┘ └───────────────┘   │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                     │
│  │ Buffer   │ │ Texture  │ │ Sampler  │                     │
│  │ (GPU mem)│ │ (atlas)  │ │ (filter) │                     │
│  └──────────┘ └──────────┘ └──────────┘                     │
├─────────────────────────────────────────────────────────────┤
│  Ghostty Core (shared with Linux/macOS)                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Terminal Emulator │ Generic Renderer │ Font System  │   │
│  │  (VT100/ANSI)      │ (cell rendering) │ (FreeType)   │   │
│  └──────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│  Windows PTY (ConPTY)                                       │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  CreatePseudoConsole │ ResizePseudoConsole │ Pipes   │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Components

### Windows App Runtime (`src/apprt/windows/`)

- **App.zig**: Main application class managing the Win32 message loop
- **Surface.zig**: Terminal window with D3D11 swap chain and rendering

### Direct3D 11 Renderer (`src/renderer/d3d11/`)

- **Direct3D11.zig**: Main renderer implementing the generic renderer interface
- **Target.zig**: Render target (wraps ID3D11RenderTargetView)
- **Frame.zig**: Frame lifecycle management
- **RenderPass.zig**: Render pass abstraction
- **Pipeline.zig**: Graphics pipeline (shaders, blend state, etc.)
- **buffer.zig**: GPU buffers (vertex, constant, etc.)
- **Texture.zig**: 2D textures for font atlas and images
- **Sampler.zig**: Texture sampling configuration
- **shaders.zig**: HLSL shaders for terminal rendering

## Building

### Prerequisites

- Zig 0.13.0 or later
- Windows 10 SDK (for D3D11 headers)
- Windows 10 version 1809 or later (for ConPTY support)

### Build Commands

```bash
# Build for Windows (from Windows or cross-compile)
zig build -Dtarget=x86_64-windows -Dapp-runtime=windows -Drenderer=d3d11

# Build release
zig build -Dtarget=x86_64-windows -Dapp-runtime=windows -Drenderer=d3d11 -Doptimize=ReleaseFast
```

### Build Options

| Option | Values | Description |
|--------|--------|-------------|
| `-Dapp-runtime` | `windows` | Use Win32 application runtime |
| `-Drenderer` | `d3d11` | Use Direct3D 11 renderer |
| `-Dtarget` | `x86_64-windows` | Windows x64 target |

## Implementation Status

### Completed
- [x] Project structure and module organization
- [x] Win32 window class registration and creation
- [x] D3D11 device, context, and swap chain creation
- [x] Render target view management
- [x] Window resize handling with swap chain resize
- [x] Basic frame rendering (clear to background color)
- [x] HLSL shader sources for terminal rendering
- [x] Build system integration (apprt, renderer selection)

### In Progress
- [ ] Connect to Ghostty core terminal emulator
- [ ] Font atlas texture creation and upload
- [ ] Cell rendering with font atlas sampling
- [ ] Keyboard input handling (VK to Ghostty key mapping)
- [ ] Mouse input handling
- [ ] Clipboard integration
- [ ] DPI awareness and scaling

### Planned
- [ ] Tab support
- [ ] Split panes
- [ ] Configuration UI
- [ ] System tray integration
- [ ] Native Windows notifications
- [ ] Shader compilation (D3DCompile)

## Key Differences from GTK/macOS

| Aspect | GTK (Linux) | macOS | YStty (Windows) |
|--------|-------------|-------|-----------------|
| Windowing | GObject/GTK4 | Cocoa/AppKit | Win32 |
| Rendering | OpenGL (GLArea) | Metal | Direct3D 11 |
| Shaders | GLSL | MSL | HLSL |
| PTY | POSIX PTY | POSIX PTY | ConPTY |
| IPC | D-Bus | XPC | Named Pipes |

## Contributing

YStty follows the same code style and architecture as the main Ghostty project.
When adding new features:

1. Implement the generic interface defined in the core
2. Use Zig's comptime features for platform-specific code
3. Keep D3D11 COM interactions isolated in the renderer module
4. Test on Windows 10 and Windows 11
