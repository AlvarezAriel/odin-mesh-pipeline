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

import "../world"

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
    sun_z: f32,
    sun_x: f32,
}

Camera :: struct #align(16) {
	transform:  glm.mat4,
    pos: glm.vec4,
    look: glm.vec4,
    sun: glm.vec4,
}


EngineState :: struct {
    player: Player,
    controls: Controls,
    camera: ^Camera,
    world: ^world.SparseVoxels,
}

EngineBuffers :: struct {
    camera_buffer: ^MTL.Buffer,
    world_buffer: ^MTL.Buffer,
}

state: EngineState

init :: proc(device: ^MTL.Device, buffers: ^EngineBuffers) {
    buffers.camera_buffer = device->newBuffer(size_of(Camera), {.StorageModeManaged})
    state.camera = buffers.camera_buffer->contentsAsType(Camera)

    buffers.world_buffer = device->newBuffer(size_of(world.SparseVoxels), {.StorageModeManaged})
    state.world = buffers.world_buffer->contentsAsType(world.SparseVoxels)

    state.player.pos  = { 0, 0, 3, 0}
    state.player.look = { 0, 0,-1, 0}
    state.camera.sun =  {1.13,1.1,-0.5, 0};
}

fillVoxel :: proc(pos: [3]u32, material: u8) {
    world.putVoxel(state.world, pos, material)
}

getTotalChunks :: proc() -> u16 {
    return 0
}

notifyWorldUpdate :: proc(buffers: ^EngineBuffers) {
    // size: uint = size_of(state.world.header) + size_of(world.Chunk) * len(state.world.chunks)
    // log.debug("notifyWorldUpdate", size)     
    //buffers.world_buffer->didModifyRange(NS.Range_Make(0, NS.UInteger(size)))
    buffers.world_buffer->didModifyRange(NS.Range_Make(0, size_of(world.SparseVoxels)))
    //log.debug("HEADERS---->", state.world.header[1][1][1])
}

update :: proc(delta: time.Duration, aspect: f32, buffers: ^EngineBuffers) {
    
    d := f32(time.duration_seconds(delta))
    state.player.speed.x = state.controls.left - state.controls.right
    voxes_per_second :f32 = d * 60.014563

    direction := glm.normalize(state.player.look * { 1, 0, 1, 0})

    state.player.pos = state.player.pos + (direction * (state.controls.forward - state.controls.back) * voxes_per_second)

    side_direction := side_look_dir()
    state.player.pos = state.player.pos + side_direction * (state.controls.left - state.controls.right) * voxes_per_second

    state.player.pos = state.player.pos + {0, (state.controls.up - state.controls.down), 0, 0 } * voxes_per_second

    view := glm.mat4LookAt(state.player.pos.xyz, state.player.pos.xyz + state.player.look.xyz, {0, -1, 0})
    proj := glm.mat4Perspective(43, aspect, 0.05, 5000.0)

    state.camera.transform = proj * view
    state.camera.pos = state.player.pos
    state.camera.look = glm.normalize(state.player.look)

    sun_rotation := glm.mat4Rotate({0,1,0}, d*(state.controls.sun_x - state.controls.sun_z))
    state.camera.sun = glm.normalize(sun_rotation * state.camera.sun)

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
        case SDL.K_Z:     
            state.controls.sun_z = value
        case SDL.K_X:     
            state.controls.sun_x = value
        case SDL.K_LSHIFT:     
            state.controls.down = value
        case SDL.K_SPACE:     
            state.controls.up = value
    }

    log.debug(state.player.pos, state.player.look)
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
    buffers.world_buffer->release()
    // if(state.world != nil) {
    //     delete(state.world.chunks)
    // }
}

