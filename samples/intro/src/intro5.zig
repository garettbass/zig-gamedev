// This intro application shows how to use zmath lib and std.MultiArrayList to efficiently generate dynamic wave
// consisting of more than 1M points on the CPU.

const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const win32 = @import("win32");
const w = win32.base;
const d2d1 = win32.d2d1;
const d3d12 = win32.d3d12;
const dwrite = win32.dwrite;
const common = @import("common");
const gfx = common.graphics;
const lib = common.library;
const zm = common.zmath;
const c = common.c;

const hrPanic = lib.hrPanic;
const hrPanicOnFail = lib.hrPanicOnFail;
const L = std.unicode.utf8ToUtf16LeStringLiteral;

// We need to export below symbols for DirectX 12 Agility SDK.
pub export var D3D12SDKVersion: u32 = 4;
pub export var D3D12SDKPath: [*:0]const u8 = ".\\d3d12\\";

const window_name = "zig-gamedev: intro 5";
const window_width = 1920;
const window_height = 1080;

const grid_size = 1024;
const max_num_vertices = grid_size * grid_size;

// By convention, we use 'Pso_' prefix for structures that are also defined in HLSL code
// (see 'DrawConst' and 'FrameConst' in intro5.hlsl).
const Pso_DrawConst = struct {
    object_to_world: [16]f32,
};

const Pso_FrameConst = struct {
    world_to_clip: [16]f32,
};

const Pso_Vertex = struct {
    position: [3]f32,
};

const Vertex = struct {
    x: f32,
    y: f32,
    z: f32,
};

const DemoState = struct {
    gctx: gfx.GraphicsContext,
    guictx: gfx.GuiContext,
    frame_stats: lib.FrameStats,

    brush: *d2d1.ISolidColorBrush,
    normal_tfmt: *dwrite.ITextFormat,

    main_pso: gfx.PipelineHandle,

    vertex_buffer: gfx.ResourceHandle,
    vertex_data: std.MultiArrayList(Vertex),

    depth_texture: gfx.ResourceHandle,
    depth_texture_dsv: d3d12.CPU_DESCRIPTOR_HANDLE,

    simd_width: i32,

    camera: struct {
        position: [3]f32,
        forward: [3]f32,
        pitch: f32,
        yaw: f32,
    },
    mouse: struct {
        cursor_prev_x: i32,
        cursor_prev_y: i32,
    },
};

