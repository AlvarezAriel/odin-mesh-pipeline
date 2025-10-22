package world

import "core:testing"
import "core:fmt"
import "core:log"
import "core:math/noise"
import "core:math/linalg"
import "core:math"
import "../vox"

CHUNK_W :: 256
CHUNK_H :: 64
PARTITION_SIZE_W :: 4
PARTITION_SIZE_H :: 2
INNER_CHUNK :: 4

TAG_EMPTY :: 0
TAG_FULL :: 1
TAG_USED :: 2


// TODO: turn this into an Octree with Morton Z-Ordering
SparseVoxels :: struct #align(16) {
    partitions: [CHUNK_W/PARTITION_SIZE_W][CHUNK_H/PARTITION_SIZE_H][CHUNK_W/PARTITION_SIZE_W]u8,
    chunks: [CHUNK_W][CHUNK_H][CHUNK_W]u64,
}

putVoxel :: proc(sv: ^SparseVoxels, pos: [3]u32, material: u8) -> u64 {
    //log.debug("PUT", pos)
    if(pos.y >= CHUNK_H*INNER_CHUNK || pos.x >= CHUNK_W*INNER_CHUNK || pos.z >= CHUNK_W*INNER_CHUNK) { return 0 }

    chunk:u64 = sv.chunks[pos.x / INNER_CHUNK][pos.y / INNER_CHUNK][pos.z / INNER_CHUNK] | (1 << u64((pos.x % INNER_CHUNK)+(pos.y%INNER_CHUNK)*INNER_CHUNK+(pos.z%INNER_CHUNK)*INNER_CHUNK*INNER_CHUNK))
    sv.chunks[pos.x / INNER_CHUNK][pos.y / INNER_CHUNK][pos.z / INNER_CHUNK] = chunk

    partitionContentSize := [3]u32 {PARTITION_SIZE_W, PARTITION_SIZE_H, PARTITION_SIZE_W} * INNER_CHUNK  
    partitionPos: [3]u32 = pos / partitionContentSize
    sv.partitions[partitionPos.x][partitionPos.y][partitionPos.z] = 1

    return chunk
}

getVoxel :: proc(sv: ^SparseVoxels, pos: [3]u32) -> u64 {
    tag:u64 = (1 << u64((pos.x % INNER_CHUNK)+(pos.y%INNER_CHUNK)*INNER_CHUNK+(pos.z%INNER_CHUNK)*INNER_CHUNK*INNER_CHUNK))

    return sv.chunks[pos.x / INNER_CHUNK][pos.y / INNER_CHUNK][pos.z / INNER_CHUNK] & tag
}

minus :: proc(x:u32, y:u32) -> u32 {
    r := int(x) - int(y)
    if r < 0 {
        return 0
    } else {
        return u32(r)
    }
}


putSphere :: proc(sv: ^SparseVoxels, center: [3]u32, radius: u32) {
    fCenter := [3]f32{f32(center.x),f32(center.y),f32(center.z)}
    start :[3]u32 = {  minus(center.x, radius), minus(center.y, radius), minus(center.z, radius) }
    for x:u32 = 0; x < radius*2; x += 1 {
        for y:u32 = 0; y < radius*2; y += 1 {
            for z:u32 = 0; z < radius*2; z += 1 {
                pos:[3]u32 = start + {x,y,z}
                fPos:[3]f32 = {f32(pos.x),f32(pos.y),f32(pos.z)}
                if linalg.distance(fCenter, fPos) < f32(radius) {
                    putVoxel(sv, pos, 1)
                    log.debug("PUT V", pos)
                }
            }
        }
    }
    putVoxel(sv, center, 1)
}

getTotalChunks :: proc() -> u16 {
    return 0
}

generate_world :: proc(sv: ^SparseVoxels) {

    load_sponza(sv, {0,0,0})

}

load_sponza :: proc(sv: ^SparseVoxels, offset:[3]u32) {
    if v, ok := vox.load_from_file("./assets/sponza.vox", context.temp_allocator); ok {
        count:u32 = 0
        for scene in v.models {
            sceneOffset: [3]u32 = { u32(scene.size.x), u32(scene.size.y),u32(scene.size.z) } 
            count += 1
            for cube in scene.voxels {
                // if(cube.pos.y >= CHUNK_H*INNER_CHUNK) { continue } 

                basePos :[3]u32 = [3]u32 { u32(cube.pos.x), u32(cube.pos.z), u32(cube.pos.y) } + sceneOffset * count;
                putVoxel(sv, basePos, 1)
            }
        }
    }
}

