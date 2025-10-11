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
import "vox"

import glm "core:math/linalg/glsl"
import "engine"
import "world"

SHADER_SOURCE :: #load("./shaders/pipeline.metal", string)

engine_buffers: engine.EngineBuffers
pixel_density: f32


build_shaders :: proc(device: ^MTL.Device) -> (library: ^MTL.Library, pso: ^MTL.RenderPipelineState, err: ^NS.Error) {
    shader_src_str := NS.String.alloc()->initWithOdinString(SHADER_SOURCE)
    defer shader_src_str->release()

    library = device->newLibraryWithSource(shader_src_str, nil) or_return

    object_function   := library->newFunctionWithName(NS.AT("objectMain"))
    defer object_function->release()

    mesh_function   := library->newFunctionWithName(NS.AT("meshMain"))
    defer mesh_function->release()

    fragment_function := library->newFunctionWithName(NS.AT("fragmentMain"))
    defer fragment_function->release()

    desc := MTL.MeshRenderPipelineDescriptor.alloc()->init()
    defer desc->release()

    desc->setObjectFunction(object_function)
    desc->setMeshFunction(mesh_function)
    desc->setFragmentFunction(fragment_function)
    desc->colorAttachments()->object(0)->setPixelFormat(.BGRA8Unorm_sRGB)
    desc->setDepthAttachmentPixelFormat(global_config.depth_format)
    desc->setRasterSampleCount(NS.UInteger(global_config.raster_sample_count))

    pso = device->newRenderPipelineStateWithMeshDescriptor(desc, nil, nil) or_return

    return
}

build_depth_stencil :: proc(device: ^MTL.Device) -> (dso: ^MTL.DepthStencilState, err: ^NS.Error) {
    desc := MTL.DepthStencilDescriptor.alloc()->init()
    defer desc->release()

    desc->setDepthCompareFunction(MTL.CompareFunction.Less);
    desc->setDepthWriteEnabled(true);

    dso = device->newDepthStencilState(desc)

    return
}

