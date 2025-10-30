#include <metal_stdlib>
using namespace metal;

#define CHUNK_W 256
#define CHUNK_H 64
#define PARTITION_SIZE_W 4
#define PARTITION_SIZE_H 2
#define INNER_SIZE 4
#define PI 3.1415926535

struct Vertex {
    float4 PositionCS [[position]];
};

struct TriangleOut {
    float4 Color [[flat]];
};

struct Camera_Data {
    float4x4 transform;
    float4 pos;
    float4 look;
    float4 target;
    float4 sun;
    uint step;
};

struct ChunkHeader {
    ushort tag;
    ushort material;
    ushort idx;
};

struct Voxels_Data {
    uchar partitions[CHUNK_W/PARTITION_SIZE_W][CHUNK_H/PARTITION_SIZE_H][CHUNK_W/PARTITION_SIZE_W];
    uint64_t chunks[CHUNK_W][CHUNK_H][CHUNK_W];
};

struct Light_Data {
    half chunks[CHUNK_W*INNER_SIZE][CHUNK_H*INNER_SIZE][CHUNK_W*INNER_SIZE];
};

struct Payload {
    uint ox;
    uint oy;
    uint oz;
    uint3 chunkIdx[PARTITION_SIZE_W*PARTITION_SIZE_H*PARTITION_SIZE_W];
};

using Voxel = metal::mesh<Vertex, TriangleOut, 125, 6 * 64, topology::triangle>;

uint64_t get_voxel_from_chunk(constant Voxels_Data*  voxels_data, uint3 upos, uint64_t chunk) {
    uint64_t tag = uint64_t(1) << uint64_t((upos.x % INNER_SIZE) + (upos.y % INNER_SIZE)*INNER_SIZE + (upos.z % INNER_SIZE)*INNER_SIZE*INNER_SIZE);
    return tag & chunk;
}
// For now it's a direct access but later on we want to replace this with an Octree acceleration structure
uint64_t get_voxel(constant Voxels_Data*  voxels_data, uint3 upos) {
    // The swapped palces between z and y is on purpose
    uint64_t chunk = voxels_data->chunks[upos.x/INNER_SIZE][upos.y/INNER_SIZE][upos.z/INNER_SIZE];
    return get_voxel_from_chunk(voxels_data, upos, chunk);
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
    float maxSteps = 32.0;

    float3 startingBlock = starting/INNER_SIZE;

    float light = 1.0;
    uint maxHeight = CHUNK_H * INNER_SIZE;
    uint maxWidth = CHUNK_W * INNER_SIZE;
    float lodStep = 1.0;
    float lodMaxSteps = 32.0;
    uint3 ray = uint3(0);
    for(lodStep = 1.5; lodStep < lodMaxSteps; lodStep += 0.8) {
        float3 dir = starting + sun * lodStep;
        ray = uint3(dir);
        if(ray.x > maxWidth || ray.y > maxHeight || ray.z > maxWidth || ray.z < 0 || ray.x < 0) {
            return 1.0;
        }
        if(get_voxel(voxels_data, ray) > 0) {
            light = 0.5 - mix(0.5, 0.1, distance(dir, starting)/lodMaxSteps);
            if(light < 0.2) {
                break;
            }
        }
    }

    for(float i = lodStep/INNER_SIZE; i < maxSteps; i += 1.05) {
        ray = uint3(startingBlock + sun * i);
        if(ray.x > CHUNK_W || ray.y > CHUNK_H || ray.z > CHUNK_W || ray.z < 0 || ray.x < 0) {
            return light;
        }
        uint64_t block = voxels_data->chunks[ray.x][ray.y][ray.z];
        float weight = hammingWeight(block);
        if(weight > 0.9) {
            return 0.0;
        }
        light -= hammingWeight(block) * (log2(1.0 + i/maxSteps));
        if(light <= 0.01) {
            return 0.01;
        }
    }
     
    return light;
}

