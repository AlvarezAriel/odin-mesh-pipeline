package pipeline

import "core:os"
import NS  "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

build_managed_texture :: proc(device: ^MTL.Device, w: uint, h: uint) -> ^MTL.Texture {
    desc := MTL.TextureDescriptor.alloc()->init()
    defer desc->release()

    desc->setWidth(NS.UInteger(w))
    desc->setHeight(NS.UInteger(h))
    desc->setPixelFormat(.RGBA8Unorm)
    desc->setStorageMode(.Managed)
    desc->setUsage({ .ShaderRead, .ShaderWrite })

    return device->newTextureWithDescriptor(desc)
}

build_compute_pipeline :: proc(device: ^MTL.Device, filename: string, entrypoint: string) -> (pso: ^MTL.ComputePipelineState, err: ^NS.Error) {
    kernel_src, ok := os.read_entire_file_from_filename(filename)

    kernel_src_str := NS.String.alloc()->initWithOdinString(string(kernel_src))
    defer kernel_src_str->release()

    compute_library := device->newLibraryWithSource(kernel_src_str, nil) or_return
    defer compute_library->release()

    entrypoint_string_name := NS.String.alloc()->initWithOdinString(string(entrypoint))
    defer entrypoint_string_name->release()

    line_rasterizer := compute_library->newFunctionWithName(entrypoint_string_name)
    defer line_rasterizer->release()

    return device->newComputePipelineStateWithFunction(line_rasterizer)
}

build_render_pipeline :: proc(
    device: ^MTL.Device,
    filename: string,
    vertex_entrypoint:string,
    fragment_entrypoint:string
) -> (state: ^MTL.RenderPipelineState, error: ^NS.Error) {

    compile_options := NS.new(MTL.CompileOptions)
    defer compile_options->release()

    program_src, ok := os.read_entire_file_from_filename(filename)

    program_src_str := NS.String.alloc()->initWithOdinString(string(program_src))
    defer program_src_str->release()

    program_library := device->newLibraryWithSource(program_src_str, compile_options) or_return

    // --- vertex
    ns_vertex_entrypoint := NS.String.alloc()->initWithOdinString(string(vertex_entrypoint))
    defer ns_vertex_entrypoint->release()

    vertex_program := program_library->newFunctionWithName(ns_vertex_entrypoint)
    assert(vertex_program != nil)

    // --- fragment
    ns_fragment_entrypoint := NS.String.alloc()->initWithOdinString(string(fragment_entrypoint))
    defer ns_fragment_entrypoint->release()

    fragment_program := program_library->newFunctionWithName(ns_fragment_entrypoint)

    assert(fragment_program != nil)

    // ------------

    pipeline_state_descriptor := NS.new(MTL.RenderPipelineDescriptor)
    pipeline_state_descriptor->colorAttachments()->object(0)->setPixelFormat(.BGRA8Unorm_sRGB)
    pipeline_state_descriptor->setVertexFunction(vertex_program)
    pipeline_state_descriptor->setFragmentFunction(fragment_program)

    return device->newRenderPipelineState(pipeline_state_descriptor)
}
