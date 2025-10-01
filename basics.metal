#include <metal_stdlib>
using namespace metal;
// The minimunm distance a ray must travel before we consider an intersection.
// This is to prevent a ray from intersecting a surface it just bounced off of.
constant float c_minimumRayHitTime = 0.01f;

// after a hit, it moves the ray this far along the normal away from a surface.
// Helps prevent incorrect intersections when rays bounce off of objects.
constant float c_rayPosNormalNudge = 0.01f;

// the farthest we look for ray hits
constant float c_superFar = 10000.0f;

// number of ray bounces allowed
constant int c_numBounces = 8;

constant float c_pi = 3.14159265359f;
constant float c_twopi = 2.0f * c_pi;

struct RgnState {
    uint seed;
};

uint wang_hash(thread RgnState *state)
{
    state->seed = uint(state->seed ^ uint(61)) ^ uint(state->seed >> uint(16));
    state->seed *= uint(9);
    state->seed = state->seed ^ (state->seed >> 4);
    state->seed *= uint(0x27d4eb2d);
    state->seed = state->seed ^ (state->seed >> 15);
    return state->seed;
}

float RandomFloat01(thread RgnState *state)
{
    return float(wang_hash(state)) / 4294967296.0;
}

float3 RandomUnitVector(thread RgnState *state)
{
    float z = RandomFloat01(state) * 2.0f - 1.0f;
    float a = RandomFloat01(state) * c_twopi;
    float r = sqrt(1.0f - z * z);
    float x = r * cos(a);
    float y = r * sin(a);
    return float3(x, y, z);
}

struct SMaterialInfo {
    float percentSpecular; // 0..1
    float roughness; // 0..1
    float3 specularColor; // 0..1
    float3 albedo;
    float3 emissive;
};

struct SRayHitInfo
{
    float dist;
    float3 normal;
    SMaterialInfo material;
};

float3 LessThan(float3 f, float value)
{
    return float3(
        (f.x < value) ? 1.0f : 0.0f,
        (f.y < value) ? 1.0f : 0.0f,
        (f.z < value) ? 1.0f : 0.0f);
}
 
float3 LinearToSRGB(float3 rgb)
{
    rgb = clamp(rgb, 0.0f, 1.0f);
 
    return mix(
        pow(rgb, float3(1.0f / 2.4f)) * 1.055f - 0.055f,
        rgb * 12.92f,
        LessThan(rgb, 0.0031308f)
    );
}
 
float3 SRGBToLinear(float3 rgb)
{
    rgb = clamp(rgb, 0.0f, 1.0f);
 
    return mix(
        pow(((rgb + 0.055f) / 1.055f), float3(2.4f)),
        rgb / 12.92f,
        LessThan(rgb, 0.04045f)
    );
}

float3 ACESFilm(float3 x)
{
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return clamp((x*(a*x + b)) / (x*(c*x + d) + e), 0.0f, 1.0f);
}

float ScalarTriple(float3 u, float3 v, float3 w)
{
    return dot(cross(u, v), w);
}

bool TestQuadTrace(float3 rayPos, float3 rayDir, thread SRayHitInfo *info, float3 a, float3 b, float3 c, float3 d)
{
    // calculate normal and flip vertices order if needed
    float3 normal = normalize(cross(c-a, c-b));
    if (dot(normal, rayDir) > 0.0f)
    {
        normal *= -1.0f;
        
		float3 temp = d;
        d = a;
        a = temp;
        
        temp = b;
        b = c;
        c = temp;
    }
    
    float3 p = rayPos;
    float3 q = rayPos + rayDir;
    float3 pq = q - p;
    float3 pa = a - p;
    float3 pb = b - p;
    float3 pc = c - p;
    
    // determine which triangle to test against by testing against diagonal first
    float3 m = cross(pc, pq);
    float v = dot(pa, m);
    float3 intersectPos;
    if (v >= 0.0f)
    {
        // test against triangle a,b,c
        float u = -dot(pb, m);
        if (u < 0.0f) return false;
        float w = ScalarTriple(pq, pb, pa);
        if (w < 0.0f) return false;
        float denom = 1.0f / (u+v+w);
        u*=denom;
        v*=denom;
        w*=denom;
        intersectPos = u*a+v*b+w*c;
    }
    else
    {
        float3 pd = d - p;
        float u = dot(pd, m);
        if (u < 0.0f) return false;
        float w = ScalarTriple(pq, pa, pd);
        if (w < 0.0f) return false;
        v = -v;
        float denom = 1.0f / (u+v+w);
        u*=denom;
        v*=denom;
        w*=denom;
        intersectPos = u*a+v*d+w*c;
    }
    
    float dist;
    if (abs(rayDir.x) > 0.1f)
    {
        dist = (intersectPos.x - rayPos.x) / rayDir.x;
    }
    else if (abs(rayDir.y) > 0.1f)
    {
        dist = (intersectPos.y - rayPos.y) / rayDir.y;
    }
    else
    {
        dist = (intersectPos.z - rayPos.z) / rayDir.z;
    }
    
	if (dist > c_minimumRayHitTime && dist < info->dist)
    {
        info->dist = dist;        
        info->normal = normal;        
        return true;
    }    
    
    return false;
}

bool TestSphereTrace(float3 rayPos, float3 rayDir, thread SRayHitInfo *info, float4 sphere)
{
	//get the vector from the center of this sphere to where the ray begins.
	float3 m = rayPos - sphere.xyz;

    //get the dot product of the above vector and the ray's vector
	float b = dot(m, rayDir);

	float c = dot(m, m) - sphere.w * sphere.w;

	//exit if r's origoutside s (c > 0) and r pointing away from s (b > 0)
	if(c > 0.0 && b > 0.0)
		return false;

	//calculate discriminant
	float discr = b * b - c;

	//a negative discriminant corresponds to ray missing sphere
	if(discr < 0.0)
		return false;
    
	//ray now found to intersect sphere, compute smallest t value of intersection
    bool fromInside = false;
	float dist = -b - sqrt(discr);
    if (dist < 0.0f)
    {
        fromInside = true;
        dist = -b + sqrt(discr);
    }
    
	if (dist > c_minimumRayHitTime && dist < info->dist)
    {
        info->dist = dist;        
        info->normal = normalize((rayPos+rayDir*dist) - sphere.xyz) * (fromInside ? -1.0f : 1.0f);
        return true;
    }
    
    return false;
}