putPrism :: proc(sv: ^SparseVoxels, from: [3]u32, to: [3]u32) {
    for x:u32 = from.x; x < to.x; x += 1 {
        for y:u32 = from.y; y < to.y; y += 1 {
            for z:u32 = from.z; z < to.z; z += 1 {
                putVoxel(sv, {x,y,z}, 1)
            }
        }
    }
}

test_scene_01:: proc(sv: ^SparseVoxels) {
    for x:f64 = 0; x < CHUNK_W*INNER_CHUNK; x += 1 {
        for z:f64 = 0; z < CHUNK_W*INNER_CHUNK; z += 1 {
            res := noise.noise_2d(34502783, {x / 512,z / 512})
            putVoxel(sv, { u32(x), u32(64*res), u32(z) }, 1)
            //putVoxel(sv, { u32(x), u32(32*(0.75 + res)), u32(z) }, 1)
            //putVoxel(sv, { u32(x), 0, u32(z) }, 1)
        }
    }
    // for x:f64 = 0; x < CHUNK_W*INNER_CHUNK; x += 1 {
    //     for z:f64 = 0; z < CHUNK_W*INNER_CHUNK; z += 1 {
    //         res := noise.noise_2d(34502783, {x / 512,z / 512})
    //         // putVoxel(sv, { u32(x), u32(64*res), u32(z) }, 1)
    //         putVoxel(sv, { u32(x), u32(0.1*CHUNK_H*(0.75 + res)), u32(z) }, 1)
    //     }
    // }

    // d:u32 = 128
    // for y:u32 = 0; y < 32; y +=1 {
    //     putVoxel(sv, {d,y,d}, 1)
    //     putVoxel(sv, {d,y,d+1}, 1)
    //     putVoxel(sv, {d,y,d+2}, 1)
    //     putVoxel(sv, {d,y,d+3}, 1)
    //     putVoxel(sv, {d,y,d+4}, 1)
    // }

    // d = 150
    // for y:u32 = 0; y < 32; y +=1 {
    //     putVoxel(sv, {d,y,d}, 1)
    //     putVoxel(sv, {d+1,y,d}, 1)
    //     putVoxel(sv, {d+2,y,d}, 1)
    //     putVoxel(sv, {d+3,y,d}, 1)
    //     putVoxel(sv, {d+4,y,d}, 1)
    // }

    load_model(sv, {100,0,512})
    load_model_2(sv, {450,0,100})
    load_tree(sv, {565, 1, 400})
}

load_model :: proc(sv: ^SparseVoxels, offset:[3]u32) {
    if v, ok := vox.load_from_file("./assets/tower.vox", context.temp_allocator); ok {
        scene := v.models[0]
        for cube in scene.voxels {
            // if(cube.pos.y >= CHUNK_H*INNER_CHUNK) { continue } 

            basePos :[3]u32 = [3]u32 { u32(cube.pos.x), u32(cube.pos.z), u32(cube.pos.y) } + offset;
            putVoxel(sv, basePos, 1)
        }
    }
}

load_tree :: proc(sv: ^SparseVoxels, offset:[3]u32) {
    if v, ok := vox.load_from_file("./assets/tree.vox", context.temp_allocator); ok {
        scene := v.models[0]
        for cube in scene.voxels {
            // if(cube.pos.y >= CHUNK_H*INNER_CHUNK) { continue } 

            basePos :[3]u32 = [3]u32 { u32(cube.pos.x), u32(cube.pos.z), u32(cube.pos.y) } + offset;
            putVoxel(sv, basePos, 1)
        }
    }
}

load_window :: proc(sv: ^SparseVoxels, offset:[3]u32) {
    if v, ok := vox.load_from_file("./assets/window.vox", context.temp_allocator); ok {
        scene := v.models[0]
        for cube in scene.voxels {
            // if(cube.pos.y >= CHUNK_H*INNER_CHUNK) { continue } 

            basePos :[3]u32 = [3]u32 { u32(cube.pos.x), u32(cube.pos.z), u32(cube.pos.y) } + offset;
            putVoxel(sv, basePos, 1)
        }
    }
}



load_model_2 :: proc(sv: ^SparseVoxels, offset:[3]u32) {
    if v, ok := vox.load_from_file("./assets/scene_2.vox", context.temp_allocator); ok {
        scene := v.models[0]
        for cube in scene.voxels {
            if(cube.pos.y >= 240) { continue } 

            basePos :[3]u32 = [3]u32 { u32(cube.pos.y), u32(cube.pos.z), u32(cube.pos.x) } + offset;
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