float castIntersect(constant Voxels_Data* voxels_data, uint3 from, float3 dir, uint count)
{
    int3 f = int3(from);
    float m = max3(abs(dir.x), abs(dir.y), abs(dir.z));
    float st = 1.0 / m;
    float3 step = dir * st;
    uint maxY =  CHUNK_H*INNER_SIZE;
    uint maxW =  CHUNK_W*INNER_SIZE;

    uint i = 1;
    for(; i < count; i++) {
        uint3 next = uint3(f - int3(trunc(step * i)));
        if(next.x >= maxW || next.y >= maxY || next.z >= maxW) {
            break;
        }
        uint64_t chunk = voxels_data->chunks[next.x/INNER_SIZE][next.y/INNER_SIZE][next.z/INNER_SIZE];
        if(chunk == 0) {
            
            if(voxels_data->partitions[next.x/PARTITION_SIZE_W][next.y/PARTITION_SIZE_H][next.z/PARTITION_SIZE_W] == 0) {
                uint3 c = min3(next.x/PARTITION_SIZE_W, next.y/PARTITION_SIZE_H, next.z/PARTITION_SIZE_W);
            }

            uint3 prev = uint3(next.x/INNER_SIZE, next.y/INNER_SIZE, next.z/INNER_SIZE);
            uint k = i + 1;
            for(; ;k++){
                next = uint3(f - int3(trunc(step * k)));
                uint3 c = min3(next.x/INNER_SIZE, next.y/INNER_SIZE, next.z/INNER_SIZE);
                if(c.x != prev.x || c.y != prev.y || c.z != prev.z) {
                    i = k - 1;
                    break;
                }
            }
            continue;
        }

        if(get_voxel_from_chunk(voxels_data, next, chunk) > 0) {
            return 0;
        }
    }

    return 1.0;
}

float countConeLight(constant Voxels_Data* voxels_data, constant Light_Data* light_data, uint3 from, float3 dir, uint count)
{
    int3 f = int3(from);
    float m = max3(abs(dir.x), abs(dir.y), abs(dir.z));
    float st = 1.0 / m;
    float3 step = dir * st;
    uint maxY =  CHUNK_H*INNER_SIZE;
    uint maxW =  CHUNK_W*INNER_SIZE;
    bool should_set_shadow = false;

    uint i = 0;
    float lightCount = 0;
    for(; i < count; i++) {
        uint3 next = uint3(f + int3(trunc(step * i)));
        if(get_voxel(voxels_data, next) > 0) {
            break;
        }
        lightCount +=  1.0 - light_data->chunks[next.x][next.y][next.z];
    }

    return lightCount ;
}

uint4 is_hit(constant Camera_Data&   camera_data, constant Voxels_Data* voxels_data, constant Light_Data* light_data, uint3 from, float3 dir, uint count)
{
    int3 f = int3(from);
    float m = max3(abs(dir.x), abs(dir.y), abs(dir.z));
    float st = 1.0 / m;
    float3 step = dir * st;
    uint maxY =  CHUNK_H*INNER_SIZE;
    uint maxW =  CHUNK_W*INNER_SIZE;

    uint i = 1;
    uint3 hitPoint;
    uint3 next;
    for(; i < count; i++) {
        hitPoint = next;
        next = uint3(f - int3(trunc(step * i)));
        if(next.x >= maxW || next.y >= maxY || next.z >= maxW) {
            break;
        }
        uint64_t chunk = voxels_data->chunks[next.x/INNER_SIZE][next.y/INNER_SIZE][next.z/INNER_SIZE];
        if(chunk == 0) {
            
            if(voxels_data->partitions[next.x/PARTITION_SIZE_W][next.y/PARTITION_SIZE_H][next.z/PARTITION_SIZE_W] == 0) {
                uint3 c = min3(next.x/PARTITION_SIZE_W, next.y/PARTITION_SIZE_H, next.z/PARTITION_SIZE_W);
            }

            uint3 prev = uint3(next.x/INNER_SIZE, next.y/INNER_SIZE, next.z/INNER_SIZE);
            uint k = i + 1;
            for(; ;k++){
                next = uint3(f - int3(trunc(step * k)));
                uint3 c = min3(next.x/INNER_SIZE, next.y/INNER_SIZE, next.z/INNER_SIZE);
                if(c.x != prev.x || c.y != prev.y || c.z != prev.z) {
                    i = k - 1;
                    break;
                }
            }
            continue;
        }

        if(get_voxel_from_chunk(voxels_data, next, chunk) > 0) {
            return uint4(hitPoint, 1);
        }
    }

    return uint4(0);
}

