package world

import "core:testing"
import "core:fmt"
import "core:log"

CHUNKS_MAX :: 32
CHUNK_SIZE :: 32
CONCURRENT_CHUNKS_MAX :: 128

TAG_EMPTY :: 0
TAG_FULL :: 1
TAG_USED :: 2


// TODO: turn this into an Octree with Morton Z-Ordering
SparseVoxels :: struct #align(16) {
    last_chunk_idx: u8,
    tags: [CHUNKS_MAX][CHUNKS_MAX][CHUNKS_MAX]u8,
    materials: [CHUNKS_MAX][CHUNKS_MAX][CHUNKS_MAX]u8,
    idxs: [CHUNKS_MAX][CHUNKS_MAX][CHUNKS_MAX]u8,
    chunks: [CONCURRENT_CHUNKS_MAX][CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE]u8,
}

putVoxel :: proc(sv: ^SparseVoxels, pos: [3]u8, material: u8) {
    p := pos / CHUNK_SIZE
    chunkPos := pos % CHUNK_SIZE

    if(sv.tags[p.x][p.y][p.z] == TAG_EMPTY) {
        sv.tags[p.x][p.y][p.z] = TAG_USED
        sv.materials[p.x][p.y][p.z] = material

        sv.last_chunk_idx += 1
        sv.idxs[p.x][p.y][p.z] = sv.last_chunk_idx
        sv.chunks[sv.last_chunk_idx][chunkPos.x][chunkPos.y][chunkPos.z] = material
        log.debug("new header", sv.last_chunk_idx, " pos ", p)
    } else {
        idx := sv.idxs[p.x][p.y][p.z]
        sv.chunks[idx][chunkPos.x][chunkPos.y][chunkPos.z] = material
    }
    // sv.tags
    // c: ^Chunk
    // chunkPos := pos % CHUNKS_MAX

    // if(header.tag == TAG_EMPTY) {
    //     chunk := Chunk { }
        
    //     //size, _ := append(&(sv.chunks), chunk)

    //     //header.idx = u8(size - 1)
    //     header.tag = TAG_USED
    //     log.debug("NEW HEADER", pos / CHUNKS_MAX)
    // }

    //c = &(sv.chunks[header.idx])

    //c.cells[chunkPos.x][chunkPos.y][chunkPos.z] = material
}

// getVoxel :: proc(sv: ^SparseVoxels, pos: [3]u8) -> u8 {
//     p := pos / CHUNKS_MAX
//     header := _chunkForPosition(sv, pos)
//     if(header.tag == TAG_EMPTY) {
//         return 0
//     }

//     chunkPos := pos % CHUNKS_MAX

//     return 1;//return  sv.chunks[header.idx].cells[chunkPos.x][chunkPos.y][chunkPos.z]
// }

// @(test)
// put_voxel_test :: proc(t: ^testing.T) {
//     voxels := SparseVoxels {}
//     defer delete(voxels.chunks)

//     pos: [3]u8 = {2,2,2}

//     putVoxel(&voxels, pos, 5)
//     tag := voxels.header[0][0][0].tag
//     testing.expectf(t, tag == TAG_USED, "Expecting TAG_USED, got %d", tag)

//     chunks_size := len(voxels.chunks)
//     testing.expectf(t, chunks_size == 1, "Expecting chunks_size=1, got %d", chunks_size)

//     cell_material := voxels.chunks[0].cells[2][2][2]
//     testing.expectf(t, cell_material == 5, "Expecting cell_material=5, got %d", cell_material)

//     material := getVoxel(&voxels, pos)
//     testing.expectf(t, material == 5, "Expecting 5, got %d", material)
// }