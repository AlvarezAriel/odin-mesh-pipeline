#include <metal_stdlib>
using namespace metal;

#define STACK_SIZE 8
#define CHUNKS_MAX 64
#define CHUNK_W 512
#define CHUNK_H 32
#define PARTITION_SIZE 8 
#define INNER_SIZE 4
#define CONCURRENT_CHUNKS_MAX 3000

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
    uchar partitions[CHUNK_W/PARTITION_SIZE][CHUNK_H/PARTITION_SIZE][CHUNK_W/PARTITION_SIZE];
    uint64_t chunks[CHUNK_W][CHUNK_H][CHUNK_W];
};

struct Payload {
    uint ox;
    uint oy;
    uint oz;
};

using Voxel = metal::mesh<Vertex, TriangleOut, 125, 6 * 64, topology::triangle>;

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
    uint3 worldPos, 
    uint3 localPos,
    constant Camera_Data&   camera_data,
    float w,
    float4 tone,
    constant Voxels_Data* voxels_data
) {
    uint triangle_count = 0;
    float4 pos = float4(float(worldPos.x), float(worldPos.y), float(worldPos.z), 0.0);

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
    uint idx = localPos.x + localPos.y*4 + localPos.z*16; // 
    uint midx = idx * 18;
    uint pidx = idx * 6;
    
    bool has_left_neightbour = pos.x - w <= camera_data.pos.x  || get_voxel(voxels_data, uint3(worldPos.x-1,worldPos.y,worldPos.z)) > 0;
    bool has_right_neightbour = camera_data.pos.x <= pos.x + w || get_voxel(voxels_data, uint3(worldPos.x+1,worldPos.y,worldPos.z)) > 0;
    bool has_top_neightbour = pos.y >= camera_data.pos.y       || get_voxel(voxels_data, uint3(worldPos.x,worldPos.y+1, worldPos.z)) > 0;
    bool has_back_neightbour = pos.z - w <= camera_data.pos.z  || get_voxel(voxels_data, uint3(worldPos.x,worldPos.y, worldPos.z-1)) > 0;
    bool has_front_neightbour = camera_data.pos.z <= pos.z + w || get_voxel(voxels_data, uint3(worldPos.x,worldPos.y, worldPos.z+1)) > 0;
    bool has_bottom_neightbour = pos.y -w < camera_data.pos.y  || get_voxel(voxels_data, uint3(worldPos.x,worldPos.y-1,worldPos.z)) > 0;


    // if(has_top_neightbour && has_bottom_neightbour && has_left_neightbour && has_right_neightbour && has_front_neightbour && has_back_neightbour) {
    //     return 0;
    // }
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

    uint3 exps = uint3(1,5,25);
    uint3 tmp; // dot product only works with float, otehrwise I would use that. I couldn't find a mulAdd

    tmp = (localPos + uint3(0,1,0)) * exps;
    uint vid0 = tmp.x + tmp.y + tmp.z;

    tmp = (localPos + uint3(0,0,0)) * exps;
    uint vid1 = tmp.x + tmp.y + tmp.z;

    tmp = (localPos + uint3(1,0,0)) * exps;
    uint vid2 = tmp.x + tmp.y + tmp.z;

    tmp = (localPos + uint3(1,1,0)) * exps;
    uint vid3 = tmp.x + tmp.y + tmp.z;

    tmp = (localPos + uint3(0,1,1)) * exps;
    uint vid4 = tmp.x + tmp.y + tmp.z;

    tmp = (localPos + uint3(0,0,1)) * exps;
    uint vid5 = tmp.x + tmp.y + tmp.z;

    tmp = (localPos + uint3(1,0,1)) * exps;
    uint vid6 = tmp.x + tmp.y + tmp.z;
    
    tmp = (localPos + uint3(1,1,1)) * exps;
    uint vid7 = tmp.x + tmp.y + tmp.z;

    outMesh.set_vertex(vid0, vertices[0]);
    outMesh.set_vertex(vid1, vertices[1]);
    outMesh.set_vertex(vid2, vertices[2]);
    outMesh.set_vertex(vid3, vertices[3]);

    outMesh.set_vertex(vid4, vertices[4]);
    outMesh.set_vertex(vid5, vertices[5]);
    outMesh.set_vertex(vid6, vertices[6]);
    outMesh.set_vertex(vid7, vertices[7]);

    float normalStrenght = 1.0;
    float3 sunAngle = normalize(camera_data.sun.xyz);

    if(!has_back_neightbour) {
        // Back
        float4 normal = float4(0.0, 0.0, -1.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        t = mix(normalStrenght, 1.0, t);

        outMesh.set_index(midx++, vid0);
        outMesh.set_index(midx++, vid1);
        outMesh.set_index(midx++, vid2);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vid0);
        outMesh.set_index(midx++, vid2);
        outMesh.set_index(midx++, vid3);
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

        outMesh.set_index(midx++, vid7);
        outMesh.set_index(midx++, vid3);
        outMesh.set_index(midx++, vid2);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vid6);
        outMesh.set_index(midx++, vid7);
        outMesh.set_index(midx++, vid2);
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

        outMesh.set_index(midx++, vid5);
        outMesh.set_index(midx++, vid7);
        outMesh.set_index(midx++, vid6);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vid5);
        outMesh.set_index(midx++, vid4);
        outMesh.set_index(midx++, vid7);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_bottom_neightbour && triangle_count < 6) {
        // Bottom
        float4 normal = float4(0.0, -1.0, 0.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        t = mix(normalStrenght, 1.0, t);

        outMesh.set_index(midx++, vid5);
        outMesh.set_index(midx++, vid6);
        outMesh.set_index(midx++, vid2);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vid5);
        outMesh.set_index(midx++, vid2);
        outMesh.set_index(midx++, vid1);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_left_neightbour && triangle_count < 6) {
        // Left
        float4 normal = float4(-1.0, 0.0, 0.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        t = mix(normalStrenght, 1.0, t);

        outMesh.set_index(midx++, vid0);
        outMesh.set_index(midx++, vid4);
        outMesh.set_index(midx++, vid1);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vid4);
        outMesh.set_index(midx++, vid5);
        outMesh.set_index(midx++, vid1);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_top_neightbour && triangle_count < 6) {
        // Top
        float4 normal = float4(0.0, 1.0, 0.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        t = mix(normalStrenght, 1.0, t);

        outMesh.set_index(midx++, vid7);
        outMesh.set_index(midx++, vid0);
        outMesh.set_index(midx++, vid3);
        quads[pidx].Color = tone.rgb * t;
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vid4);
        outMesh.set_index(midx++, vid0);
        outMesh.set_index(midx++, vid7);
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
    if(voxels_data->partitions[objectIndex.x][objectIndex.y][objectIndex.z] > 0) {
        float vision_cone = dot(normalize(float3(objectIndex * INNER_SIZE) - camera_data.pos.xyz), normalize(camera_data.look.xyz));
        if(vision_cone > 0.0 || (distance(float3(objectIndex)*INNER_SIZE + float3(1), camera_data.pos.xyz) < 2)) {
            // if(voxels_data->chunks[objectIndex.x][objectIndex.y][objectIndex.z] > 0) {
                outPayload.ox = objectIndex.x;
                outPayload.oy = objectIndex.y;
                outPayload.oz = objectIndex.z;
                if (gtid == 0) {
                    outGrid.set_threadgroups_per_grid(uint3(PARTITION_SIZE,PARTITION_SIZE,PARTITION_SIZE));
                }
            // }
        }
    }
}