float topLightCone(constant Camera_Data&   camera_data, constant Voxels_Data* voxels_data, constant Light_Data* light_data, uint3 from, float side, uint steps, uint coneRays, float3 normal) {
    float lightAcc = 0;

    uint3 starting = uint3(int3(from) + int3(0, side ,0));
    
    float3 sunAngle = normalize(camera_data.sun.xyz);
    float directAngle = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;

    float directLight = 0;
    if(directAngle > 0) {
        directLight = castIntersect(voxels_data, from + uint3(0,1,0), -camera_data.sun.xyz, 128);
        if(directLight == 1.0) {
            return 1.0;
        }
    }
    float indirectLight = 0;

    float rays = float(coneRays);
    float rotation = (PI*2)/rays;
    for(float i = 0; i < rays;i++) {
        float r = i*rotation;
        float x = cos(r);
        float z = sin(r);
        uint4 hit = is_hit(camera_data, voxels_data, light_data, starting, -normalize(float3(x, side, z)), steps);
        if(hit.w != 0) {
            indirectLight += 1.0 - light_data->chunks[hit.x][hit.y][hit.z];
        }
    }

    float ambient = 0;
    if(directAngle > 0.1) {
        for(float i = 0; i < rays/2; i++) {
            float r = i*rotation;
            float x = cos(r);
            float z = sin(r);
            ambient += countConeLight(voxels_data, light_data, starting, normalize(float3(x, side, z)), 6);
        }
    }

    ambient = ambient / rays;

    float neight = 0;
    float bias = 0.07;
    neight += bias - min(float(get_voxel(voxels_data, uint3(int3(from) + int3(0, 0, +1)) )), 1.0)*bias;
    neight += bias - min(float(get_voxel(voxels_data, uint3(int3(from) + int3(0,  0, -1)) )), 1.0)*bias;
    neight += bias - min(float(get_voxel(voxels_data, uint3(int3(from) + int3(+1, 0,  0)) )), 1.0)*bias;
    neight += bias - min(float(get_voxel(voxels_data, uint3(int3(from) + int3(-1, 0,  0)) )), 1.0)*bias;

    float ambientBias = directAngle*(0.3 + neight);

    lightAcc = indirectLight / rays;

    float total = ambient*ambientBias+lightAcc*0.5 + directLight*0.8;

    return min(total, 1.0);
}

