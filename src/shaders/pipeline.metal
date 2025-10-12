#include <metal_stdlib>
using namespace metal;

#define STACK_SIZE 8
#define CHUNKS_MAX 64
#define CHUNK_W 64
#define CHUNK_H 32
#define INNER_SIZE 4
#define CONCURRENT_CHUNKS_MAX 3000

struct Vertex {
    float4 PositionCS [[position]];
    float3 VColor;
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
    uint64_t chunks[CHUNK_W][CHUNK_H][CHUNK_W];
};

struct Payload {
    uint ox;
    uint oy;
    uint oz;
};

using Voxel = metal::mesh<Vertex, TriangleOut, 8, 12, topology::triangle>;

// For now it's a direct access but later on we want to replace this with an Octree acceleration structure
uint64_t get_voxel(constant Voxels_Data*  voxels_data, uint3 upos) {
    // The swapped palces between z and y is on purpose
    uint64_t chunk = voxels_data->chunks[upos.x/INNER_SIZE][upos.y/INNER_SIZE][upos.z/INNER_SIZE];
    uint64_t tag = uint64_t(1) << uint64_t((upos.x % INNER_SIZE) + (upos.y % INNER_SIZE)*INNER_SIZE + (upos.z % INNER_SIZE)*INNER_SIZE*INNER_SIZE);
    return tag & chunk;
}



float hammingWeight(uint64_t x)
{
    const uint64_t m1  = 0x5555555555555555; //binary: 0101...
    const uint64_t m2  = 0x3333333333333333; //binary: 00110011..
    const uint64_t m4  = 0x0f0f0f0f0f0f0f0f; //binary:  4 zeros,  4 ones ...
    const uint64_t h01 = 0x0101010101010101; //the sum of 256 to the power of 0,1,2,3...
    x -= (x >> 1) & m1;             //put count of each 2 bits into those 2 bits
    x = (x & m2) + ((x >> 2) & m2); //put count of each 4 bits into those 4 bits 
    x = (x + (x >> 4)) & m4;        //put count of each 8 bits into those 8 bits 
    return float((x * h01) >> 56) / 64.0;  //returns left 8 bits of x + (x<<8) + (x<<16) + (x<<24) + ... as a normalized float
}

