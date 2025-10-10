#include <metal_stdlib>
using namespace metal;

#define STACK_SIZE 1
#define CHUNKS_MAX 32
#define CHUNK_SIZE 32
#define CONCURRENT_CHUNKS_MAX 128

struct Vertex {
    float4 PositionCS [[position]];
};

struct TriangleOut {
    float3 Normal [[flat]];
    float3 Color [[flat]];
};

struct Camera_Data {
    float4x4 transform;
    float4 pos;
    float4 look;
};

struct ChunkHeader {
    ushort tag;
    ushort material;
    ushort idx;
};

struct Voxels_Data {
    uchar chunkCount;
    uchar tags[CHUNKS_MAX][CHUNKS_MAX][CHUNKS_MAX];
    uchar materials[CHUNKS_MAX][CHUNKS_MAX][CHUNKS_MAX];
    uchar idxs[CHUNKS_MAX][CHUNKS_MAX][CHUNKS_MAX];
    uchar chunks[CONCURRENT_CHUNKS_MAX][CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE];
};

struct Payload {
    uint ox;
    uint oy;
    uint oz;
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
    uint max_pidx = idx * (12/2) + 6;

    float4 pos = float4(float(upos.x), float(upos.y), float(upos.z), 0.0);

    bool has_left_neightbour = get_voxel(voxels_data, uint3(upos.x-1,upos.y,upos.z)) > 0;
    bool has_right_neightbour = get_voxel(voxels_data, uint3(upos.x+1,upos.y,upos.z)) > 0;
    bool has_top_neightbour = get_voxel(voxels_data, uint3(upos.x,upos.y+1, upos.z)) > 0;
    bool has_back_neightbour = get_voxel(voxels_data, uint3(upos.x,upos.y, upos.z-1)) > 0;
    bool has_front_neightbour = get_voxel(voxels_data, uint3(upos.x,upos.y, upos.z+1)) > 0;
    bool has_bottom_neightbour = get_voxel(voxels_data, uint3(upos.x,upos.y-1,upos.z)) > 0;

    bool has_back_top_neightbour = get_voxel(voxels_data, uint3(upos.x,upos.y + 1,upos.z - 1)) > 0;
    bool has_front_top_neightbour = get_voxel(voxels_data, uint3(upos.x,upos.y+1,upos.z+1)) > 0;
    

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

    
    if(!has_back_neightbour && pos.z > camera_data.pos.z ) {
        // Back
        float4 normal = float4(0.0, 0.0, -1.0, 0.0);
        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 1);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Normal = normal.rgb;
        quads[pidx].Color = tone.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 2);
        outMesh.set_index(midx++, vidx + 3);
        quads[pidx].Normal = normal.rgb;
        quads[pidx].Color = tone.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        
    }
    
    if(!has_right_neightbour && camera_data.pos.x > pos.x ) {
        // Right
        float4 normal = float4(1.0, 0.0, 0.0, 0.0);

        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 3);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Normal = normal.rgb;
        quads[pidx].Color = tone.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 6);
        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Normal = normal.rgb;
        quads[pidx].Color = tone.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        
    }

    if(!has_front_neightbour && camera_data.pos.z > pos.z) {
        // Front
        float4 normal = float4(0.0, 0.0, 1.0, 0.0);

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 6);
        quads[pidx].Normal = normal.rgb;
        quads[pidx].Color = tone.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 7);
        quads[pidx].Normal = normal.rgb;
        quads[pidx].Color = tone.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        
    }

    if(!has_bottom_neightbour && pos.y > camera_data.pos.y && midx < max_midx) {
        // Bottom
        float4 normal = float4(0.0, -1.0, 0.0, 0.0);

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 6);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Normal = normal.rgb;
        quads[pidx].Color = tone.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 2);
        outMesh.set_index(midx++, vidx + 1);
        quads[pidx].Normal = normal.rgb;
        quads[pidx].Color = tone.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
    }

    if(!has_left_neightbour && pos.x > camera_data.pos.x && midx < max_midx) {
        // Left
        float4 normal = float4(-1.0, 0.0, 0.0, 0.0);

        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 1);
        quads[pidx].Normal = normal.rgb;
        quads[pidx].Color = tone.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 1);
        quads[pidx].Normal = normal.rgb;
        quads[pidx].Color = tone.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        
    }

    if(!has_top_neightbour && pos.y < camera_data.pos.y && midx < max_midx - 5) {
        // Top
        float4 normal = float4(0.0, 1.0, 0.0, 0.0);

        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 3);
        quads[pidx].Normal = normal.rgb;
        quads[pidx].Color = tone.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 7);
        quads[pidx].Normal = normal.rgb;
        quads[pidx].Color = tone.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
           
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
            if (gtid == 0) {
                outGrid.set_threadgroups_per_grid(uint3(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE));
            }
        }
    }
    
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

    if (threadIndex.x == 0) {
        outMesh.set_primitive_count(6);
    }
    
    uint x = payload.ox;
    uint y = payload.oy;
    uint z =  payload.oz;
    float w = 0.5;

    uint3 pos;
    pos = uint3(x,y,z)*CHUNK_SIZE + chunkPos;
    float vision_cone = dot(normalize(float3(pos) - camera_data.pos.xyz), normalize(camera_data.look.xyz));
    if(vision_cone > 0.1 && get_voxel(voxels_data, pos) > 0) {
        float4 c = float4(float3(chunkPos) / CHUNK_SIZE, 0.0);
        pushCube(outMesh, pos, camera_data, w, 0, c, voxels_data);
    }
}

struct FSInput
{
    Vertex vtx;
    TriangleOut tri;
};

[[fragment]]
float4 fragmentMain(FSInput input [[stage_in]])
{
    float3 color = float3(0.1) + input.tri.Color * 0.9;
    return float4(color, 1.0);
}