float lateralLightCone(constant Camera_Data&   camera_data, constant Voxels_Data* voxels_data, constant Light_Data* light_data, uint3 from, float side, uint steps, uint coneRays, float3 normal) {
     float lightAcc = 0;

    uint3 starting = uint3(int3(from) + int3(side, 0 ,0));
    
    float3 sunAngle = normalize(camera_data.sun.xyz);
    float directAngle = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;

    float directLight = 0;
    if(directAngle > 0) {
        directLight = castIntersect(voxels_data, from + uint3(1,0,0), -camera_data.sun.xyz, 128);
    }
    float indirectLight = 0;

    float rays = float(coneRays);
    float rotation = (PI*2)/rays;
    for(float i = 0; i < rays;i++) {
        float r = i*rotation;
        float x = cos(r);
        float z = sin(r);
        uint4 hit = is_hit(camera_data, voxels_data, light_data, starting, -normalize(float3(side, x, z)), steps);
        if(hit.w != 0) {
            indirectLight += 1.0 - light_data->chunks[hit.x][hit.y][hit.z];
        }
    }

    float ambient = 0;
    if(directAngle > 0.2) {
        for(float i = 0; i < rays/2; i++) {
            float r = i*rotation;
            float x = cos(r);
            float z = sin(r);
            ambient += countConeLight(voxels_data, light_data, starting, normalize(float3(side, x, z)), 6);
        }
    }

    ambient = ambient / rays;

    float neight = 0;
    float bias = 0.07;
    neight += bias - min(float(get_voxel(voxels_data, uint3(int3(from) + int3(0,  0, +1)) )), 1.0)*bias;
    neight += bias - min(float(get_voxel(voxels_data, uint3(int3(from) + int3(0,  0, -1)) )), 1.0)*bias;
    neight += bias - min(float(get_voxel(voxels_data, uint3(int3(from) + int3(0, +1,  0)) )), 1.0)*bias;
    neight += bias - min(float(get_voxel(voxels_data, uint3(int3(from) + int3(0, -1,  0)) )), 1.0)*bias;

    float ambientBias = directAngle*(0.3 + neight);

    lightAcc = indirectLight / rays;

    float total = ambient*ambientBias+lightAcc*0.5 + directLight*0.8;

    return min(total, 1.0);
}


float frontalLightCone(constant Camera_Data&   camera_data, constant Voxels_Data* voxels_data, constant Light_Data* light_data, uint3 from, float side, uint steps, uint coneRays, float3 normal) {
     float lightAcc = 0;

    uint3 starting = uint3(int3(from) + int3(0 ,0, side));
    
    float3 sunAngle = normalize(camera_data.sun.xyz);
    float directAngle = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;

    float directLight = 0;
    if(directAngle > 0.2) {
        directLight = castIntersect(voxels_data, from, -camera_data.sun.xyz, 128);
    }
    float indirectLight = 0;

    float rays = float(coneRays);
    float rotation = (PI*2)/rays;
    for(float i = 0; i < rays;i++) {
        float r = i*rotation;
        float x = cos(r);
        float z = sin(r);
        uint4 hit = is_hit(camera_data, voxels_data, light_data, starting, -normalize(float3(x, z, side)), steps);
        if(hit.w != 0) {
            indirectLight += 1.0 - light_data->chunks[hit.x][hit.y][hit.z];
        }
    }

    float ambient = 0;
    for(float i = 0; i < rays; i++) {
        float r = i*rotation;
        float x = cos(r);
        float z = sin(r);
        ambient += countConeLight(voxels_data, light_data, starting, normalize(float3(x*2, z*2, side)), 6);
    }

    
    ambient = ambient / rays;

    float neight = 0;
    float bias = 0.07;
    neight += bias - min(float(get_voxel(voxels_data, uint3(int3(from) + int3(  0, +1, 0)) )), 1.0)*bias;
    neight += bias - min(float(get_voxel(voxels_data, uint3(int3(from) + int3(  0, -1, 0)) )), 1.0)*bias;
    neight += bias - min(float(get_voxel(voxels_data, uint3(int3(from) + int3( +1,  0, 0)) )), 1.0)*bias;
    neight += bias - min(float(get_voxel(voxels_data, uint3(int3(from) + int3( -1,  0, 0)) )), 1.0)*bias;

    float ambientBias = directAngle*(0.3 + neight);

    lightAcc = indirectLight / rays;

    float total = ambient*ambientBias+lightAcc*0.5 + directLight*0.8;

    return min(total, 1.0);
}

