package world

import "core:testing"
import "core:fmt"
import "core:log"
import "core:math/noise"
import "../vox"

CHUNK_W :: 256
CHUNK_H :: 64
PARTITION_SIZE :: 2
INNER_CHUNK :: 4

TAG_EMPTY :: 0
TAG_FULL :: 1
TAG_USED :: 2


// TODO: turn this into an Octree with Morton Z-Ordering
SparseVoxels :: struct #align(16) {
    partitions: [CHUNK_W/PARTITION_SIZE][CHUNK_H/PARTITION_SIZE][CHUNK_W/PARTITION_SIZE]u8,
    chunks: [CHUNK_W][CHUNK_H][CHUNK_W]u64,
}

putVoxel :: proc(sv: ^SparseVoxels, pos: [3]u32, material: u8) -> u64 {
    //log.debug("PUT", pos)
    chunk:u64 = sv.chunks[pos.x / INNER_CHUNK][pos.y / INNER_CHUNK][pos.z / INNER_CHUNK] | (1 << u64((pos.x % INNER_CHUNK)+(pos.y%INNER_CHUNK)*INNER_CHUNK+(pos.z%INNER_CHUNK)*INNER_CHUNK*INNER_CHUNK))
    sv.chunks[pos.x / INNER_CHUNK][pos.y / INNER_CHUNK][pos.z / INNER_CHUNK] = chunk

    partitionContentSize:u32 = INNER_CHUNK * PARTITION_SIZE
    partitionPos: [3]u32 = pos / partitionContentSize
    sv.partitions[partitionPos.x][partitionPos.y][partitionPos.z] = 1

    return chunk
}

getVoxel :: proc(sv: ^SparseVoxels, pos: [3]u32) -> u64 {
    tag:u64 = (1 << u64((pos.x % INNER_CHUNK)+(pos.y%INNER_CHUNK)*INNER_CHUNK+(pos.z%INNER_CHUNK)*INNER_CHUNK*INNER_CHUNK))

    return sv.chunks[pos.x / INNER_CHUNK][pos.y / INNER_CHUNK][pos.z / INNER_CHUNK] & tag
}

getTotalChunks :: proc() -> u16 {
    return 0
}

generate_world :: proc(sv: ^SparseVoxels) {

    for x:f64 = 0; x < 1024; x += 1 {
        for z:f64 = 0; z < 1024; z += 1 {
            res := noise.noise_2d(34502783, {x / 512,z / 512})
            // putVoxel(sv, { u32(x), u32(64*res), u32(z) }, 1)
            putVoxel(sv, { u32(x), u32(64*(0.75 + res)), u32(z) }, 1)
        }
    }

    load_model(sv, {100,0,512})
}

load_model :: proc(sv: ^SparseVoxels, offset:[3]u32) {
    if v, ok := vox.load_from_file("./assets/tower.vox", context.temp_allocator); ok {
        scene := v.models[0]
        for cube in scene.voxels {
            if(cube.pos.y >= 255 || cube.pos.y >= 255 ) { continue } 

            basePos :[3]u32 = [3]u32 { u32(cube.pos.x), u32(cube.pos.z), u32(cube.pos.y) } + offset;
            putVoxel(sv, basePos, 1)
        }
    }
}

@(test)
put_voxel_test :: proc(t: ^testing.T) {
    voxels := new(SparseVoxels)
    defer free(voxels)

    pos: [3]u32 = {0,0,0}
    chunk := putVoxel(voxels, pos, 1)
    testing.expectf(t, chunk == 1, "Expecting chunks_code=1, got %d", chunk)

    pos = {0,1,0}
    chunk = putVoxel(voxels, pos, 1)
    testing.expectf(t, chunk == 5, "Expecting chunks_code=1, got %d", chunk)

    pos = {0,0,0}
    is_present := getVoxel(voxels, pos)
    testing.expectf(t, is_present > 0, "Expecting is_present > 0, got %d", is_present)

    pos = {0,0,1}
    is_present = getVoxel(voxels, pos)
    testing.expectf(t, is_present == 0, "Expecting is_present == 0, got %d", is_present)
}