build_voxel_buffer :: proc(device: ^MTL.Device) {
    if v, ok := vox.load_from_file("./assets/scene_2.vox", context.temp_allocator); ok {
        scene := v.models[0]
        log.debug("loading models", len(v.models))
        for cube in scene.voxels {
            if(cube.pos.y > 255 || cube.pos.y > 255 || cube.pos.z > 64) { continue } 

            basePos :[3]u32 = [3]u32 { u32(cube.pos.x), u32(cube.pos.z), u32(cube.pos.y) } * 2;
            for x in 0..=1 {
                for y in 0..=1 {
                    for z in 0..=1 { 
                        engine.fillVoxel(basePos + {u32(x),u32(y),u32(z)} + {2,0,2}, 1)
                    }
                }
            }
        }
    }

    // for x in 0..=1 {
    //     for y in 0..=1 {
    //         for z in 0..=1 { 
    //             if(x == 1 && z == 1 && y ==1 ) { continue }
    //             engine.fillVoxel({u32(x),u32(y),u32(z)} + {1,1,1}, 1)
    //         }
    //     }
    // }

    // for x in 0..=1 {
    //     for y in 0..=1 {
    //         for z in 0..=1 { 
    //             if(x == 1 && z == 1 && y ==1 ) { continue }
    //             engine.fillVoxel({u32(x),u32(y),u32(z)} + {3,1,1}, 1)
    //         }
    //     }
    // }

    // for x in 0..=1 {
    //     for y in 0..=1 {
    //         for z in 0..=1 { 
    //             if(x == 1 && z == 1 && y ==1 ) { continue }
    //             engine.fillVoxel({u32(x),u32(y),u32(z)} + {16,1,1}, 1)
    //         }
    //     }
    // }

    
    log.debug("Total Chunks loaded:", engine.getTotalChunks())
    

    // engine.fillVoxel({1,1,1}, 1)
    
    // for x in  0..<1024 {
    //     for z in  0..<512 {
    //         engine.fillVoxel({u8(x),0,u8(z)}, 1)
    //     }
    // }
    // engine.fillVoxel({15,2,0}, 1)
    // engine.fillVoxel({31,2,0}, 1)
    // engine.fillVoxel({31,3,0}, 1)
    // engine.fillVoxel({47,2,0}, 1)
    // engine.notifyWorldUpdate(&engine_buffers)
    
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

    window := SDL3.CreateWindow("sdl demo", global_config.window_size.x, global_config.window_size.y, {.HIGH_PIXEL_DENSITY, .RESIZABLE, .METAL})
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
    
    w, h: i32
    SDL3.GetWindowSizeInPixels(window, &w,&h)

    log.debug("window size in pixels", w, h, " display mode:",     SDL3.GetDisplayForWindow(window))
    renderer := SDL3.GetRenderer(window)
    SDL3.SetRenderLogicalPresentation(renderer, w, h, .LETTERBOX)
    SDL3.SetRenderVSync(renderer, global_config.vsync)

    log.debug("Preparing swapchain")
    swapchain->setDevice(device)
    swapchain->setPixelFormat(.BGRA8Unorm_sRGB)
    swapchain->setFramebufferOnly(true)
    swapchain->setFrame(native_window->frame())
    swapchain->setDrawableSize(NS.Size { NS.Float(f32(w)), NS.Float(f32(h)) } )

    native_window->contentView()->setLayer(swapchain)
    native_window->setOpaque(true)
    native_window->setBackgroundColor(nil)

    log.debug("Building shaders")
    library, pso := build_shaders(device) or_return
    defer library->release()
    defer pso->release()

    dso := build_depth_stencil(device) or_return
    defer dso->release()

    log.debug("Initializing engine")
    engine.init(device, &engine_buffers)
    defer engine.release(&engine_buffers)

    log.debug("Initializing world")
    build_voxel_buffer(device)

    command_queue := device->newCommandQueue()
    defer command_queue->release()

    SDL3.ShowWindow(window)
    last_frame_time := time.tick_now()
    event: SDL3.Event


    assert(SDL3.SetWindowRelativeMouseMode(window, true))

    depth_texture: ^MTL.Texture = nil
	defer if depth_texture != nil { depth_texture->release() }

    fps := 0
    elapsed_time:time.Duration = 0
    for quit := false; !quit;  {

        delta := time.tick_since(last_frame_time)
        elapsed_time += delta
		last_frame_time = time.tick_now()
        fps += 1
        if time.duration_seconds(elapsed_time) > 5 {
            log.debug("FPS:",fps / 5)
            elapsed_time = elapsed_time - time.Second * 5
            fps = 0
        }
        w, h: i32
		SDL3.GetWindowSizeInPixels(window, &w, &h)
		aspect_ratio := f32(w)/max(f32(h), 1)


		for SDL3.PollEvent(&event) {
            // TODO: here send input to engine
            engine.input(&event)
			#partial switch event.type {
            case .KEY_DOWN:
                if event.key.key == SDL3.K_ESCAPE {
                    assert(SDL3.SetWindowRelativeMouseMode(window, false))
                }

            case .WINDOW_RESIZED:
                update_window_size()
			case .QUIT:
				quit = true
			}
		}

        engine.update(delta, aspect_ratio, &engine_buffers)

        if depth_texture == nil ||
		   depth_texture->width() != NS.UInteger(w) ||
		   depth_texture->height() != NS.UInteger(h) {
			desc := MTL.TextureDescriptor.texture2DDescriptorWithPixelFormat(
				pixelFormat = global_config.depth_format,
				width = NS.UInteger(w),
				height = NS.UInteger(h),
				mipmapped = false,
			)
			defer desc->release()

			desc->setUsage({.RenderTarget})
			desc->setStorageMode(.Private)

			if depth_texture != nil {
				depth_texture->release()
			}

			depth_texture = device->newTextureWithDescriptor(desc)
		}

        drawable := swapchain->nextDrawable()
        assert(drawable != nil)
        defer drawable->release()

        pass := MTL.RenderPassDescriptor.renderPassDescriptor()
        defer pass->release()

        color_attachment := pass->colorAttachments()->object(0)
        assert(color_attachment != nil)
        color_attachment->setClearColor(MTL.ClearColor{0.0, 0.0, 0.0, 1.0})
        color_attachment->setLoadAction(.Clear)
        color_attachment->setStoreAction(.Store)
        color_attachment->setTexture(drawable->texture())

		depth_attachment := pass->depthAttachment()
		depth_attachment->setTexture(depth_texture)
		depth_attachment->setClearDepth(1.0)
		depth_attachment->setLoadAction(.Clear)
		depth_attachment->setStoreAction(.Store)

        command_buffer := command_queue->commandBuffer()
        defer command_buffer->release()

        render_encoder := command_buffer->renderCommandEncoderWithDescriptor(pass)
        defer render_encoder->release()

        render_encoder->setRenderPipelineState(pso)
        render_encoder->setDepthStencilState(dso)
        render_encoder->setCullMode(.None)

        render_encoder->setObjectBuffer(buffer=engine_buffers.camera_buffer,  offset=0, index=0)
        render_encoder->setObjectBuffer(buffer=engine_buffers.world_buffer,   offset=0, index=1)


        render_encoder->setMeshBuffer(buffer=engine_buffers.camera_buffer,  offset=0, index=0)
        render_encoder->setMeshBuffer(buffer=engine_buffers.world_buffer,   offset=0, index=1)

        render_encoder->drawMeshThreadgroups(MTL.Size {world.CHUNKS_MAX,world.CHUNKS_MAX,world.CHUNKS_MAX}, MTL.Size { 1,1,1 }, MTL.Size { 2,2,2 })

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
