#include <metal_stdlib>
using namespace metal;

#define AS_GROUP_SIZE 32
#define STACK_SIZE 1

struct Vertex {
    float4 PositionCS [[position]];
};

struct TriangleOut {
    float3 Normal [[flat]];
};

struct Camera_Data {
    float4x4 transform;
    float4 pos;
};

struct Voxels_Data {
    uchar cell[AS_GROUP_SIZE][AS_GROUP_SIZE][AS_GROUP_SIZE];
};

struct Payload {
    uint ox;
    uint oy;
    uint mapy[AS_GROUP_SIZE];
};

using Voxel = metal::mesh<Vertex, TriangleOut, 8*STACK_SIZE, 6*STACK_SIZE, topology::triangle>;

// For now it's a direct access but later on we want to replace this with an Octree acceleration structure
uchar get_voxel(constant Voxels_Data*  voxels_data, uint3 upos) {
    // The swapped palces between z and y is on purpose
    return voxels_data->cell[upos.x][upos.z][upos.y];
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

    bool has_left_neightbour = voxels_data->cell[upos.x-1][upos.z][upos.y] > 0;
    bool has_right_neightbour = voxels_data->cell[upos.x+1][upos.z][upos.y] > 0;
    bool has_top_neightbour = voxels_data->cell[upos.x][upos.z][upos.y+1] > 0;

    bool has_back_top_neightbour = voxels_data->cell[upos.x][upos.z-1][upos.y+1] > 0;
    bool has_front_top_neightbour = voxels_data->cell[upos.x][upos.z+1][upos.y+1] > 0;

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

    bool has_back_neightbour = voxels_data->cell[upos.x][upos.z-1][upos.y] > 0;
    if(!has_back_neightbour && pos.z > camera_data.pos.z ) {
        // Back
        float4 normal = float4(0.0, 0.0, -1.0, 0.0);
        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 1);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Normal = normal.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 2);
        outMesh.set_index(midx++, vidx + 3);
        quads[pidx].Normal = normal.rgb;
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
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 6);
        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Normal = normal.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        
    }

    bool has_front_neightbour = voxels_data->cell[upos.x][upos.z+1][upos.y] > 0;
    if(!has_front_neightbour && camera_data.pos.z > pos.z) {
        // Front
        float4 normal = float4(0.0, 0.0, 1.0, 0.0);

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 6);
        quads[pidx].Normal = normal.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 7);
        quads[pidx].Normal = normal.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        
    }

    bool has_bottom_neightbour = voxels_data->cell[upos.x][upos.z][upos.y-1] > 0;
    if(!has_bottom_neightbour && pos.y > camera_data.pos.y && midx < max_midx) {
        // Bottom
        float4 normal = float4(0.0, -1.0, 0.0, 0.0);

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 6);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Normal = normal.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 2);
        outMesh.set_index(midx++, vidx + 1);
        quads[pidx].Normal = normal.rgb;
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
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 1);
        quads[pidx].Normal = normal.rgb;
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
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 7);
        quads[pidx].Normal = normal.rgb;
        outMesh.set_primitive(pidx, quads[pidx]);
           
    }

    return triangle_count;
}

[[object]]
void objectMain(
    uint objectIndex                      [[threadgroup_position_in_grid]],
    uint gtid                             [[thread_position_in_threadgroup]],
    uint width                            [[threads_per_threadgroup]],
    constant Voxels_Data*   voxels_data   [[buffer(0)]],
    object_data Payload& outPayload       [[payload]],
    mesh_grid_properties outGrid)
{
    uint y = objectIndex / AS_GROUP_SIZE;
    uint x = objectIndex % AS_GROUP_SIZE;
    uchar voxel = get_voxel(voxels_data, uint3(x, y, gtid));
    outPayload.mapy[gtid] = 0;
    uint visible;
    // TODO: add frustum culling and neightbour culling
    if(voxel == 0) {
        visible = 0;
    } else {
        visible = 1;
    }

    // IMPORTANT: simd works in simd groups, not threadgroups, if the threads within a threadgroup is greater than the max simd group, this will fail
    // TLDR: keep threadPerObjectThreadgroup=32 
    uint index = simd_prefix_exclusive_sum(visible);
    if(visible > 0) {
        outPayload.mapy[index] = gtid;
    }
    
    outPayload.ox = x;
    outPayload.oy = y;

    uint count = simd_sum(visible);
    if (gtid == 0) {
        outGrid.set_threadgroups_per_grid(uint3(count, 1, 1));
        //outGrid.set_threadgroups_per_grid(uint3(AS_GROUP_SIZE, 1, 1));
    }
}


[[mesh]]
void meshMain(
    Voxel outMesh,
    constant Camera_Data&   camera_data   [[buffer(0)]],
    constant Voxels_Data*   voxels_data   [[buffer(1)]],
    object_data const Payload& payload    [[payload]],
    uint payloadIndex                       [[threadgroup_position_in_grid]],
    uint threadIndex                        [[thread_position_in_threadgroup]],
    uint tid                                [[thread_position_in_grid]],
    uint width                              [[threadgroups_per_grid]]
) {
    

    if (threadIndex == 0) {
        outMesh.set_primitive_count(6);
    }
    
    uint x = payload.ox;
    uint y = payload.oy;
    uint z =  payload.mapy[payloadIndex];
    float w = 0.5;

    uint3 pos;
    pos = uint3(x,y,z);
    float4 c = float4(float3(0.2), 0.0);
    pushCube(outMesh, pos, camera_data, w, 0, c, voxels_data);
    
}


struct FSInput
{
    Vertex vtx;
    TriangleOut tri;
};

[[fragment]]
float4 fragmentMain(FSInput input [[stage_in]])
{
    float3 normalColor = float3(0.5) + input.tri.Normal / 2.0;
    return float4(normalColor, 1.0);
}