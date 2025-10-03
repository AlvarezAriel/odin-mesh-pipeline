package engine

import "core:fmt"
import "core:log"
import os "core:os/os2"
import "core:strings"
import SDL "vendor:sdl3"
import glm "core:math/linalg/glsl"
import "core:time"

import NS  "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

Player :: struct {
    pos: glm.vec3
}

Camera :: struct #align(16) {
	transform:  glm.mat4,
}

EngineState :: struct {
    player: Player,
    camera: ^Camera,
}

EngineBuffers :: struct {
    camera_buffer: ^MTL.Buffer,
}

state: EngineState

init :: proc(device: ^MTL.Device, buffers: ^EngineBuffers) {
    buffers.camera_buffer = device->newBuffer(size_of(Camera), {.StorageModeManaged})
    state.camera = buffers.camera_buffer->contentsAsType(Camera)
}

update :: proc(delta: time.Duration, aspect: f32, buffers: ^EngineBuffers) {
    
    view := glm.mat4LookAt({0, 0, 2}, {0, 0, 0}, {0, 1, 0})
    proj := glm.mat4Perspective(45, aspect, 0.1, 100.0)

    state.camera.transform = proj * view

    buffers.camera_buffer->didModifyRange(NS.Range_Make(0, size_of(Camera)))
}

release :: proc(buffers: ^EngineBuffers) {
    buffers.camera_buffer->release()
}
