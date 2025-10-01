package engine

import glm "core:math/linalg/glsl"
import SDL "vendor:sdl2"
import "core:fmt"

Shader_Data :: struct {
    camera: ^Camera_Data,
    fragment_uniform: ^FragmentUniform,
    compute_uniform: ^ComputeUniform,
    voxel_data: ^Voxel_Data,
    requires_computation: bool,
}

Voxel_Data :: struct #align (16) {
    points: [16][16]u16,
}

Camera_Data :: struct #align (16) {
    look: matrix[4, 4]f32,
}

FragmentUniform :: struct #align (16) {
    cursor: [4]f32,
    toggle_layer: [4]f32,
    screen_size: [2]f32,
}

ComputeUniform :: struct #align (16) {
    cursor: [4]f32,
    flags: [4]f32,
}

init :: proc(shader_data: ^Shader_Data, screen_size: [2]f32) {
    for i := 0; i < 16; i += 1 {
        shader_data.voxel_data.points[i][i] = 1
    }

    shader_data.fragment_uniform.screen_size = screen_size
    shader_data.fragment_uniform.toggle_layer = { 1.0, 1.0, 1.0, 1.0 }
    shader_data.fragment_uniform.cursor = { 0.0, 0.0, 0.0, 0.0 }
    shader_data.compute_uniform.cursor = { 0.0, 0.0, 0.0, 0.0 }
    shader_data.camera.look = glm.mat4LookAt({ 0, 0, -1 }, { 0, 0, 0 }, { 0, 1, 0 })
    shader_data.requires_computation = true
}

input :: proc(event: SDL.Event, shader_data: ^Shader_Data) {
    #partial switch event.type {
    case .MOUSEMOTION:
        new_pos : [2]f32 = { f32(event.motion.x), f32(event.motion.y) }
        shader_data.fragment_uniform.cursor.x = new_pos.x
        shader_data.fragment_uniform.cursor.y = new_pos.y
        shader_data.compute_uniform.cursor.x = new_pos.x
        shader_data.compute_uniform.cursor.y = new_pos.y
        fmt.println("MOUSEMOTION ", new_pos)
    case .MOUSEBUTTONDOWN:
        new_pos : [2]f32 = { f32(event.button.x), f32(event.button.y) }
        shader_data.compute_uniform.cursor.z = new_pos.x
        shader_data.compute_uniform.cursor.w = new_pos.y
        fmt.println("MOUSEBUTTONDOWN ", new_pos)
    }

}

update :: proc(elapsed_time: f32, shader_data: ^Shader_Data) {
    shader_data.compute_uniform.flags[0] += 1.0;
    shader_data.compute_uniform.flags[1] = elapsed_time;
}
