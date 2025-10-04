#include <metal_stdlib>
using namespace metal;

#define AS_GROUP_SIZE 1024

struct Vertex {
    float4 PositionCS [[position]];
    float Color;
};

struct Camera_Data {
    float4x4 transform;
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
    outGrid.set_threadgroups_per_grid(uint3(AS_GROUP_SIZE, 1, 1));
}


using Voxel = metal::mesh<Vertex, void, 8*2, 12*2, topology::triangle>;

void pushCube(Voxel outMesh, float4 pos, Camera_Data camera_data, float w, uint idx) {
    Vertex vertices[8];
    uint vidx = idx * 8;

    vertices[0].PositionCS = camera_data.transform * (pos + float4(-w, w, -w, 1.0));
    vertices[0].Color = 0.5;

    vertices[1].PositionCS = camera_data.transform * (pos + float4(-w, -w, -w, 1.0));
    vertices[1].Color =  0.5;

    vertices[2].PositionCS = camera_data.transform * (pos + float4(+w, -w, -w, 1.0));
    vertices[2].Color =  0.5;

    vertices[3].PositionCS = camera_data.transform * (pos + float4(+w, w, -w, 1.0));
    vertices[3].Color =  0.5;

    vertices[4].PositionCS = camera_data.transform * (pos + float4(-w, w, w, 1.0));
    vertices[4].Color =  0.5;

    vertices[5].PositionCS = camera_data.transform * (pos + float4(-w, -w, w, 1.0));
    vertices[5].Color =  0.5;

    vertices[6].PositionCS = camera_data.transform * (pos + float4(+w, -w, w, 1.0));
    vertices[6].Color =  0.5;

    vertices[7].PositionCS = camera_data.transform * (pos + float4(+w, w, w, 1.0));
    vertices[7].Color =  0.5;

    outMesh.set_vertex(vidx + 0, vertices[0]);
    outMesh.set_vertex(vidx + 1, vertices[1]);
    outMesh.set_vertex(vidx + 2, vertices[2]);
    outMesh.set_vertex(vidx + 3, vertices[3]);
    outMesh.set_vertex(vidx + 4, vertices[4]);
    outMesh.set_vertex(vidx + 5, vertices[5]);
    outMesh.set_vertex(vidx + 6, vertices[6]);
    outMesh.set_vertex(vidx + 7, vertices[7]);

    uint midx = idx * 36;
    // Back
    outMesh.set_index(midx+0, vidx + 0);
    outMesh.set_index(midx+1, vidx + 1);
    outMesh.set_index(midx+2, vidx + 2);

    outMesh.set_index(midx+3, vidx + 0);
    outMesh.set_index(midx+4, vidx + 2);
    outMesh.set_index(midx+5, vidx + 3);

    // Right
    outMesh.set_index(midx+6, vidx + 7);
    outMesh.set_index(midx+7, vidx + 3);
    outMesh.set_index(midx+8, vidx + 2);

    outMesh.set_index(midx+ 9, vidx + 6);
    outMesh.set_index(midx+10, vidx + 7);
    outMesh.set_index(midx+11, vidx + 2);

    // Front
    outMesh.set_index(midx+12, vidx + 5);
    outMesh.set_index(midx+13, vidx + 7);
    outMesh.set_index(midx+14, vidx + 6);

    outMesh.set_index(midx+15, vidx + 5);
    outMesh.set_index(midx+16, vidx + 4);
    outMesh.set_index(midx+17, vidx + 7);

    // Bottom
    outMesh.set_index(midx+18, vidx + 5);
    outMesh.set_index(midx+19, vidx + 6);
    outMesh.set_index(midx+20, vidx + 2);

    outMesh.set_index(midx+21, vidx + 5);
    outMesh.set_index(midx+22, vidx + 2);
    outMesh.set_index(midx+23, vidx + 1);

    // Left
    outMesh.set_index(midx+24, vidx + 0);
    outMesh.set_index(midx+25, vidx + 4);
    outMesh.set_index(midx+26, vidx + 1);

    outMesh.set_index(midx+27, vidx + 4);
    outMesh.set_index(midx+28, vidx + 5);
    outMesh.set_index(midx+29, vidx + 1);

    // Top
    outMesh.set_index(midx+30, vidx + 7);
    outMesh.set_index(midx+31, vidx + 0);
    outMesh.set_index(midx+32, vidx + 3);

    outMesh.set_index(midx+33, vidx + 4);
    outMesh.set_index(midx+34, vidx + 0);
    outMesh.set_index(midx+35, vidx + 7);
}


[[mesh]]
void meshMain(
    Voxel outMesh,
    device const Camera_Data&   camera_data   [[buffer(0)]],
    object_data const Payload& payload [[payload]],
    uint tid [[thread_index_in_threadgroup]],
    uint gid [[threadgroup_position_in_grid]]
) {
    
    outMesh.set_primitive_count(12*2);
    

    float starting = float(payload.MeshletIndices[gid] / AS_GROUP_SIZE);
    float w = 0.5;

    float4 pos;
    pos = float4(starting, 0.0, float(gid), 0.0);
    pushCube(outMesh, pos, camera_data, w, 0);

    pos = float4(starting, 1.0, float(gid), 0.0);
    pushCube(outMesh, pos, camera_data, w, 1);
}


struct FSInput
{
    Vertex vtx;
};

[[fragment]]
float4 fragmentMain(FSInput input [[stage_in]])
{
    return float4(float3(input.vtx.Color), 1.0);
}