uint pushCube(
    Voxel outMesh, 
    uint3 worldPos, 
    uint3 localPos,
    constant Camera_Data&   camera_data,
    float w,
    float4 tone,
    constant Voxels_Data* voxels_data,
    constant Light_Data*     light_data
) {
    uint triangle_count = 0;
    float4 pos = float4(float(worldPos.x), float(worldPos.y), float(worldPos.z), 0.0);

    float dist = distance(camera_data.pos.xyz, pos.xyz);
    float normalizedDist = min(dist, 512.0) / 512.0;

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

    float count = 0;

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

    float normalStrenght = 0.8;
    float3 sunAngle = normalize(camera_data.sun.xyz);

    float3 baseColor = float3(0.8);
    if(distance(pos.xyz, camera_data.target.xyz) < 4.0) {
        baseColor = float3(1.0, 0.3, 0.25);
    }

    uint lightSteps = 16;
    float lightLodDistance = 600;
    float renderDistance = distance(pos.xyz, camera_data.pos.xyz);

    lightSteps = uint(mix(lightSteps, 4, renderDistance/max(renderDistance,lightLodDistance)));

    uint coneRays = uint(mix(16, 8, renderDistance/max(renderDistance,lightLodDistance)));

    if(!has_back_neightbour) {
        // Back
        float4 normal = float4(0.0, 0.0, -1.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        //t = mix(normalStrenght, 1.0, t);

        float l = frontalLightCone(camera_data, voxels_data, light_data, worldPos.xyz, -1, lightSteps, coneRays, normal.xyz);
        tone.xyz = baseColor * l;

        outMesh.set_index(midx++, vid0);
        outMesh.set_index(midx++, vid1);
        outMesh.set_index(midx++, vid2);
        quads[pidx].Color = float4(tone.rgb, normalizedDist);
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vid0);
        outMesh.set_index(midx++, vid2);
        outMesh.set_index(midx++, vid3);
        quads[pidx].Color = float4(tone.rgb, normalizedDist);
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }
    
    if(!has_right_neightbour ) {
        // Right
        float4 normal = float4(1.0, 0.0, 0.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        //t = mix(normalStrenght, 1.0, t);

        float l = lateralLightCone(camera_data, voxels_data, light_data, worldPos.xyz, 1, lightSteps, coneRays, normal.xyz);
        tone.xyz = baseColor * l;

        outMesh.set_index(midx++, vid7);
        outMesh.set_index(midx++, vid3);
        outMesh.set_index(midx++, vid2);
        quads[pidx].Color = float4(tone.rgb, normalizedDist);
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vid6);
        outMesh.set_index(midx++, vid7);
        outMesh.set_index(midx++, vid2);
        quads[pidx].Color = float4(tone.rgb, normalizedDist);
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_front_neightbour) {
        // Front
        float4 normal = float4(0.0, 0.0, 1.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        //t = mix(normalStrenght, 1.0, t);

        float l = frontalLightCone(camera_data, voxels_data, light_data, worldPos.xyz, 1, lightSteps, coneRays, normal.xyz);
        tone.xyz = baseColor * l;

        outMesh.set_index(midx++, vid5);
        outMesh.set_index(midx++, vid7);
        outMesh.set_index(midx++, vid6);
        quads[pidx].Color = float4(tone.rgb, normalizedDist);
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vid5);
        outMesh.set_index(midx++, vid4);
        outMesh.set_index(midx++, vid7);
        quads[pidx].Color = float4(tone.rgb, normalizedDist);
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_bottom_neightbour) {
        // Bottom
        float4 normal = float4(0.0, -1.0, 0.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        //t = mix(normalStrenght, 1.0, t);

        float l = topLightCone(camera_data, voxels_data, light_data, worldPos.xyz, -1, lightSteps / 2, 4, normal.xyz);
        tone.xyz = baseColor * l;

        outMesh.set_index(midx++, vid5);
        outMesh.set_index(midx++, vid6);
        outMesh.set_index(midx++, vid2);
        quads[pidx].Color = float4(tone.rgb, normalizedDist);
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vid5);
        outMesh.set_index(midx++, vid2);
        outMesh.set_index(midx++, vid1);
        quads[pidx].Color = float4(tone.rgb, normalizedDist);
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_left_neightbour) {
        // Left
        float4 normal = float4(-1.0, 0.0, 0.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        //t = mix(normalStrenght, 1.0, t);

        float l = lateralLightCone(camera_data, voxels_data, light_data, worldPos.xyz, -1, lightSteps, coneRays, normal.xyz);
        tone.xyz = baseColor * l;

        outMesh.set_index(midx++, vid0);
        outMesh.set_index(midx++, vid4);
        outMesh.set_index(midx++, vid1);
        quads[pidx].Color = float4(tone.rgb , normalizedDist);
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vid4);
        outMesh.set_index(midx++, vid5);
        outMesh.set_index(midx++, vid1);
        quads[pidx].Color = float4(tone.rgb, normalizedDist);
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;
        triangle_count += 2;
    }

    if(!has_top_neightbour) {
        // Top
        float4 normal = float4(0.0, 1.0, 0.0, 0.0);
        float t = (1.0 + dot(sunAngle, normal.rgb)) * 0.5;
        //t = mix(normalStrenght, 1.0, t);

        float l = topLightCone(camera_data, voxels_data, light_data, worldPos.xyz, 1, lightSteps, coneRays, normal.xyz);
        tone.xyz = baseColor * l;

        outMesh.set_index(midx++, vid7);
        outMesh.set_index(midx++, vid0);
        outMesh.set_index(midx++, vid3);
        quads[pidx].Color = float4(tone.rgb, normalizedDist);
        outMesh.set_primitive(pidx, quads[pidx]);
        pidx++;

        outMesh.set_index(midx++, vid4);
        outMesh.set_index(midx++, vid0);
        outMesh.set_index(midx++, vid7);
        quads[pidx].Color = float4(tone.rgb, normalizedDist);
        outMesh.set_primitive(pidx, quads[pidx]);
        triangle_count += 2;   
    }

    return triangle_count;
}