uint processVoxel(
    Voxel outMesh, 
    uint3 pos, 
    uint3 localPos,
    constant Camera_Data&   camera_data,
    constant Voxels_Data* voxels_data
) {
    float3 fpos = float3(pos);
    float vision_cone = dot(normalize(fpos - camera_data.pos.xyz), normalize(camera_data.look.xyz));

    uint primitiveCount = 0;
    if(vision_cone > 0.6) {
        float4 c = float4(float3(0.0), 1.0);
        primitiveCount += pushCube(outMesh, pos, localPos, camera_data, 0.5, c, voxels_data);
    }

    return primitiveCount;
}

[[mesh]]
void meshMain(
    Voxel outMesh,
    constant Camera_Data&   camera_data   [[buffer(0)]],
    constant Voxels_Data*   voxels_data   [[buffer(1)]],
    object_data const Payload& payload    [[payload]],
    uint3 partitionPos                    [[threadgroup_position_in_grid]],
    uint3 threadIndex                     [[thread_position_in_threadgroup]],
    uint3 tid                             [[thread_position_in_grid]],
    uint width                            [[threadgroups_per_grid]]
) {
    // uint x = payload.ox;
    // uint y = payload.oy;
    // uint z =  payload.oz;

    uint3 globalPos = uint3(payload.ox, payload.oy, payload.oz) * PARTITION_SIZE + partitionPos;
        if(voxels_data->chunks[globalPos.x][globalPos.y][globalPos.z] > 0) {
        uint3 localPos = threadIndex;
        float w = 0.5;
        uint primitiveCount = 0;

        uint3 worldPos = globalPos * INNER_SIZE + localPos;
        if (threadIndex.x == 0 && threadIndex.y == 0 && threadIndex.z == 0) {
            // TODO: this amount can be optimized, since in reality we will always have at most half of this
            // but since we only know after processing, it's hard (?) to get the correct mesh ID without serializing threads.
            outMesh.set_primitive_count(8 * 64);
        }

        if(get_voxel(voxels_data, worldPos) > 0) {
            //uint idx = threadIndex.x + threadIndex.y*2 + threadIndex.z*4;
            primitiveCount += processVoxel(
                outMesh, worldPos, localPos, camera_data, voxels_data
            );
        }
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
    return float4(input.tri.Color.rgb, 1.0);
    // return float4(input.vtx.Col.rgb, 1.0);
}