float lightCalc(
    float3 starting, 
    constant Camera_Data&   camera_data,
    constant Voxels_Data* voxels_data
) {
    float3 sun = camera_data.sun.xyz;
    float maxSteps = 6.0;

    float3 startingBlock = starting/INNER_SIZE;

    float light = 1.0;

    float lodStep = 1.0;
    float lodMaxSteps = 8.0;
    for(lodStep = 1.1; lodStep < lodMaxSteps; lodStep += 0.8) {
        float3 dir = starting + sun * lodStep;
        uint3 ray = uint3(dir);
        if(get_voxel(voxels_data, ray) > 0) {
            light = 0.5 - mix(0.5, 0.1, distance(dir, starting)/lodMaxSteps);
            if(light < 0.1) {
                return light;
            }
        }
    }  

    for(float i = lodStep/INNER_SIZE; i < maxSteps; i += 1.05) {
        uint3 ray = uint3(startingBlock + sun * i);
        uint64_t block = voxels_data->chunks[ray.x][ray.y][ray.z];
        float weight = hammingWeight(block);
        if(weight > 0.9) {
            return 0.0;
        }
        light -= hammingWeight(block) * (1.5 - i/maxSteps);
        if(light <= 0.01) {
            return 0.01;
        }
    }
     
    return light;
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
    float4 pos = float4(float(upos.x), float(upos.y), float(upos.z), 0.0);

    tone =  lightCalc(pos.xyz + float3(+w,w,+w), camera_data, voxels_data);
    tone +=  lightCalc(pos.xyz + float3(0,0,0), camera_data, voxels_data);
    // tone += lightCalc(pos.xyz + float3(+w,w,-w), camera_data, voxels_data);
    // tone += lightCalc(pos.xyz + float3(-w,w,+w), camera_data, voxels_data);
    // tone += lightCalc(pos.xyz + float3(-w,w,-w), camera_data, voxels_data);
    tone = tone / 2.0;
    tone = mix(0.05, 1.0, tone);


    //tone =  lightCalc(pos.xyz + float3( 0,0, 0), camera_data, voxels_data);

    // TOOD: remove this, it's just a way to hack materials for now
    // if(upos.y == 0) {
    //     float4 green = mix(float4(0.15, 0.6, 0.27, 0.0), float4(0.3, 0.97, 0.42, 0.0), tone);
    //     tone = green;
    // } else {
    //     if(upos.y > 3 && upos.x < 200 && upos.z > 128) {
    //         float4 red = mix(float4(0.55, 0.14, 0.19, 0.0), float4(0.95, 0.28, 0.32, 0.0), tone);
    //         tone = red;
    //     } else {
    //         tone = float4(mix(0.2, 1.0, tone));
    //     }
    // }
    // tone = min(tone, float4(1.0));
    Vertex vertices[8];
    TriangleOut quads[6];
    uint vidx = idx * 8;
    uint midx = idx * 18;
    uint pidx = idx * 6;

    uint max_midx = idx * (36/2) + 18;
    uint max_pidx = idx * 6 + 6;

    

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

    vertices[0].VColor = float3(1.0);
    vertices[1].VColor = float3(1.0);
    vertices[2].VColor = float3(1.0);
    vertices[3].VColor = float3(1.0);
    vertices[4].VColor = float3(1.0);
    vertices[5].VColor = float3(1.0);
    vertices[6].VColor = float3(1.0);
    vertices[7].VColor = float3(1.0);

    float shadow = 0.6;
    // if(!has_front_neightbour) {
    //     if(get_voxel(voxels_data, uint3(upos.x,upos.y - 1, upos.z+1)) > 0) {
    //         vertices[5].VColor = float3(shadow);
    //         vertices[6].VColor = float3(shadow);
    //     }
    // }

    // if(!has_right_neightbour) {
    //     if(get_voxel(voxels_data, uint3(upos.x+1,upos.y - 1, upos.z)) > 0) {
    //         vertices[2].VColor = float3(shadow);
    //         vertices[6].VColor = float3(shadow);
    //     }
    // }

    // if(!has_top_neightbour) {
    //     bool has_top_left = get_voxel(voxels_data, uint3(upos.x-1,upos.y + 1, upos.z)) > 0;
    //     bool has_top_front = get_voxel(voxels_data, uint3(upos.x,upos.y + 1, upos.z+1)) > 0;

    //     if(has_top_left) {
    //         vertices[0].VColor = float3(shadow);
    //         vertices[4].VColor = float3(shadow);
    //     }

    //     if(get_voxel(voxels_data, uint3(upos.x,upos.y + 1, upos.z-1)) > 0) {
    //         vertices[0].VColor = float3(shadow);
    //         vertices[3].VColor = float3(shadow);
    //         // ??
    //     }

    //     if(get_voxel(voxels_data, uint3(upos.x-1,upos.y + 1, upos.z-1)) > 0) {
    //         vertices[0].VColor = float3(shadow*1.2);
    //     }

    //     if(get_voxel(voxels_data, uint3(upos.x-1,upos.y + 1, upos.z+1)) > 0) {
    //         vertices[4].VColor = min(vertices[4].VColor, float3(shadow*1.2));
    //     }

    //     if(has_top_front) {
    //         vertices[4].VColor = float3(shadow);
    //         vertices[7].VColor = float3(shadow);
    //     }

    //     if(has_top_left && has_top_front) {
    //         vertices[4].VColor = float3(shadow);
    //     }
    // }


    outMesh.set_vertex(vidx + 0, vertices[0]);
    outMesh.set_vertex(vidx + 1, vertices[1]);
    outMesh.set_vertex(vidx + 2, vertices[2]);
    outMesh.set_vertex(vidx + 3, vertices[3]);

    outMesh.set_vertex(vidx + 4, vertices[4]);
    outMesh.set_vertex(vidx + 5, vertices[5]);
    outMesh.set_vertex(vidx + 6, vertices[6]);
    outMesh.set_vertex(vidx + 7, vertices[7]);

    float normalStrenght = 0.7;

    float3 sunAngle = normalize(camera_data.sun.xyz);
    if(!has_back_neightbour) {
        // Back
        float4 normal = float4(0.0, 0.0, -1.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        t = mix(normalStrenght, 1.0, t);

        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 1);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 2);
        outMesh.set_index(midx++, vidx + 3);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }
    
    if(!has_right_neightbour ) {
        // Right
        float4 normal = float4(1.0, 0.0, 0.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        t = mix(normalStrenght, 1.0, t);

        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 3);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 6);
        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_front_neightbour) {
        // Front
        float4 normal = float4(0.0, 0.0, 1.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        t = mix(normalStrenght, 1.0, t);

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 6);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 7);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_bottom_neightbour && midx < max_midx) {
        // Bottom
        float4 normal = float4(0.0, -1.0, 0.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        t = mix(normalStrenght, 1.0, t);

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 6);
        outMesh.set_index(midx++, vidx + 2);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 2);
        outMesh.set_index(midx++, vidx + 1);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_left_neightbour && midx < max_midx) {
        // Left
        float4 normal = float4(-1.0, 0.0, 0.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        t = mix(normalStrenght, 1.0, t);

        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 1);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 5);
        outMesh.set_index(midx++, vidx + 1);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_top_neightbour && midx < max_midx) {
        // Top
        float4 normal = float4(0.0, 1.0, 0.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        t = mix(normalStrenght, 1.0, t);

        outMesh.set_index(midx++, vidx + 7);
        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 3);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vidx + 4);
        outMesh.set_index(midx++, vidx + 0);
        outMesh.set_index(midx++, vidx + 7);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        triangle_count += 2;   
    }

    return triangle_count;
}

