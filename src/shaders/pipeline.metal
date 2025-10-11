#include <metal_stdlib>
using namespace metal;

#define STACK_SIZE 8
#define CHUNKS_MAX 64
#define CHUNK_SIZE 16
#define CONCURRENT_CHUNKS_MAX 1024

struct Vertex {
    float4 PositionCS [[position]];
};

struct TriangleOut {
    float3 Color [[flat]];
};

struct Camera_Data {
    float4x4 transform;
    float4 pos;
    float4 look;
    float4 sun;
};

struct ChunkHeader {
    ushort tag;
    ushort material;
    ushort idx;
};

struct Voxels_Data {
    ushort chunkCount;
    uchar tags[CHUNKS_MAX][CHUNKS_MAX][CHUNKS_MAX];
    uchar materials[CHUNKS_MAX][CHUNKS_MAX][CHUNKS_MAX];
    ushort idxs[CHUNKS_MAX][CHUNKS_MAX][CHUNKS_MAX];
    uchar chunks[CONCURRENT_CHUNKS_MAX][CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE];
};

struct Payload {
    uint ox;
    uint oy;
    uint oz;
    ushort chunkId;
};

using Voxel = metal::mesh<Vertex, TriangleOut, 8*STACK_SIZE, 6*STACK_SIZE, topology::triangle>;

// For now it's a direct access but later on we want to replace this with an Octree acceleration structure
uchar get_voxel(constant Voxels_Data*  voxels_data, uint3 upos) {
    // The swapped palces between z and y is on purpose
    uint3 idx_pos = upos / CHUNK_SIZE;
    uint3 inside_chunk_pos = upos % CHUNK_SIZE;

    uint chunk_idx = voxels_data->idxs[idx_pos.x][idx_pos.y][idx_pos.z];
    return voxels_data->chunks[chunk_idx][inside_chunk_pos.x][inside_chunk_pos.y][inside_chunk_pos.z];
}

