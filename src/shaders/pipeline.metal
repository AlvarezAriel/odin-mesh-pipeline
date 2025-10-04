#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float4 PositionCS [[position]];
    float4 Color;
};

struct Camera_Data {
    float4x4 transform;
};

using Mesh = metal::mesh<Vertex, void, 8, 12, topology::triangle>;

void pushCube(Mesh outMesh, float4 pos, Camera_Data camera_data, float w, uint idx) {
    Vertex vertices[8];
    uint vidx = idx * 8;

    vertices[0].PositionCS = camera_data.transform * (pos + float4(-w, w, -w, 1.0));
    vertices[0].Color = float4(0.2, 0.5, 0.2, 1.0);

    vertices[1].PositionCS = camera_data.transform * (pos + float4(-w, -w, -w, 1.0));
    vertices[1].Color = float4(0.6, 0.5, 0.4, 1.0);

    vertices[2].PositionCS = camera_data.transform * (pos + float4(+w, -w, -w, 1.0));
    vertices[2].Color = float4(0.0, 0.0, 1.0, 1.0);

    vertices[3].PositionCS = camera_data.transform * (pos + float4(+w, w, -w, 1.0));
    vertices[3].Color = float4(1.0, 0.0, 0.1, 1.0);

    vertices[4].PositionCS = camera_data.transform * (pos + float4(-w, w, w, 1.0));
    vertices[4].Color = float4(0.6, 0.0, 0.2, 1.0);

    vertices[5].PositionCS = camera_data.transform * (pos + float4(-w, -w, w, 1.0));
    vertices[5].Color = float4(0.0, 0.0, 0.4, 1.0);

    vertices[6].PositionCS = camera_data.transform * (pos + float4(+w, -w, w, 1.0));
    vertices[6].Color = float4(0.2, 0.0, 0.2, 1.0);

    vertices[7].PositionCS = camera_data.transform * (pos + float4(+w, w, w, 1.0));
    vertices[7].Color = float4(0.0, 1.0, 0.0, 1.0);

    outMesh.set_vertex(vidx + 0, vertices[0]);
    outMesh.set_vertex(vidx + 1, vertices[1]);
    outMesh.set_vertex(vidx + 2, vertices[2]);
    outMesh.set_vertex(vidx + 3, vertices[3]);
    outMesh.set_vertex(vidx + 4, vertices[4]);
    outMesh.set_vertex(vidx + 5, vertices[5]);
    outMesh.set_vertex(vidx + 6, vertices[6]);
    outMesh.set_vertex(vidx + 7, vertices[7]);

    // Back
    outMesh.set_index(0, vidx + 0);
    outMesh.set_index(1, vidx + 1);
    outMesh.set_index(2, vidx + 2);

    outMesh.set_index(3, vidx + 0);
    outMesh.set_index(4, vidx + 2);
    outMesh.set_index(5, vidx + 3);

    // Right
    outMesh.set_index(6, vidx + 7);
    outMesh.set_index(7, vidx + 3);
    outMesh.set_index(8, vidx + 2);

    outMesh.set_index( 9, vidx + 6);
    outMesh.set_index(10, vidx + 7);
    outMesh.set_index(11, vidx + 2);

    // Front
    outMesh.set_index(12, vidx + 5);
    outMesh.set_index(13, vidx + 7);
    outMesh.set_index(14, vidx + 6);

    outMesh.set_index(15, vidx + 5);
    outMesh.set_index(16, vidx + 4);
    outMesh.set_index(17, vidx + 7);

    // Bottom
    outMesh.set_index(18, vidx + 5);
    outMesh.set_index(19, vidx + 6);
    outMesh.set_index(20, vidx + 2);

    outMesh.set_index(21, vidx + 5);
    outMesh.set_index(22, vidx + 2);
    outMesh.set_index(23, vidx + 1);

    // Left
    outMesh.set_index(24, vidx + 0);
    outMesh.set_index(25, vidx + 4);
    outMesh.set_index(26, vidx + 1);

    outMesh.set_index(27, vidx + 4);
    outMesh.set_index(28, vidx + 5);
    outMesh.set_index(29, vidx + 1);

    // Top
    outMesh.set_index(30, vidx + 7);
    outMesh.set_index(31, vidx + 0);
    outMesh.set_index(32, vidx + 3);

    outMesh.set_index(33, vidx + 4);
    outMesh.set_index(34, vidx + 0);
    outMesh.set_index(35, vidx + 7);
}


[[mesh]]
void meshMain(
    Mesh outMesh,
    device const Camera_Data&   camera_data   [[buffer(0)]],
    uint tid [[thread_index_in_threadgroup]],
    uint gid [[threadgroup_position_in_grid]]
) {
    
    outMesh.set_primitive_count(12);

    float starting = float(gid);
    float w = 0.5;

    float4 pos = float4(starting, 0.0, 0.0, 0.0);

    pushCube(outMesh, pos, camera_data, w, 0);
    
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