[[object]]
void objectMain(
    uint3 objectIndex                     [[threadgroup_position_in_grid]],
    uint gtid                             [[thread_position_in_threadgroup]],
    uint width                            [[threads_per_threadgroup]],
    constant Camera_Data&   camera_data   [[buffer(0)]],
    constant Voxels_Data*   voxels_data   [[buffer(1)]],
    object_data Payload& outPayload       [[payload]],
    mesh_grid_properties outGrid)
{

    float vision_cone = dot(normalize(float3(objectIndex * INNER_SIZE) - camera_data.pos.xyz), normalize(camera_data.look.xyz));
    if(vision_cone > 0.0 || (distance(float3(objectIndex)*INNER_SIZE + float3(1), camera_data.pos.xyz) < 2)) {
        if(voxels_data->chunks[objectIndex.x][objectIndex.y][objectIndex.z] > 0) {
            outPayload.ox = objectIndex.x;
            outPayload.oy = objectIndex.y;
            outPayload.oz = objectIndex.z;
            if (gtid == 0) {
                outGrid.set_threadgroups_per_grid(uint3(INNER_SIZE, INNER_SIZE, INNER_SIZE) );
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
    if(vision_cone > 0.6) {
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

    uint3 upos = uint3(x,y,z);
    float w = 0.5;
    uint primitiveCount = 0;

    if (threadIndex.x == 0) {
        // TODO: this amount can be optimized, since in reality we will always have at most half of this
        // but since we only know after processing, it's hard (?) to get the correct mesh ID without serializing threads.
        outMesh.set_primitive_count(12);
    }
    uint3 insidePos = upos * INNER_SIZE + chunkPos;

    if(get_voxel(voxels_data, insidePos) > 0) {
        //uint idx = threadIndex.x + threadIndex.y*2 + threadIndex.z*4;
        primitiveCount += processVoxel(
            outMesh, insidePos, camera_data, 0, voxels_data
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
    // float3 color = mix(0.0, 2.0, input.tri.Color.r);
    // float3 result = mix(0.0, 0.1, input.vtx.PositionCS.w - 0.5); 
    // float3 c2 = mix(float3(0.1, 0.17, 0.35), float3(1.0, 0.71, 0.73), color.r);
    return float4(input.tri.Color.rgb * input.vtx.VColor.r, 1.0);
}