[[object]]
void objectMain(
    uint3 objectIndex                     [[threadgroup_position_in_grid]],
    uint3 gtid                            [[thread_position_in_threadgroup]],
    uint width                            [[threads_per_threadgroup]],
    constant Camera_Data&   camera_data   [[buffer(0)]],
    constant Voxels_Data*   voxels_data   [[buffer(1)]],
    object_data Payload& outPayload       [[payload]],
    mesh_grid_properties outGrid)
{
    if(voxels_data->partitions[objectIndex.x][objectIndex.y][objectIndex.z] > 0) {
        float3 blockPos = float3(objectIndex * INNER_SIZE) * float3(PARTITION_SIZE_W,PARTITION_SIZE_H,PARTITION_SIZE_W);
        float vision_cone = dot(normalize(blockPos - camera_data.pos.xyz), normalize(camera_data.look.xyz));
        float distanceToCamera = distance(blockPos + float3(1), camera_data.pos.xyz);
        if(vision_cone > 0.3 || (distanceToCamera < INNER_SIZE * PARTITION_SIZE_W)) {
            outPayload.ox = objectIndex.x;
            outPayload.oy = objectIndex.y;
            outPayload.oz = objectIndex.z;

            uint3 chunkPos = objectIndex * uint3(PARTITION_SIZE_W,PARTITION_SIZE_H,PARTITION_SIZE_W) + gtid;
            uint count = 0;
            uint id = 0;
            if(voxels_data->chunks[chunkPos.x][chunkPos.y][chunkPos.z] > 0) {
                count = 1;
                id = simd_prefix_exclusive_sum(count);
                outPayload.chunkIdx[id] = gtid;
            }
            
            uint availableChunks = simd_sum(count);
            if (simd_is_first()) {
                outGrid.set_threadgroups_per_grid(uint3(availableChunks,1,1));
            }
        }
    }
}


