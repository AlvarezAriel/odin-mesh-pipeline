#include <metal_stdlib>
using namespace metal;

#define AS_GROUP_SIZE 128
#define STACK_SIZE 32

struct Vertex {
    float4 PositionCS [[position]];
    float4 Color;
};

struct Camera_Data {
    float4x4 transform;
};

struct Voxels_Data {
    float cell[128][128][64];
};


struct Payload {
    uint MeshletIndices[AS_GROUP_SIZE];
};

[[object]]
void objectMain(
    uint                 gtid       [[thread_position_in_threadgroup]],
    uint                 dtid       [[thread_position_in_grid]],
    object_data Payload& outPayload [[payload]],
    mesh_grid_properties outGrid)
{
    outPayload.MeshletIndices[gtid] = dtid;
    // Assumes all meshlets are visible
    // TODO: culling
    outGrid.set_threadgroups_per_grid(uint3(AS_GROUP_SIZE, 1, 1));
}


using Voxel = metal::mesh<Vertex, void, 8*STACK_SIZE, 12*STACK_SIZE, topology::triangle>;

uint pushCube(
    Voxel outMesh, 
    uint3 upos, 
    Camera_Data camera_data, 
    float w, uint idx, 
    float4 tone,
    constant Voxels_Data* voxels_data
) {
    uint triangle_count = 0;

    Vertex vertices[8];
    uint vidx = idx * 8;

    float4 pos = float4(float(upos.x), float(upos.y), float(upos.z), 0.0);

    vertices[0].PositionCS = camera_data.transform * (pos + float4(-w, w, -w, 1.0));
    vertices[0].Color = tone;

    vertices[1].PositionCS = camera_data.transform * (pos + float4(-w, -w, -w, 1.0));
    vertices[1].Color =  tone;

    vertices[2].PositionCS = camera_data.transform * (pos + float4(+w, -w, -w, 1.0));
    vertices[2].Color =  tone;

    vertices[3].PositionCS = camera_data.transform * (pos + float4(+w, w, -w, 1.0));
    vertices[3].Color =  tone;

    vertices[4].PositionCS = camera_data.transform * (pos + float4(-w, w, w, 1.0));
    vertices[4].Color =  tone;

    vertices[5].PositionCS = camera_data.transform * (pos + float4(-w, -w, w, 1.0));
    vertices[5].Color =  tone;

    vertices[6].PositionCS = camera_data.transform * (pos + float4(+w, -w, w, 1.0));
    vertices[6].Color =  tone;

    vertices[7].PositionCS = camera_data.transform * (pos + float4(+w, w, w, 1.0));
    vertices[7].Color =  tone;

    outMesh.set_vertex(vidx + 0, vertices[0]);
    outMesh.set_vertex(vidx + 1, vertices[1]);
    outMesh.set_vertex(vidx + 2, vertices[2]);
    outMesh.set_vertex(vidx + 3, vertices[3]);
    outMesh.set_vertex(vidx + 4, vertices[4]);
    outMesh.set_vertex(vidx + 5, vertices[5]);
    outMesh.set_vertex(vidx + 6, vertices[6]);
    outMesh.set_vertex(vidx + 7, vertices[7]);

    uint midx = idx * 36;

    bool has_back_neightbour = voxels_data->cell[upos.x][upos.z-1][upos.y] > 0.0;
    if(!has_back_neightbour) {
        // Back
        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 1);
        outMesh.set_index(midx++, vidx + 2);

        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 2);
        outMesh.set_index(midx++, vidx + 3);

        triangle_count += 2;
    }
    
    bool has_right_neightbour = voxels_data->cell[upos.x+1][upos.z][upos.y] > 0.0;
    if(!has_right_neightbour) {
        // Right
        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 3);
        outMesh.set_index(midx++, vidx + 2);

        outMesh.set_index(midx++, vidx + 6);
        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 2);

        triangle_count += 2;
    }

    bool has_front_neightbour = voxels_data->cell[upos.x][upos.z+1][upos.y] > 0.0;
    if(!has_front_neightbour) {
        // Front
        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 6);

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 7);

        triangle_count += 2;
    }

    bool has_bottom_neightbour = voxels_data->cell[upos.x][upos.z][upos.y-1] > 0.0;
    if(!has_bottom_neightbour) {
        // Bottom
        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 6);
        outMesh.set_index(midx++, vidx + 2);

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 2);
        outMesh.set_index(midx++, vidx + 1);

        triangle_count += 2;
    }

    bool has_left_neightbour = voxels_data->cell[upos.x-1][upos.z][upos.y] > 0.0;
    if(!has_left_neightbour) {
        // Left
        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 1);

        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 1);

        triangle_count += 2;
    }

    bool has_top_neightbour = voxels_data->cell[upos.x][upos.z][upos.y+1] > 0.0;
    if(!has_top_neightbour) {
        // Top
        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 3);

        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 7);

        triangle_count += 2;
    }

    return triangle_count;
}


[[mesh]]
void meshMain(
    Voxel outMesh,
    constant Camera_Data&   camera_data   [[buffer(0)]],
    constant Voxels_Data*   voxels_data   [[buffer(1)]],
    object_data const Payload& payload [[payload]],
    uint tid [[thread_index_in_threadgroup]],
    uint gid [[threadgroup_position_in_grid]]
) {
    
    outMesh.set_primitive_count(12*STACK_SIZE);

    uint x = payload.MeshletIndices[gid] / AS_GROUP_SIZE;
    uint z = gid;
    float w = 0.5;

    uint3 pos;
    uint triangle_count = 0;
    for(uint i = 0 ; i < STACK_SIZE; i++) {
        uint y = i;
        float color = voxels_data->cell[x][z][y];

        if(color > 0.0) {
            float4 c = float4(float3(0.2), 0.0);
            pos = uint3(x,y,z);
            triangle_count += pushCube(outMesh, pos, camera_data, w, i, c, voxels_data);
        }
    }
}


struct FSInput
{
    Vertex vtx;
};

[[fragment]]
float4 fragmentMain(FSInput input [[stage_in]])
{
    return float4(input.vtx.Color.rgb, 1.0);
}