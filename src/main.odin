package main

import NS  "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA  "vendor:darwin/QuartzCore"

import SDL3 "vendor:sdl3"

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:time"

SHADER_SOURCE :: #load("./shaders/pipeline.metal", string)

build_shaders :: proc(device: ^MTL.Device) -> (library: ^MTL.Library, pso: ^MTL.RenderPipelineState, err: ^NS.Error) {
    shader_src_str := NS.String.alloc()->initWithOdinString(SHADER_SOURCE)
    defer shader_src_str->release()

    library = device->newLibraryWithSource(shader_src_str, nil) or_return

    mesh_function   := library->newFunctionWithName(NS.AT("meshMain"))
    fragment_function := library->newFunctionWithName(NS.AT("fragmentMain"))
    defer mesh_function->release()
    defer fragment_function->release()

    desc := MTL.MeshRenderPipelineDescriptor.alloc()->init()
    defer desc->release()

    desc->setMeshFunction(mesh_function)
    desc->setFragmentFunction(fragment_function)
    desc->colorAttachments()->object(0)->setPixelFormat(.BGRA8Unorm_sRGB)
    desc->setDepthAttachmentPixelFormat(.Depth32Float)

    pso = device->newRenderPipelineStateWithMeshDescriptor(desc, nil, nil) or_return
    return
}

metal_main :: proc() -> (err: ^NS.Error) {
    cl := log.create_console_logger()
	context.logger = cl

    tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, context.allocator)
    context.allocator = mem.tracking_allocator(&tracking_allocator)
	defer reset_tracking_allocator()

	if !SDL3.Init({.VIDEO}) {
		log.fatalf("unable to initialize sdl, error: %s", SDL3.GetError())
	}

    device := MTL.CreateSystemDefaultDevice()
    if device == nil {
		log.fatal("unable to initialize gpu METAL device")
	}

    window := SDL3.CreateWindow("sdl demo", 800, 600, {.HIGH_PIXEL_DENSITY, .RESIZABLE, .METAL})
	if window == nil {
		log.fatalf("unable to initialize window, error: %s", SDL3.GetError())
	}

    native_window := (^NS.Window)(SDL3.GetPointerProperty(SDL3.GetWindowProperties(window), SDL3.PROP_WINDOW_COCOA_WINDOW_POINTER, nil))
    if (native_window == nil) {
        log.fatal("unable to fetch native window info")
    }

	fmt.println(device->name()->odinString())

    swapchain := CA.MetalLayer.layer()
    defer swapchain->release()

    swapchain->setDevice(device)
    swapchain->setPixelFormat(.BGRA8Unorm_sRGB)
    swapchain->setFramebufferOnly(true)
    swapchain->setFrame(native_window->frame())

    native_window->contentView()->setLayer(swapchain)
    native_window->setOpaque(true)
    native_window->setBackgroundColor(nil)

    library, pso := build_shaders(device) or_return
    defer library->release()
    defer pso->release()

    command_queue := device->newCommandQueue()
    defer command_queue->release()

    SDL3.ShowWindow(window)
    start_tick := time.tick_now()
    event: SDL3.Event

    for quit := false; !quit;  {

        duration := time.tick_since(start_tick)
		elapsed_time := f32(time.duration_seconds(duration))

		for SDL3.PollEvent(&event) {
            // TODO: here send input to engine

			#partial switch event.type {
            case .WINDOW_RESIZED:
                update_window_size()
			case .QUIT:
				quit = true
			}
		}

        drawable := swapchain->nextDrawable()
        assert(drawable != nil)
        defer drawable->release()

        pass := MTL.RenderPassDescriptor.renderPassDescriptor()
        defer pass->release()

        color_attachment := pass->colorAttachments()->object(0)
        assert(color_attachment != nil)
        color_attachment->setClearColor(MTL.ClearColor{0.25, 0.5, 1.0, 1.0})
        color_attachment->setLoadAction(.Clear)
        color_attachment->setStoreAction(.Store)
        color_attachment->setTexture(drawable->texture())

        command_buffer := command_queue->commandBuffer()
        defer command_buffer->release()

        render_encoder := command_buffer->renderCommandEncoderWithDescriptor(pass)
        defer render_encoder->release()

        render_encoder->setRenderPipelineState(pso)

        // TODO: the thread values are just for the example, use proper ones later!!
        render_encoder->drawMeshThreadgroups(MTL.Size { 1,1,1 }, MTL.Size { 0,0,0 }, MTL.Size { 1,1,1 })

        render_encoder->endEncoding()

        command_buffer->presentDrawable(drawable)
        command_buffer->commit()
    }

    return nil
}

update_window_size :: proc() {
    // SDL.GetWindowSize(ctx.window, &ctx.window_size[0], &ctx.window_size[1])
}

main :: proc() {
    err := metal_main()
    if err != nil {
        fmt.eprintln(err->localizedDescription()->odinString())
        os.exit(1)
    }
}

reset_tracking_allocator :: proc() -> bool {
	a := cast(^mem.Tracking_Allocator)context.allocator.data
	err := false
	if len(a.allocation_map) > 0 {
		log.warnf("Leaked allocation count: %v", len(a.allocation_map))
	}
	for _, v in a.allocation_map {
		log.warnf("%v: Leaked %v bytes", v.location, v.size)
		err = true
	}

	mem.tracking_allocator_clear(a)
	return err
}
