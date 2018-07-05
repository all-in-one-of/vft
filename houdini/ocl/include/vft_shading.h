#ifndef VFT_SHADING
#define VFT_SHADING

#include "vft_defines.h"

float scene(float3, const int, float*, float3*);
static float length2(float3);
static float distPointPlane(float3, float3, float3);
float primitive_stack(float3, const int);
void fractal_stack(float3*, float*, const float3*, int*, const int);

////////////// shading functions

// compute Normals
// based on "Modeling with distance functions" article from Inigo Quilez
static float3 compute_N(const float* iso_limit, const float3* ray_P_world)
{
    float3 N_grad;
    float2 e = (float2)(1.0f, -1.0f) * (*iso_limit) * 0.01f;

    N_grad = normalize( e.xyy * scene( (*ray_P_world) + e.xyy, 0, NULL, NULL) + 
                        e.yyx * scene( (*ray_P_world) + e.yyx, 0, NULL, NULL) + 
                        e.yxy * scene( (*ray_P_world) + e.yxy, 0, NULL, NULL) + 
                        e.xxx * scene( (*ray_P_world) + e.xxx, 0, NULL, NULL) );
    return N_grad;
}

// compute Ambient Occlusion
// based on "Modeling with distance functions" article from Inigo Quilez
static float compute_AO(const float3* N, const float3* ray_P_world)
{
    float AO = 1.0f;
    float AO_occ = 0.0f;
    float AO_sca = 1.0f;

    #pragma unroll
    for(int j=0; j<5; j++)
    {
        float AO_hr = 0.01f + 0.12f * (float)(j)/4.0f;
        float3 AO_pos =  (*N) * AO_hr + (*ray_P_world);
        float AO_dd = scene(AO_pos, 0, NULL, NULL);
        AO_occ += -(AO_dd-AO_hr)*AO_sca;
        AO_sca *= 0.95f;
    }
    
    AO = clamp( 1.0f - 3.4f * AO_occ, 0.0f, 1.0f );
    AO = pow(AO, 1.6f);

    return AO;
}

// primitive shape function - calls respective parto of primitive_stack(), in case of DELTA DE mode also outputs N
static float primitive(float3 P, const float size, const int final, float* orbit_closest, float* orbit_colors, const float3 color, float3* N, const int stack)
{
    P /= size;
    float out_distance = primitive_stack(P, stack);

    if (final == 1 && out_distance <= *orbit_closest - ORBITS_OFFSET)
    {
        #pragma unroll
        for (int i=0; i<ORBITS_ARRAY_LENGTH; i++)
        {
            orbit_colors[i] = 1.0f;
        }
        orbit_colors[1] = color.x;
        orbit_colors[2] = color.y;
        orbit_colors[3] = color.z;

        #if ENABLE_DELTA_DE
            float iso_limit = 0.0001f;
            *N = compute_N(&iso_limit, &P);
        #endif
    }

    return out_distance * size;
}