fn init(gpa_allocator: std.mem.Allocator) DemoState {
    // Create application window and initialize dear imgui library.
    const window = lib.initWindow(gpa_allocator, window_name, window_width, window_height) catch unreachable;

    // Create temporary memory allocator for use during initialization. We pass this allocator to all
    // subsystems that need memory and then free everyting with a single deallocation.
    var arena_allocator_state = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena_allocator_state.deinit();
    const arena_allocator = arena_allocator_state.allocator();

    // Create DirectX 12 context.
    var gctx = gfx.GraphicsContext.init(window);

    // Create Direct2D brush which will be needed to display text.
    const brush = blk: {
        var brush: ?*d2d1.ISolidColorBrush = null;
        hrPanicOnFail(gctx.d2d.context.CreateSolidColorBrush(
            &.{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 0.5 },
            null,
            &brush,
        ));
        break :blk brush.?;
    };

    // Create Direct2D text format which will be needed to display text.
    const normal_tfmt = blk: {
        var info_txtfmt: ?*dwrite.ITextFormat = null;
        hrPanicOnFail(gctx.dwrite_factory.CreateTextFormat(
            L("Verdana"),
            null,
            .BOLD,
            .NORMAL,
            .NORMAL,
            32.0,
            L("en-us"),
            &info_txtfmt,
        ));
        break :blk info_txtfmt.?;
    };
    hrPanicOnFail(normal_tfmt.SetTextAlignment(.LEADING));
    hrPanicOnFail(normal_tfmt.SetParagraphAlignment(.NEAR));

    const main_pso = blk: {
        const input_layout_desc = [_]d3d12.INPUT_ELEMENT_DESC{
            d3d12.INPUT_ELEMENT_DESC.init("POSITION", 0, .R32G32B32_FLOAT, 0, 0, .PER_VERTEX_DATA, 0),
        };

        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = &input_layout_desc,
            .NumElements = input_layout_desc.len,
        };
        pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        pso_desc.NumRenderTargets = 1;
        pso_desc.DSVFormat = .D32_FLOAT;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .POINT;

        break :blk gctx.createGraphicsShaderPipeline(
            arena_allocator,
            &pso_desc,
            "content/shaders/intro5.vs.cso",
            "content/shaders/intro5.ps.cso",
        );
    };

    // Create vertex buffer and return a *handle* to the underlying Direct3D12 resource.
    const vertex_buffer = gctx.createCommittedResource(
        .DEFAULT,
        d3d12.HEAP_FLAG_NONE,
        &d3d12.RESOURCE_DESC.initBuffer(max_num_vertices * @sizeOf(Vertex)),
        d3d12.RESOURCE_STATE_COPY_DEST,
        null,
    ) catch |err| hrPanic(err);

    const vertex_data = blk: {
        var vertex_data = std.MultiArrayList(Vertex){};
        vertex_data.ensureTotalCapacity(gpa_allocator, max_num_vertices) catch unreachable;

        var i: u32 = 0;
        while (i < max_num_vertices) : (i += 1) {
            vertex_data.appendAssumeCapacity(.{ .x = 0, .y = 0, .z = 0 });
        }
        break :blk vertex_data;
    };

    // Create depth texture resource.
    const depth_texture = gctx.createCommittedResource(
        .DEFAULT,
        d3d12.HEAP_FLAG_NONE,
        &blk: {
            var desc = d3d12.RESOURCE_DESC.initTex2d(.D32_FLOAT, gctx.viewport_width, gctx.viewport_height, 1);
            desc.Flags = d3d12.RESOURCE_FLAG_ALLOW_DEPTH_STENCIL | d3d12.RESOURCE_FLAG_DENY_SHADER_RESOURCE;
            break :blk desc;
        },
        d3d12.RESOURCE_STATE_DEPTH_WRITE,
        &d3d12.CLEAR_VALUE.initDepthStencil(.D32_FLOAT, 1.0, 0),
    ) catch |err| hrPanic(err);

    // Create depth texture 'view' - a descriptor which can be send to Direct3D 12 API.
    const depth_texture_dsv = gctx.allocateCpuDescriptors(.DSV, 1);
    gctx.device.CreateDepthStencilView(
        gctx.getResource(depth_texture), // Get the D3D12 resource from a handle.
        null,
        depth_texture_dsv,
    );

    // Open D3D12 command list, setup descriptor heap, etc. After this call we can upload resources to the GPU,
    // draw 3D graphics etc.
    gctx.beginFrame();

    // Create and upload graphics resources for dear imgui renderer.
    var guictx = gfx.GuiContext.init(arena_allocator, &gctx, 1);

    // This will send command list to the GPU, call 'Present' and do some other bookkeeping.
    gctx.endFrame();

    // Wait for the GPU to finish all commands.
    gctx.finishGpuCommands();

    return .{
        .gctx = gctx,
        .guictx = guictx,
        .frame_stats = lib.FrameStats.init(),
        .brush = brush,
        .normal_tfmt = normal_tfmt,
        .main_pso = main_pso,
        .vertex_buffer = vertex_buffer,
        .vertex_data = vertex_data,
        .depth_texture = depth_texture,
        .depth_texture_dsv = depth_texture_dsv,
        .camera = .{
            .position = [3]f32{ 0.0, 5.0, -5.0 },
            .forward = [3]f32{ 0.0, 0.0, 1.0 },
            .pitch = 0.175 * math.pi,
            .yaw = 0.0,
        },
        .mouse = .{
            .cursor_prev_x = 0,
            .cursor_prev_y = 0,
        },
        .simd_width = 4,
    };
}

