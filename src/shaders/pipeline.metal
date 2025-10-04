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

[[mesh]]
void meshMain(
    Mesh outMesh,
    device const Camera_Data&   camera_data   [[buffer(0)]],
    uint tid [[thread_index_in_threadgroup]],
    uint gid [[threadgroup_position_in_grid]]
) {
    Vertex vertices[8];
    outMesh.set_primitive_count(12);

    float starting = float(gid)*1.2;
    float width = 0.5;

    vertices[0].PositionCS = camera_data.transform * float4(starting-width, width, -width, 1.0);
    vertices[0].Color = float4(0.2, 0.5, 0.2, 1.0);

    vertices[1].PositionCS = camera_data.transform * float4(starting-width, -width, -width, 1.0);
    vertices[1].Color = float4(0.6, 0.5, 0.4, 1.0);

    vertices[2].PositionCS = camera_data.transform * float4(starting+width, -width, -width, 1.0);
    vertices[2].Color = float4(0.0, 0.0, 1.0, 1.0);

    vertices[3].PositionCS = camera_data.transform * float4(starting+width, width, -width, 1.0);
    vertices[3].Color = float4(1.0, 0.0, 0.1, 1.0);

    vertices[4].PositionCS = camera_data.transform * float4(starting-width, width, width, 1.0);
    vertices[4].Color = float4(0.6, 0.0, 0.2, 1.0);

    vertices[5].PositionCS = camera_data.transform * float4(starting-width, -width, width, 1.0);
    vertices[5].Color = float4(0.0, 0.0, 0.4, 1.0);

    vertices[6].PositionCS = camera_data.transform * float4(starting+width, -width, width, 1.0);
    vertices[6].Color = float4(0.2, 0.0, 0.2, 1.0);

    vertices[7].PositionCS = camera_data.transform * float4(starting+width, width, width, 1.0);
    vertices[7].Color = float4(0.0, 1.0, 0.0, 1.0);

    outMesh.set_vertex(0, vertices[0]);
    outMesh.set_vertex(1, vertices[1]);
    outMesh.set_vertex(2, vertices[2]);
    outMesh.set_vertex(3, vertices[3]);
    outMesh.set_vertex(4, vertices[4]);
    outMesh.set_vertex(5, vertices[5]);
    outMesh.set_vertex(6, vertices[6]);
    outMesh.set_vertex(7, vertices[7]);

    // Back
    outMesh.set_index(0, 0);
    outMesh.set_index(1, 1);
    outMesh.set_index(2, 2);

    outMesh.set_index(3, 0);
    outMesh.set_index(4, 2);
    outMesh.set_index(5, 3);

    // Right
    outMesh.set_index(6, 7);
    outMesh.set_index(7, 3);
    outMesh.set_index(8, 2);

    outMesh.set_index( 9, 6);
    outMesh.set_index(10, 7);
    outMesh.set_index(11, 2);

    // Front
    outMesh.set_index(12, 5);
    outMesh.set_index(13, 7);
    outMesh.set_index(14, 6);

    outMesh.set_index(15, 5);
    outMesh.set_index(16, 4);
    outMesh.set_index(17, 7);

    // Bottom
    outMesh.set_index(18, 5);
    outMesh.set_index(19, 6);
    outMesh.set_index(20, 2);

    outMesh.set_index(21, 5);
    outMesh.set_index(22, 2);
    outMesh.set_index(23, 1);

    // Left
    outMesh.set_index(24, 0);
    outMesh.set_index(25, 4);
    outMesh.set_index(26, 1);

    outMesh.set_index(27, 4);
    outMesh.set_index(28, 5);
    outMesh.set_index(29, 1);

    // Top
    outMesh.set_index(30, 7);
    outMesh.set_index(31, 0);
    outMesh.set_index(32, 3);

    outMesh.set_index(33, 4);
    outMesh.set_index(34, 0);
    outMesh.set_index(35, 7);
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