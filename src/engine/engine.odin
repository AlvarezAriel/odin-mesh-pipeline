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

SparseVoxels :: struct #align(16) {
    voxels: [512]u8,
}

EngineState :: struct {
    player: Player,
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
}

update :: proc(delta: time.Duration, aspect: f32, buffers: ^EngineBuffers) {
    
    view := glm.mat4LookAt({0, 20, 10}, {0, 0, 0}, {0, 1, 0})
    proj := glm.mat4Perspective(45, aspect, 0.1, 100.0)

    state.camera.transform = proj * view

    buffers.camera_buffer->didModifyRange(NS.Range_Make(0, size_of(Camera)))

    //---



}

release :: proc(buffers: ^EngineBuffers) {
    buffers.camera_buffer->release()
}