fn deinit(demo: *DemoState, gpa_allocator: std.mem.Allocator) void {
    demo.gctx.finishGpuCommands();
    demo.vertex_data.deinit(gpa_allocator);
    _ = demo.gctx.releaseResource(demo.depth_texture);
    _ = demo.gctx.releaseResource(demo.vertex_buffer);
    _ = demo.gctx.releasePipeline(demo.main_pso);
    _ = demo.brush.Release();
    _ = demo.normal_tfmt.Release();
    demo.guictx.deinit(&demo.gctx);
    demo.gctx.deinit();
    lib.deinitWindow(gpa_allocator);
    demo.* = undefined;
}

fn update(demo: *DemoState) void {
    // Update frame counter and fps stats.
    demo.frame_stats.update();
    const dt = demo.frame_stats.delta_time;

    // Update dear imgui lib. After this call we can define our widgets.
    lib.newImGuiFrame(dt);

    c.igSetNextWindowPos(
        c.ImVec2{ .x = @intToFloat(f32, demo.gctx.viewport_width) - 600.0 - 20, .y = 20.0 },
        c.ImGuiCond_FirstUseEver,
        c.ImVec2{ .x = 0.0, .y = 0.0 },
    );
    c.igSetNextWindowSize(.{ .x = 600.0, .y = -1 }, c.ImGuiCond_Always);

    _ = c.igBegin(
        "Demo Settings",
        null,
        c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoResize | c.ImGuiWindowFlags_NoSavedSettings,
    );
    c.igBulletText("", "");
    c.igSameLine(0, -1);
    c.igTextColored(.{ .x = 0, .y = 0.8, .z = 0, .w = 1 }, "Right Mouse Button + Drag", "");
    c.igSameLine(0, -1);
    c.igText(" :  rotate camera", "");

    c.igBulletText("", "");
    c.igSameLine(0, -1);
    c.igTextColored(.{ .x = 0, .y = 0.8, .z = 0, .w = 1 }, "W, A, S, D", "");
    c.igSameLine(0, -1);
    c.igText(" :  move camera", "");

    _ = c.igRadioButton_IntPtr("Vector width 4", &demo.simd_width, 4);
    _ = c.igRadioButton_IntPtr("Vector width 8", &demo.simd_width, 8);
    _ = c.igRadioButton_IntPtr("Vector width 16", &demo.simd_width, 16);

    c.igEnd();

    // Handle camera rotation with mouse.
    {
        var pos: w.POINT = undefined;
        _ = w.GetCursorPos(&pos);
        const delta_x = @intToFloat(f32, pos.x) - @intToFloat(f32, demo.mouse.cursor_prev_x);
        const delta_y = @intToFloat(f32, pos.y) - @intToFloat(f32, demo.mouse.cursor_prev_y);
        demo.mouse.cursor_prev_x = pos.x;
        demo.mouse.cursor_prev_y = pos.y;

        if (w.GetAsyncKeyState(w.VK_RBUTTON) < 0) {
            demo.camera.pitch += 0.0025 * delta_y;
            demo.camera.yaw += 0.0025 * delta_x;
            demo.camera.pitch = math.min(demo.camera.pitch, 0.48 * math.pi);
            demo.camera.pitch = math.max(demo.camera.pitch, -0.48 * math.pi);
            demo.camera.yaw = zm.modAngle(demo.camera.yaw);
        }
    }

    // Handle camera movement with 'WASD' keys.
    {
        const speed = zm.f32x4s(10.0);
        const delta_time = zm.f32x4s(demo.frame_stats.delta_time);
        const transform = zm.mul(zm.rotationX(demo.camera.pitch), zm.rotationY(demo.camera.yaw));
        var forward = zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 0.0), transform));

        zm.store(demo.camera.forward[0..], forward, 3);

        const right = speed * delta_time * zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 0.0), forward));
        forward = speed * delta_time * forward;

        // Load camera position from memory to SIMD register ('3' means that we want to load three components).
        var cpos = zm.load(demo.camera.position[0..], zm.Vec, 3);

        if (w.GetAsyncKeyState('W') < 0) {
            cpos += forward;
        } else if (w.GetAsyncKeyState('S') < 0) {
            cpos -= forward;
        }
        if (w.GetAsyncKeyState('D') < 0) {
            cpos += right;
        } else if (w.GetAsyncKeyState('A') < 0) {
            cpos -= right;
        }

        // Copy updated position from SIMD register to memory.
        zm.store(demo.camera.position[0..], cpos, 3);
    }
}

