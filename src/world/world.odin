package world

import "core:testing"
import "core:fmt"
import "core:log"

CHUNK_W :: 512
CHUNK_H :: 32
PARTITION_SIZE :: 8 
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