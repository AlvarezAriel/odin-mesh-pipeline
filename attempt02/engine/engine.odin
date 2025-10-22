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
    enabled: bool,
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
    target: glm.vec4,
    sun: glm.vec4,
    light_step: u32,
}


EngineState :: struct {
    player: Player,
    controls: Controls,
    camera: ^Camera,
    world: ^world.SparseVoxels,
    should_update_world: bool, // TODO: use actual regions instead of updating the whole thing
}

EngineBuffers :: struct {
    should_compute: bool,
    camera_buffer: ^MTL.Buffer,
    world_buffer: ^MTL.Buffer,
    light_buffer: ^MTL.Buffer,
}

InternalLightTransport :: struct #align(16) {
    chunks: [world.CHUNK_W*world.INNER_CHUNK][world.CHUNK_H*world.INNER_CHUNK][world.CHUNK_W*world.INNER_CHUNK]f16,
}

state: EngineState

init :: proc(device: ^MTL.Device, buffers: ^EngineBuffers) {
    buffers.camera_buffer = device->newBuffer(size_of(Camera), {.StorageModeManaged})
    state.camera = buffers.camera_buffer->contentsAsType(Camera)

    buffers.light_buffer = device->newBuffer(size_of(InternalLightTransport), MTL.ResourceOptions{.StorageModePrivate})
    buffers.should_compute = true;
    state.camera.light_step = 0

    buffers.world_buffer = device->newBuffer(size_of(world.SparseVoxels), {.StorageModeManaged})
    state.world = buffers.world_buffer->contentsAsType(world.SparseVoxels)

    state.player.pos  = { 255.84962, 138.37822, 396.55328, 0}
    state.player.look = { -0.18924446, -0.35738355, 0.91458386, 0}
    state.camera.sun =  {0.17285791, 0.5965225, 0.78376079, 0};

    
    state.controls.enabled = true

    world.generate_world(state.world)
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

    if(state.controls.sun_x != 0 || state.controls.sun_z != 0) {
        buffers.should_compute = true
    }

    sun_rotation := glm.mat4Rotate({0,1,0}, d*(state.controls.sun_x - state.controls.sun_z))
    state.camera.sun = glm.normalize(sun_rotation * state.camera.sun)

    if(state.camera.light_step + 1 >= world.CHUNK_W / 8) {
        state.camera.light_step = 0
        buffers.should_compute = false
    } else {
        state.camera.light_step += 1
    }


    collision, ok := castRayCollision().?
    if(ok) {
        state.camera.target = {f32(collision.x), f32(collision.y), f32(collision.z), 0}
    }

    if state.should_update_world {
        state.should_update_world = false
        if(ok) {
            state.camera.light_step = collision.z / (world.INNER_CHUNK * 8)
        } else {
            state.camera.light_step = 0
        }
        notifyWorldUpdate(buffers)
        buffers.should_compute = true
        
    }

    buffers.camera_buffer->didModifyRange(NS.Range_Make(0, size_of(Camera)))
}

side_look_dir :: proc() -> (side_direction: glm.vec4){
    side_direction.xyz = glm.cross_vec3({ 0, 1, 0}, state.player.look.xyz)
    return 
}

edit_world :: proc() {
    collision, ok := castRayCollision().?
    log.debug("ADD BLOCK: ", collision)
    if(ok) {
        world.putSphere(state.world, collision, 4)
        state.should_update_world = true
    }
}

input :: proc(event: ^SDL.Event) {


    if event.type == SDL.EventType.MOUSE_BUTTON_DOWN { 
        if(state.controls.enabled == false) {
            state.controls.enabled = true
        } else {
            edit_world()
        }
    }

    if !state.controls.enabled {
        return
    }
    
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
        case SDL.K_ESCAPE:
            state.controls.enabled = false 
    }

    log.debug(state.player.pos, state.player.look, state.camera.sun)
}

castRayCollision :: proc() -> Maybe([3]u32) {
    from := state.camera.pos.xyz
    dir  := state.camera.look.xyz
    f := [3]int { int(from.x), int(from.y), int(from.z) }
    m := math.max(math.abs(dir.x), math.max(math.abs(dir.y), math.abs(dir.z)))
    st := 1.0 / m
    step := dir * st
    maxY: u32 =  world.CHUNK_H*world.INNER_CHUNK
    maxW: u32 =  world.CHUNK_W*world.INNER_CHUNK
    should_set_shadow := false

    i: f32 = 1
    next: [3]u32
    prev: [3]u32
    for ; i < world.CHUNK_W*world.INNER_CHUNK; i += 1 {
        s := step * i
        floatnext := f + [3]int {int(math.trunc(s.x)),int(math.trunc(s.y)),int(math.trunc(s.z))}
        prev = next
        next = [3]u32 { u32(floatnext.x), u32(floatnext.y), u32(floatnext.z)}
        if(next.x >= maxW || next.y >= maxY || next.z >= maxW) {
            break
        }

        if(world.getVoxel(state.world, next) > 0) {
            return prev
        }
    }

    return nil
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
    buffers.light_buffer->release()
    // if(state.world != nil) {
    //     delete(state.world.chunks)
    // }
}

