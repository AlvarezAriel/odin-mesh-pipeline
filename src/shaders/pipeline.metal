#include <metal_stdlib>
    using namespace metal;

    struct Vertex {
        float4 PositionCS [[position]];
        float3 Color;
    };

    using Mesh = metal::mesh<Vertex, void, 3, 1, topology::triangle>;

    [[mesh]]
    void meshMain(Mesh outMesh)
    {
        outMesh.set_primitive_count(3);

        Vertex vertices[3];

        vertices[0].PositionCS = float4(-0.5, 0.5, 0.0, 1.0);
        vertices[0].Color = float3(1.0, 0.0, 0.0);

        vertices[1].PositionCS = float4(0.5, 0.5, 0.0, 1.0);
        vertices[1].Color = float3(0.0, 1.0, 0.0);

        vertices[2].PositionCS = float4(0.0, -0.5, 0.0, 1.0);
        vertices[2].Color = float3(0.0, 0.0, 1.0);

        outMesh.set_vertex(0, vertices[0]);
        outMesh.set_vertex(1, vertices[1]);
        outMesh.set_vertex(2, vertices[2]);

        outMesh.set_index(0, 0);
        outMesh.set_index(1, 1);
        outMesh.set_index(2, 2);
    }

    struct FSInput
    {
        Vertex vtx;
    };

    [[fragment]]
    float4 fragmentMain(FSInput input [[stage_in]])
    {
        return float4(input.vtx.Color, 1.0);
    }