uint pushCube(
    Voxel outMesh, 
    uint3 upos, 
    constant Camera_Data&   camera_data,
    float w, uint idx, 
    float4 tone,
    constant Voxels_Data* voxels_data
) {
    uint triangle_count = 0;

    Vertex vertices[8];
    TriangleOut quads[6];
    uint vidx = idx * 8;
    uint midx = idx * 18;
    uint pidx = idx * 6;

    uint max_midx = idx * (36/2) + 18;
    uint max_pidx = idx * 6 + 6;

    float4 pos = float4(float(upos.x), float(upos.y), float(upos.z), 0.0);

    bool has_left_neightbour = pos.x - w <= camera_data.pos.x  || get_voxel(voxels_data, uint3(upos.x-1,upos.y,upos.z)) > 0;
    bool has_right_neightbour = camera_data.pos.x <= pos.x + w || get_voxel(voxels_data, uint3(upos.x+1,upos.y,upos.z)) > 0;
    bool has_top_neightbour = pos.y >= camera_data.pos.y       || get_voxel(voxels_data, uint3(upos.x,upos.y+1, upos.z)) > 0;
    bool has_back_neightbour = pos.z - w <= camera_data.pos.z  || get_voxel(voxels_data, uint3(upos.x,upos.y, upos.z-1)) > 0;
    bool has_front_neightbour = camera_data.pos.z <= pos.z + w || get_voxel(voxels_data, uint3(upos.x,upos.y, upos.z+1)) > 0;
    bool has_bottom_neightbour = pos.y -w < camera_data.pos.y  || get_voxel(voxels_data, uint3(upos.x,upos.y-1,upos.z)) > 0;

    //bool has_back_top_neightbour = get_voxel(voxels_data, uint3(upos.x,upos.y + 1,upos.z - 1)) > 0;
    //bool has_front_top_neightbour = get_voxel(voxels_data, uint3(upos.x,upos.y+1,upos.z+1)) > 0;
    

    vertices[0].PositionCS = camera_data.transform * (pos + float4(-w, w, -w, 1.0));
    vertices[1].PositionCS = camera_data.transform * (pos + float4(-w, -w, -w, 1.0));
    vertices[2].PositionCS = camera_data.transform * (pos + float4(+w, -w, -w, 1.0));
    vertices[3].PositionCS = camera_data.transform * (pos + float4(+w, w, -w, 1.0));
    vertices[4].PositionCS = camera_data.transform * (pos + float4(-w, w, w, 1.0));
    vertices[5].PositionCS = camera_data.transform * (pos + float4(-w, -w, w, 1.0));
    vertices[6].PositionCS = camera_data.transform * (pos + float4(+w, -w, w, 1.0));
    vertices[7].PositionCS = camera_data.transform * (pos + float4(+w, w, w, 1.0));

    outMesh.set_vertex(vidx + 0, vertices[0]);
    outMesh.set_vertex(vidx + 1, vertices[1]);
    outMesh.set_vertex(vidx + 2, vertices[2]);
    outMesh.set_vertex(vidx + 3, vertices[3]);

    outMesh.set_vertex(vidx + 4, vertices[4]);
    outMesh.set_vertex(vidx + 5, vertices[5]);
    outMesh.set_vertex(vidx + 6, vertices[6]);
    outMesh.set_vertex(vidx + 7, vertices[7]);

    float3 sunAngle = normalize(camera_data.sun.xyz);
    if(!has_back_neightbour) {
        // Back
        float4 normal = float4(0.0, 0.0, -1.0, 0.0);
        float3 t = float3((1.0 + dot(sunAngle, normal.rgb)) * 0.2);

        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 1);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Color = tone.rgb + t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 2);
        outMesh.set_index(midx++, vidx + 3);
        quads[pidx].Color = tone.rgb + t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }
    
    if(!has_right_neightbour ) {
        // Right
        float4 normal = float4(1.0, 0.0, 0.0, 0.0);
        float3 t = float3((1.0 + dot(sunAngle, normal.rgb)) * 0.2);

        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 3);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Color = tone.rgb + t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 6);
        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Color = tone.rgb + t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_front_neightbour) {
        // Front
        float4 normal = float4(0.0, 0.0, 1.0, 0.0);
        float3 t = float3((1.0 + dot(sunAngle, normal.rgb)) * 0.2);

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 6);
        quads[pidx].Color = tone.rgb + t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 7);
        quads[pidx].Color = tone.rgb + t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_bottom_neightbour && midx < max_midx) {
        // Bottom
        float4 normal = float4(0.0, -1.0, 0.0, 0.0);
        float3 t = float3((1.0 + dot(sunAngle, normal.rgb)) * 0.2);

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 6);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Color = tone.rgb + t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 2);
        outMesh.set_index(midx++, vidx + 1);
        quads[pidx].Color = tone.rgb + t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_left_neightbour && midx < max_midx) {
        // Left
        float4 normal = float4(-1.0, 0.0, 0.0, 0.0);
        float3 t = float3((0.5 + dot(sunAngle, normal.rgb)) * 0.2);

        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 1);
        quads[pidx].Color = tone.rgb + t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 1);
        quads[pidx].Color = tone.rgb + t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_top_neightbour && midx < max_midx) {
        // Top
        float4 normal = float4(0.0, 1.0, 0.0, 0.0);
        float3 t = float3((1.0 + dot(sunAngle, normal.rgb)) * 0.2);

        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 3);
        quads[pidx].Color = tone.rgb + t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 7);
        quads[pidx].Color = tone.rgb + t;
        outMesh.set_primitive(pidx, quads[pidx]);
        triangle_count += 2;   
    }

    return triangle_count;
}