uint processVoxel(
    Voxel outMesh, 
    uint3 pos, 
    uint3 localPos,
    constant Camera_Data&   camera_data,
    constant Voxels_Data* voxels_data,
    constant Light_Data*     light_data
) {
    float3 fpos = float3(pos);
    float vision_cone = dot(normalize(fpos - camera_data.pos.xyz), normalize(camera_data.look.xyz));

    uint primitiveCount = 0;
    if(vision_cone > 0.6) {
        float4 c = float4(float3(0.0), 1.0);
        primitiveCount += pushCube(outMesh, pos, localPos, camera_data, 0.5, c, voxels_data, light_data);
    }

    return primitiveCount;
}

[[mesh]]
void meshMain(
    Voxel outMesh,
    constant Camera_Data&   camera_data   [[buffer(0)]],
    constant Voxels_Data*   voxels_data   [[buffer(1)]],
    constant Light_Data*     light_data   [[buffer(2)]],
    object_data const Payload& payload    [[payload]],
    uint partitionPosIndex                [[threadgroup_position_in_grid]],
    uint3 threadIndex                     [[thread_position_in_threadgroup]],
    uint3 tid                             [[thread_position_in_grid]],
    uint width                            [[threadgroups_per_grid]]
) {
    // uint x = payload.ox;
    // uint y = payload.oy;
    // uint z =  payload.oz;

    uint3 partitionPos = payload.chunkIdx[partitionPosIndex];
    uint3 globalPos = uint3(payload.ox, payload.oy, payload.oz) * uint3(PARTITION_SIZE_W,PARTITION_SIZE_H,PARTITION_SIZE_W) + partitionPos;
    uint3 localPos = threadIndex;
    uint primitiveCount = 0;

    uint3 worldPos = globalPos * INNER_SIZE + localPos;
    if (simd_is_first()) {
        // TODO: this amount can be optimized, since in reality we will always have at most half of this
        // but since we only know after processing, it's hard (?) to get the correct mesh ID without serializing threads.
        outMesh.set_primitive_count(6 * (INNER_SIZE*INNER_SIZE*INNER_SIZE));
    }

    if(get_voxel(voxels_data, worldPos) > 0) {
        //uint idx = threadIndex.x + threadIndex.y*2 + threadIndex.z*4;
        primitiveCount += processVoxel(
            outMesh, worldPos, localPos, camera_data, voxels_data, light_data
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
    return float4(mix(input.tri.Color.rgb, float3(0.46, 0.32, 0.31), input.tri.Color.w * 0.5), 1.0);
    //return float4(float3(input.tri.Color.w), 1.0);
}

void putVoxel(device Voxels_Data* sv, uint3 pos) {
    uint64_t chunk = sv->chunks[pos.x / INNER_SIZE][pos.y / INNER_SIZE][pos.z / INNER_SIZE] | (1 << uint64_t((pos.x % INNER_SIZE)+(pos.y%INNER_SIZE)*INNER_SIZE+(pos.z%INNER_SIZE)*INNER_SIZE*INNER_SIZE));
    sv->chunks[pos.x / INNER_SIZE][pos.y / INNER_SIZE][pos.z / INNER_SIZE] = chunk;

    uint3 partitionContentSize = INNER_SIZE * uint3(PARTITION_SIZE_W,PARTITION_SIZE_H,PARTITION_SIZE_W);
    uint3 partitionPos = pos / partitionContentSize;
    sv->partitions[partitionPos.x][partitionPos.y][partitionPos.z] = 1;
}

uint64_t get_voxel_from_chunk_device(device Voxels_Data*  voxels_data, uint3 upos, uint64_t chunk) {
    uint64_t tag = uint64_t(1) << uint64_t((upos.x % INNER_SIZE) + (upos.y % INNER_SIZE)*INNER_SIZE + (upos.z % INNER_SIZE)*INNER_SIZE*INNER_SIZE);
    return tag & chunk;
}
// For now it's a direct access but later on we want to replace this with an Octree acceleration structure
uint64_t get_voxel_device(device Voxels_Data*  voxels_data, uint3 upos) {
    // The swapped palces between z and y is on purpose
    uint64_t chunk = voxels_data->chunks[upos.x/INNER_SIZE][upos.y/INNER_SIZE][upos.z/INNER_SIZE];
    return get_voxel_from_chunk_device(voxels_data, upos, chunk);
}


void bakeLightRay(device Voxels_Data* voxels_data, device Light_Data* light_data, uint3 from, float3 dir, uint count)
{
    int3 f = int3(from);
    float m = max3(abs(dir.x), abs(dir.y), abs(dir.z));
    float st = 1.0 / m;
    float3 step = dir * st;
    uint maxY =  CHUNK_H*INNER_SIZE;
    uint maxW =  CHUNK_W*INNER_SIZE;
    bool should_set_shadow = false;

    uint i = 1;
    for(; i < count; i++) {
        uint3 next = uint3(f - int3(trunc(step * i)));
        if(next.x >= maxW || next.y >= maxY || next.z >= maxW) {
            break;
        }
        uint64_t chunk = voxels_data->chunks[next.x/INNER_SIZE][next.y/INNER_SIZE][next.z/INNER_SIZE];
        if(chunk == 0) {
            
            if(voxels_data->partitions[next.x/PARTITION_SIZE_W][next.y/PARTITION_SIZE_H][next.z/PARTITION_SIZE_W] == 0) {
                uint3 c = min3(next.x/PARTITION_SIZE_W, next.y/PARTITION_SIZE_H, next.z/PARTITION_SIZE_W);
            }

            uint3 prev = uint3(next.x/INNER_SIZE, next.y/INNER_SIZE, next.z/INNER_SIZE);
            uint k = i + 1;
            for(; ;k++){
                next = uint3(f - int3(trunc(step * k)));
                uint3 c = min3(next.x/INNER_SIZE, next.y/INNER_SIZE, next.z/INNER_SIZE);
                if(c.x != prev.x || c.y != prev.y || c.z != prev.z) {
                    i = k - 1;
                    should_set_shadow = true;
                    break;
                }
            }
            continue;
        }

        if(get_voxel_from_chunk_device(voxels_data, next, chunk) > 0) {
            should_set_shadow = true;
            break;
        }
    }

    if(should_set_shadow) {
        for(; i < count; i++) {
            uint3 next = uint3(f - int3(trunc(step * i)));
            if(next.x > maxW || next.y > maxY || next.z > maxW || next.x <= 0 || next.z <= 0 || next.y <= 0) {
                break;
            }

            light_data->chunks[next.x][next.y][next.z] = half(1.0);
        }
    }
}


kernel void compute(
    constant Camera_Data&  camera_data   [[buffer(0)]],
    device Voxels_Data*    voxels_data [[buffer(1)]],
    device Light_Data*     light_data    [[buffer(2)]],
    uint2 global [[threadgroup_position_in_grid]],
    uint2 local [[thread_position_in_threadgroup]]
) {
    uint parts = CHUNK_W / 8;
    uint temporalSteps = 8;
    for(uint x = 0; x < parts*INNER_SIZE;x++) {
        for(uint z = 0; z < INNER_SIZE;z++) {
            uint3 pos = uint3(x + global.x * parts*INNER_SIZE, CHUNK_H*INNER_SIZE - 1, z + global.y*INNER_SIZE + camera_data.step*INNER_SIZE*temporalSteps);
            bakeLightRay(voxels_data, light_data, pos, camera_data.sun.xyz, CHUNK_H*INNER_SIZE*2);
        }
    }
}