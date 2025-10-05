package engine

import "core:fmt"
import "core:log"
import os "core:os/os2"
import "core:strings"
import SDL "vendor:sdl3"
import glm "core:math/linalg/glsl"
import "core:time"
import "core:math"

import NS  "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

Player :: struct {
    pos: glm.vec4,
    speed: glm.vec4,
    look: glm.vec4,
}

Controls :: struct {
    left: f32,
    right: f32,
    forward: f32,
    back: f32,
    up: f32,
    down: f32,
}

Camera :: struct #align(16) {
	transform:  glm.mat4,
}

SparseVoxels :: struct #align(16) {
    voxels: [512]u8,
}

EngineState :: struct {
    player: Player,
    controls: Controls,
    camera: ^Camera,
    sparse_voxels: ^SparseVoxels,
}

EngineBuffers :: struct {
    camera_buffer: ^MTL.Buffer,
    sparse_voxels_buffer: ^MTL.Buffer,
}

state: EngineState

init :: proc(device: ^MTL.Device, buffers: ^EngineBuffers) {
    buffers.camera_buffer = device->newBuffer(size_of(Camera), {.StorageModeManaged})
    state.camera = buffers.camera_buffer->contentsAsType(Camera)

    buffers.sparse_voxels_buffer = device->newBuffer(size_of(SparseVoxels), {.StorageModeManaged})
    state.sparse_voxels = buffers.sparse_voxels_buffer->contentsAsType(SparseVoxels)

    state.player.pos  = { 0, 1.0, 4, 0}
    state.player.look = { 0, 0, -1, 0}
    log.debug("initial look", state.player.look)
}

update :: proc(delta: time.Duration, aspect: f32, buffers: ^EngineBuffers) {
    
    d := f32(time.duration_seconds(delta))
    state.player.speed.x = state.controls.left - state.controls.right
    voxes_per_second :f32 = d * 100

    direction := glm.normalize(state.player.look * { 1, 0, 1, 0})

    state.player.pos = state.player.pos + (direction * (state.controls.forward - state.controls.back) * voxes_per_second)

    side_direction := side_look_dir()
    state.player.pos = state.player.pos + side_direction * (state.controls.left - state.controls.right) * voxes_per_second

    state.player.pos = state.player.pos + {0, (state.controls.up - state.controls.down), 0, 0 } * voxes_per_second

    view := glm.mat4LookAt(state.player.pos.xyz, state.player.pos.xyz + state.player.look.xyz, {0, -1, 0})
    proj := glm.mat4Perspective(43, aspect, 0.05, 5000.0)

    state.camera.transform = proj * view

    buffers.camera_buffer->didModifyRange(NS.Range_Make(0, size_of(Camera)))

    //---
}

side_look_dir :: proc() -> (side_direction: glm.vec4){
    side_direction.xyz = glm.cross_vec3({ 0, 1, 0}, state.player.look.xyz)
    return 
}

input :: proc(event: ^SDL.Event) {
    calcCameraYaw(event)
    // TODO: use scancodes instead
    value: f32 = 0
    if event.type == SDL.EventType.KEY_DOWN {
        value = 1
    } else if event.type == SDL.EventType.KEY_UP {
        value = 0
    } else {
        return
    }
    
    switch event.key.key {
        case SDL.K_W:
            state.controls.forward = value
        case SDL.K_S:     
            state.controls.back = value
        case SDL.K_A:     
            state.controls.left = value
        case SDL.K_D:     
            state.controls.right = value
        case SDL.K_LSHIFT:     
            state.controls.down = value
        case SDL.K_SPACE:     
            state.controls.up = value
    }
}

calcCameraYaw :: proc(event: ^SDL.Event) {

    sensitivity: f32 = 0.001




    if event.type == SDL.EventType.MOUSE_MOTION {
        yrotation := glm.mat4Rotate({0,1,0}, -event.motion.xrel * sensitivity)
        xrotation := glm.mat4Rotate(side_look_dir().xyz, event.motion.yrel * sensitivity)
        state.player.look = glm.normalize(yrotation * state.player.look)
        state.player.look = glm.normalize(xrotation * state.player.look)
    }
}

release :: proc(buffers: ^EngineBuffers) {
    buffers.camera_buffer->release()
}
