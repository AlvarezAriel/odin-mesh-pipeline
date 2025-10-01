package main

import NS  "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA  "vendor:darwin/QuartzCore"

import SDL "vendor:sdl2"

import "core:fmt"
import "core:os"
import "core:math"
import glm "core:math/linalg/glsl"

SHADER_SOURCE :: #load("./shaders/pipeline.metal", string)

Instance_Data :: struct #align(16) {
    transform: glm.mat4,
    color:     glm.vec4,
}

NUM_INSTANCES :: 32

Camera_Data :: struct {
    perspective_transform: glm.mat4,
    world_transform:       glm.mat4,
}

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
    SDL.SetHint(SDL.HINT_RENDER_DRIVER, "metal")
    SDL.setenv("METAL_DEVICE_WRAPPER_TYPE", "1", 0)
    SDL.Init({.VIDEO})
    defer SDL.Quit()

    window := SDL.CreateWindow("Metal Mesh Pipeline",
        SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED,
        854, 480,
        {.ALLOW_HIGHDPI, .HIDDEN, .RESIZABLE},
    )
    defer SDL.DestroyWindow(window)

    window_system_info: SDL.SysWMinfo
    SDL.GetVersion(&window_system_info.version)
    SDL.GetWindowWMInfo(window, &window_system_info)
    assert(window_system_info.subsystem == .COCOA)

    native_window := (^NS.Window)(window_system_info.info.cocoa.window)

    device := MTL.CreateSystemDefaultDevice()
    defer device->release()

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

    camera_buffer := device->newBuffer(size_of(Camera_Data), {.StorageModeManaged})
    defer camera_buffer->release()

    command_queue := device->newCommandQueue()
    defer command_queue->release()

    SDL.ShowWindow(window)
    for quit := false; !quit;  {
        for e: SDL.Event; SDL.PollEvent(&e); {
            #partial switch e.type {
            case .QUIT:
                quit = true
            case .KEYDOWN:
                if e.key.keysym.sym == .ESCAPE {
                    quit = true
                }
            }
        }

        w, h: i32
        SDL.GetWindowSize(window, &w, &h)
        aspect_ratio := f32(w)/max(f32(h), 1)

        {
            camera_data := camera_buffer->contentsAsType(Camera_Data)
            camera_data.perspective_transform = glm.mat4Perspective(glm.radians_f32(45), aspect_ratio, 0.03, 500)
            camera_data.world_transform = 1
            camera_buffer->didModifyRange(NS.Range_Make(0, size_of(Camera_Data)))
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

main :: proc() {
    err := metal_main()
    if err != nil {
        fmt.eprintln(err->localizedDescription()->odinString())
        os.exit(1)
    }
}