fn computeWaves(comptime T: type, vertex_data: std.MultiArrayList(Vertex), time: f32) void {
    const static = struct {
        const offsets = [16]f32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    };
    const voffset = zm.load(static.offsets[0..], T, 0);
    const vtime = zm.splat(T, time);

    const xslice = vertex_data.items(.x);
    const yslice = vertex_data.items(.y);
    const zslice = vertex_data.items(.z);

    var z: f32 = -0.5 * 0.1 * @intToFloat(f32, grid_size);
    var z_index: u32 = 0;
    while (z_index < grid_size) : ({
        z_index += 1;
        z += 0.1;
    }) {
        var x: f32 = -0.5 * 0.1 * @intToFloat(f32, grid_size);
        var x_index: u32 = 0;
        while (x_index < grid_size) : ({
            x_index += zm.veclen(T);
            x += 0.1 * @intToFloat(f32, zm.veclen(T));
        }) {
            const index = x_index + z_index * grid_size;

            var vx = zm.splat(T, x) + voffset * zm.splat(T, 0.1);
            var vy = zm.splat(T, 0.0);
            var vz = zm.splat(T, z);

            const d = zm.sqrt(vx * vx + vy * vy + vz * vz);

            vy = zm.sin(d - vtime);

            zm.store(xslice[index..], vx, 0);
            zm.store(yslice[index..], vy, 0);
            zm.store(zslice[index..], vz, 0);
        }
    }
}