[[object]]
void objectMain(
    uint3 objectIndex                      [[threadgroup_position_in_grid]],
    uint gtid                             [[thread_position_in_threadgroup]],
    uint width                            [[threads_per_threadgroup]],
    constant Camera_Data&   camera_data   [[buffer(0)]],
    constant Voxels_Data*   voxels_data   [[buffer(1)]],
    object_data Payload& outPayload       [[payload]],
    mesh_grid_properties outGrid)
{
    
    float vision_cone = dot(normalize(float3(objectIndex * CHUNK_SIZE) - camera_data.pos.xyz), normalize(camera_data.look.xyz));
    if(vision_cone > 0.0 || (distance(float3(objectIndex)*CHUNK_SIZE + float3(CHUNK_SIZE/2), camera_data.pos.xyz) < CHUNK_SIZE)) {
        if(voxels_data->tags[objectIndex.x][objectIndex.y][objectIndex.z] == 2) {
            outPayload.ox = objectIndex.x;
            outPayload.oy = objectIndex.y;
            outPayload.oz = objectIndex.z;
            outPayload.chunkId = voxels_data->idxs[objectIndex.x][objectIndex.y][objectIndex.z];
            if (gtid == 0) {
                outGrid.set_threadgroups_per_grid(uint3(CHUNK_SIZE/2, CHUNK_SIZE/2, CHUNK_SIZE/2) );
            }
        }
    }
}

uint processVoxel(
    Voxel outMesh, 
    uint3 pos, 
    constant Camera_Data&   camera_data,
    uint idx, 
    constant Voxels_Data* voxels_data
) {
    float3 fpos = float3(pos);
    float vision_cone = dot(normalize(fpos - camera_data.pos.xyz), normalize(camera_data.look.xyz));

    uint primitiveCount = 0;
    if(vision_cone > 0.1) {
        //idx = 1;
        //uint actualIdx = simd_prefix_exclusive_sum(idx);
        float4 c = float4(float3(0.0), 1.0);
        primitiveCount += pushCube(outMesh, pos, camera_data, 0.5, idx, c, voxels_data);
    }

    return primitiveCount;
}

[[mesh]]
void meshMain(
    Voxel outMesh,
    constant Camera_Data&   camera_data   [[buffer(0)]],
    constant Voxels_Data*   voxels_data   [[buffer(1)]],
    object_data const Payload& payload    [[payload]],
    uint3 chunkPos                        [[threadgroup_position_in_grid]],
    uint3 threadIndex                     [[thread_position_in_threadgroup]],
    uint3 tid                             [[thread_position_in_grid]],
    uint width                            [[threadgroups_per_grid]]
) {
    uint x = payload.ox;
    uint y = payload.oy;
    uint z =  payload.oz;
    float w = 0.5;
    uint primitiveCount = 0;

    if (threadIndex.x == 0) {
        // TODO: this amount can be optimized, since in reality we will always have at most half of this
        // but since we only know after processing, it's hard (?) to get the correct mesh ID without serializing threads.
        outMesh.set_primitive_count(6*STACK_SIZE);
    }
    uint3 insidePos = threadIndex + chunkPos*2;

    if(voxels_data->chunks[payload.chunkId][insidePos.x][insidePos.y][insidePos.z] > 0) {
        uint3 pos = uint3(x,y,z)*CHUNK_SIZE + insidePos;
        uint idx = threadIndex.x + threadIndex.y*2 + threadIndex.z*4;
        primitiveCount += processVoxel(
            outMesh, pos, camera_data, idx, voxels_data
        );
    }
    //uint totalPrimitives = simd_sum(primitiveCount);
}

struct FSInput
{
    Vertex vtx;
    TriangleOut tri;
};

[[fragment]]
float4 fragmentMain(
    FSInput input [[stage_in]]
) {
    float3 color = mix(0.0, 2.0, input.tri.Color.r);
    float3 result = mix(0.0, 0.1, input.vtx.PositionCS.w - 0.5); 
    float3 c2 = mix(float3(0.1, 0.17, 0.35), float3(1.0, 0.71, 0.73), color.r);
    return float4(c2.r, c2.g, c2.b, 1.0);
}