// hybrid shape function - contains fractal loop, fractals combination is defined in fractals_stack(), in case of DELTA DE mode also outputs N
static float hybrid(float3 P_in, const int max_iterations, const float max_distance, const float size, const int final, float* orbit_closest, float* orbit_colors, float3* N, const int stack)
{
    P_in /= size;
    float3 Z = P_in;
    float de = 1.0f;
    float distance;
    float out_distance;
    int log_lin = 0;

    // init orbit traps variables
    float3 orbit_pt = (float3)(0.0f,0.0f,0.0f);
    float orbit_pt_dist = LARGE_NUMBER;
    float2 orbit_plane = (float2)(1.0f,0.0f);
    float3 orbit_plane_origin = (float3)(0.0f);
    float3 orbit_plane_dist = (float3)(LARGE_NUMBER);
    float orbit_coord_dist = LARGE_NUMBER;
    float orbit_sphere_rad = 1.0f;
    float orbit_sphere_dist = LARGE_NUMBER;
    float3 orbit_axis_dist = LARGE_NUMBER;

    // fractal loop
    int i = 0;
    #pragma unroll
    for (i = 0; i < max_iterations; i++)
    {
        distance = length(Z);
        if (distance > max_distance) break;
        
        fractal_stack(&Z, &de, &P_in, &log_lin, stack);

        // orbit traps calculations
        if (final == 1)
        {
            orbit_pt_dist = min(orbit_pt_dist, length2(Z - orbit_pt));
            orbit_plane_dist.x = min( orbit_plane_dist.x, distPointPlane(Z, orbit_plane.xyy, orbit_plane_origin) );
            orbit_plane_dist.y = min( orbit_plane_dist.y, distPointPlane(Z, orbit_plane.yxy, orbit_plane_origin) );
            orbit_plane_dist.z = min( orbit_plane_dist.z, distPointPlane(Z, orbit_plane.yyx, orbit_plane_origin) );
            orbit_coord_dist = min( orbit_coord_dist, fabs(dot(Z, P_in)) );
            orbit_sphere_dist = min( orbit_sphere_dist, length2(Z - normalize(Z)*orbit_sphere_rad) );
            orbit_axis_dist.x = min(orbit_axis_dist.x, Z.y*Z.y + Z.z*Z.z);
            orbit_axis_dist.y = min(orbit_axis_dist.y, Z.x*Z.x + Z.z*Z.z);
            orbit_axis_dist.z = min(orbit_axis_dist.z, Z.x*Z.x + Z.y*Z.y);
        }
    }
    distance = length(Z);

    // delta DE method
    // based on Makin/Buddhi 4-point Delta-DE formula
    #if ENABLE_DELTA_DE
        float delta = 0.000005f;

        Z = P_in + (float3)(delta, 0.0f, 0.0f);
        #pragma unroll
        for (int j=0; j<i; j++)
        {
            fractal_stack(&Z, &de, &P_in, &log_lin, stack);
        }
        float rx = length(Z);
        float drx = (distance - rx) / delta;

        Z = P_in + (float3)(0.0f, delta, 0.0f);

        #pragma unroll
        for (int j=0; j<i; j++)
        {
            fractal_stack(&Z, &de, &P_in, &log_lin, stack);
        }
        float ry = length(Z);
        float dry = (distance - ry) / delta;

        Z = P_in + (float3)(0.0f, 0.0f, delta);

        #pragma unroll
        for (int j=0; j<i; j++)
        {
            fractal_stack(&Z, &de, &P_in, &log_lin, stack);
        }
        float rz = length(Z);
        float drz = (distance - rz) / delta;

        float3 dist_grad = (float3)(drx, dry, drz);
        de = length(dist_grad);

        dist_grad = normalize(dist_grad);
    #endif

    // automatic determining DE mode based on log_lin value
    if (log_lin >= 0) out_distance = 0.5f * log(distance) * distance/de;
    else out_distance = distance / fabs(de);

    // outputting orbit traps (and N in case of DELTA DE mode) to the closest shape
    if (final == 1 && out_distance <= *orbit_closest)
    {
        orbit_colors[0] = sqrt(orbit_pt_dist); // distance to point at specified coordinates
        orbit_colors[1] = orbit_plane_dist.x; // distance to YZ plane
        orbit_colors[2] = orbit_plane_dist.y; // distance to XZ plane
        orbit_colors[3] = orbit_plane_dist.z; // distance to XY plane
        orbit_colors[4] = orbit_coord_dist; // dot(Z, world coords)
        orbit_colors[5] = sqrt(orbit_sphere_dist); // distance to sphere
        orbit_colors[6] = sqrt(orbit_axis_dist.x); // distance to X axis
        orbit_colors[7] = sqrt(orbit_axis_dist.y); // distance to Y axis
        orbit_colors[8] = sqrt(orbit_axis_dist.z); // distance to Z axis

        #if ENABLE_DELTA_DE
            *N = dist_grad;
        #endif
    }

    // change orbit_closest, if the evaluated point is closer to this shape
    *orbit_closest = min(*orbit_closest, out_distance * size);

    // output distance estimate, take shape's size into consideration
    return out_distance * size;
}

#endif