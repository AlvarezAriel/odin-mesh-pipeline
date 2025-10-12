package world

import "core:testing"
import "core:fmt"
import "core:log"

CHUNKS_MAX :: 128
CHUNK_SIZE :: 128
CONCURRENT_CHUNKS_MAX :: 3000

CHUNK_W :: 128
CHUNK_H :: 64

TAG_EMPTY :: 0
TAG_FULL :: 1
TAG_USED :: 2


// TODO: turn this into an Octree with Morton Z-Ordering
SparseVoxels :: struct #align(16) {
    chunks: [CHUNK_W][CHUNK_H][CHUNK_W]u8,
}

putVoxel :: proc(sv: ^SparseVoxels, pos: [3]u32, material: u8) -> u8 {
    //log.debug("PUT", pos)
    chunk:u8 = sv.chunks[pos.x / 2][pos.y / 2][pos.z / 2] | (0b00000001 << u8((pos.x % 2)+(pos.y%2)*2+(pos.z%2)*4))
    sv.chunks[pos.x / 2][pos.y / 2][pos.z / 2] = chunk
    return chunk
}

getVoxel :: proc(sv: ^SparseVoxels, pos: [3]u32) -> u8 {
    tag:u8 = (0b00000001 << u8((pos.x % 2)+(pos.y%2)*2+(pos.z%2)*4))

    return sv.chunks[pos.x / 2][pos.y / 2][pos.z / 2] & tag
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