fn draw(demo: *DemoState) void {
    var gctx = &demo.gctx;

    const cam_world_to_view = zm.lookToLh(
        zm.load(demo.camera.position[0..], zm.Vec, 3),
        zm.load(demo.camera.forward[0..], zm.Vec, 3),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );
    const cam_view_to_clip = zm.perspectiveFovLh(
        0.25 * math.pi,
        @intToFloat(f32, gctx.viewport_width) / @intToFloat(f32, gctx.viewport_height),
        0.01,
        200.0,
    );
    const cam_world_to_clip = zm.mul(cam_world_to_view, cam_view_to_clip);

    // Begin DirectX 12 rendering.
    gctx.beginFrame();

    // Get current back buffer resource and transition it to 'render target' state.
    const back_buffer = gctx.getBackBuffer();
    gctx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATE_RENDER_TARGET);
    gctx.flushResourceBarriers();

    gctx.cmdlist.OMSetRenderTargets(
        1,
        &[_]d3d12.CPU_DESCRIPTOR_HANDLE{back_buffer.descriptor_handle},
        w.TRUE,
        &demo.depth_texture_dsv,
    );
    gctx.cmdlist.ClearRenderTargetView(
        back_buffer.descriptor_handle,
        &[4]f32{ 0.2, 0.2, 0.2, 1.0 },
        0,
        null,
    );
    gctx.cmdlist.ClearDepthStencilView(demo.depth_texture_dsv, d3d12.CLEAR_FLAG_DEPTH, 1.0, 0, 0, null);

    // Update dynamic mesh.
    {
        switch (demo.simd_width) {
            4 => computeWaves(zm.F32x4, demo.vertex_data, @floatCast(f32, demo.frame_stats.time)),
            8 => computeWaves(zm.F32x8, demo.vertex_data, @floatCast(f32, demo.frame_stats.time)),
            16 => computeWaves(zm.F32x16, demo.vertex_data, @floatCast(f32, demo.frame_stats.time)),
            else => unreachable,
        }

        const xslice = demo.vertex_data.items(.x);
        const yslice = demo.vertex_data.items(.y);
        const zslice = demo.vertex_data.items(.z);

        const verts = gctx.allocateUploadBufferRegion(Pso_Vertex, @intCast(u32, demo.vertex_data.len));
        var i: usize = 0;
        while (i < demo.vertex_data.len) : (i += 1) {
            verts.cpu_slice[i].position = [3]f32{ xslice[i], yslice[i], zslice[i] };
        }

        gctx.addTransitionBarrier(demo.vertex_buffer, d3d12.RESOURCE_STATE_COPY_DEST);
        gctx.flushResourceBarriers();
        gctx.cmdlist.CopyBufferRegion(
            gctx.getResource(demo.vertex_buffer),
            0,
            verts.buffer,
            verts.buffer_offset,
            verts.cpu_slice.len * @sizeOf(@TypeOf(verts.cpu_slice[0])),
        );
        gctx.addTransitionBarrier(demo.vertex_buffer, d3d12.RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER);
        gctx.flushResourceBarriers();
    }

    gctx.setCurrentPipeline(demo.main_pso);

    // Set input assembler (IA) state.
    gctx.cmdlist.IASetPrimitiveTopology(.POINTLIST);
    gctx.cmdlist.IASetVertexBuffers(0, 1, &[_]d3d12.VERTEX_BUFFER_VIEW{.{
        .BufferLocation = gctx.getResource(demo.vertex_buffer).GetGPUVirtualAddress(),
        .SizeInBytes = max_num_vertices * @sizeOf(Pso_Vertex),
        .StrideInBytes = @sizeOf(Pso_Vertex),
    }});

    // Upload per-frame constant data (camera xform).
    {
        // Allocate memory for one instance of Pso_FrameConst structure.
        const mem = gctx.allocateUploadMemory(Pso_FrameConst, 1);

        // Copy 'cam_world_to_clip' matrix to upload memory. We need to transpose it because
        // HLSL uses column-major matrices by default (zmath uses row-major matrices).
        zm.storeF32x4x4(mem.cpu_slice[0].world_to_clip[0..], zm.transpose(cam_world_to_clip));

        // Set GPU handle of our allocated memory region so that it is visible to the shader.
        gctx.cmdlist.SetGraphicsRootConstantBufferView(
            0, // Slot index in Root Signature (CBV(b0), see intro5.hlsl).
            mem.gpu_base,
        );
    }

    gctx.cmdlist.DrawInstanced(max_num_vertices, 1, 0, 0);

    // Draw dear imgui widgets.
    demo.guictx.draw(gctx);

    // Begin Direct2D rendering to the back buffer.
    gctx.beginDraw2d();
    {
        // Display average fps and frame time.

        const stats = &demo.frame_stats;
        var buffer = [_]u8{0} ** 64;
        const text = std.fmt.bufPrint(
            buffer[0..],
            "FPS: {d:.1}\nCPU time: {d:.3} ms",
            .{ stats.fps, stats.average_cpu_time },
        ) catch unreachable;

        demo.brush.SetColor(&.{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 });
        lib.drawText(
            gctx.d2d.context,
            text,
            demo.normal_tfmt,
            &d2d1.RECT_F{
                .left = 10.0,
                .top = 10.0,
                .right = @intToFloat(f32, gctx.viewport_width),
                .bottom = @intToFloat(f32, gctx.viewport_height),
            },
            @ptrCast(*d2d1.IBrush, demo.brush),
        );
    }
    // End Direct2D rendering and transition back buffer to 'present' state.
    gctx.endDraw2d();

    // Call 'Present' and prepare for the next frame.
    gctx.endFrame();
}

pub fn main() !void {
    // Initialize some low-level Windows stuff (DPI awarness, COM), check Windows version and also check
    // if DirectX 12 Agility SDK is supported.
    lib.init();
    defer lib.deinit();

    // Create main memory allocator for our application.
    var gpa_allocator_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa_allocator_state.deinit();
        std.debug.assert(leaked == false);
    }
    const gpa_allocator = gpa_allocator_state.allocator();

    var demo = init(gpa_allocator);
    defer deinit(&demo, gpa_allocator);

    while (true) {
        var message = std.mem.zeroes(w.user32.MSG);
        const has_message = w.user32.peekMessageA(&message, null, 0, 0, w.user32.PM_REMOVE) catch false;
        if (has_message) {
            _ = w.user32.translateMessage(&message);
            _ = w.user32.dispatchMessageA(&message);
            if (message.message == w.user32.WM_QUIT) {
                break;
            }
        } else {
            update(&demo);
            draw(&demo);
        }
    }
}