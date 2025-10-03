#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float4 PositionCS [[position]];
    float Color;
};

struct Camera_Data {
    float4x4 transform;
};

using Mesh = metal::mesh<Vertex, void, 4, 2, topology::triangle>;

[[mesh]]
void meshMain(
    Mesh outMesh,
    device const Camera_Data&   camera_data   [[buffer(0)]],
    uint tid [[thread_index_in_threadgroup]],
    uint gid [[threadgroup_position_in_grid]]
) {
    outMesh.set_primitive_count(4);

    float starting = float(gid) / 2.0;
    float width = 0.5;
    Vertex vertices[4];

    float c = 0.3;
    if(gid % 2 == 0) {
        c = 1.0;
    }

    vertices[0].PositionCS = camera_data.transform * float4(starting-width, 0.5, 0.0, 1.0);
    vertices[0].Color = c;

    vertices[1].PositionCS = camera_data.transform * float4(starting-width, -0.5, 0.0, 1.0);
    vertices[1].Color = c;

    vertices[2].PositionCS = camera_data.transform * float4(starting+width, -0.5, 0.0, 1.0);
    vertices[2].Color = c;

    vertices[3].PositionCS = camera_data.transform * float4(starting+width, 0.5, 0.0, 1.0);
    vertices[3].Color = c;

    outMesh.set_vertex(0, vertices[0]);
    outMesh.set_vertex(1, vertices[1]);
    outMesh.set_vertex(2, vertices[2]);
    outMesh.set_vertex(3, vertices[3]);

    outMesh.set_index(0, 0);
    outMesh.set_index(1, 1);
    outMesh.set_index(2, 2);

    outMesh.set_index(3, 0);
    outMesh.set_index(4, 2);
    outMesh.set_index(5, 3);
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