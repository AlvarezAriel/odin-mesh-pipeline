package world

import "core:testing"
import "core:fmt"
import "core:log"

CHUNKS_MAX :: 8

TAG_EMPTY :: 0
TAG_FULL :: 1
TAG_USED :: 2

ChunkHeader :: struct #align(16) {
    tag: u8,
    material: u8,
    idx: u16,
}

// TODO: turn this into an Octree with Morton Z-Ordering
SparseVoxels :: struct #align(16) {
    header: [CHUNKS_MAX][CHUNKS_MAX][CHUNKS_MAX]ChunkHeader,
    chunks: [dynamic]Chunk,
}

Chunk :: struct #align(16) {
    cells: [16][16][16]u8
}


putVoxel :: proc(sv: ^SparseVoxels, pos: [3]u8, material: u8) {
    header := _chunkForPosition(sv, pos)
    
    c: ^Chunk
    chunkPos := pos % CHUNKS_MAX

    if(header.tag == TAG_EMPTY) {
        chunk := Chunk { }
        
        size, _ := append(&(sv.chunks), chunk)

        header.idx = u16(size) - 1
        header.tag = TAG_USED
    }

    c = &(sv.chunks[header.idx])

    c.cells[chunkPos.x][chunkPos.y][chunkPos.z] = material
}

_chunkForPosition :: proc(sv: ^SparseVoxels, pos: [3]u8) -> ^ChunkHeader {
    p := pos / CHUNKS_MAX
    return &(sv.header[p.x][p.y][p.z])
} 

getVoxel :: proc(sv: ^SparseVoxels, pos: [3]u8) -> u8 {
    header := _chunkForPosition(sv, pos)
    if(header.tag == TAG_EMPTY) {
        return 0
    }

    chunkPos := pos % CHUNKS_MAX

    return  sv.chunks[header.idx].cells[chunkPos.x][chunkPos.y][chunkPos.z]
}

@(test)
put_voxel_test :: proc(t: ^testing.T) {
    voxels := SparseVoxels {}
    defer delete(voxels.chunks)

    pos: [3]u8 = {2,2,2}

    putVoxel(&voxels, pos, 5)
    tag := voxels.header[0][0][0].tag
    testing.expectf(t, tag == TAG_USED, "Expecting TAG_USED, got %d", tag)

    chunks_size := len(voxels.chunks)
    testing.expectf(t, chunks_size == 1, "Expecting chunks_size=1, got %d", chunks_size)

    cell_material := voxels.chunks[0].cells[2][2][2]
    testing.expectf(t, cell_material == 5, "Expecting cell_material=5, got %d", cell_material)

    material := getVoxel(&voxels, pos)
    testing.expectf(t, material == 5, "Expecting 5, got %d", material)
}