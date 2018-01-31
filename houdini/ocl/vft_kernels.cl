#include "vft_utils.h"
#include "vft_math.h"
#include "vft_fractals.h"

#define ORBITS_ARRAY_LENGTH    9

// dr -> de
// r -> distance
// Bailout -> max_distance
// Iterations -> max_iterations
static float hybrid(float3 P_in, const int max_iterations, const int max_distance, const float size, float* orbit_colors)
{
    P_in /= size;
    float3 Z = P_in;
    float de = 1.0;
    float distance;
    float out_de;
    int log_lin = 0; // positive is log, negative is lin

    float3 orbit_pt = (float3)(0,0,0);
    float orbit_pt_dist = 1e20f;

    float2 orbit_plane = (float2)(1,0);
    float3 orbit_plane_origin = (float3)(0);
    float3 orbit_plane_dist = (float3)(1e20f);

    float orbit_coord_dist = 1e20f;    

    for (int i = 0; i < max_iterations; i++)
    {
        distance = length(Z);
        if (distance > max_distance) break;
        
        //mandelbulbPower2Iter(&Z, &de, &P_in, &log_lin, 1.0f, (float4)(0,0.3,0.5,0.2)); // log
        //bristorbrotIter(&Z, &de, &P_in, &log_lin, 1.0f, (float4)(0,1.3,3.3,0)); // log
        //xenodreambuieIter(&Z, &de, &P_in, &log_lin, 1.0f, (float4)(1,1,0,0), 9, 0, 0); // log
        //mandelboxIter(&Z, &de, &P_in, &log_lin, 1.0f, (float4)(1,1,3,4), 3.0); // lin
        mandelbulbIter(&Z, &de, &P_in, &log_lin, 1.0f, (float4)(0,1,0,0), 8); // log
        //mengerSpongeIter(&Z, &de, &P_in, &log_lin, 1.0f, (float4)(1,0,1.0,0)); // lin
        //sierpinski3dIter(&Z, &de, &P_in, &log_lin, 1.0f, (float4)(0,0,0,0.5), 2.0, (float3)(1,1,1), (float3)(0,0,0) ); // lin

        orbit_pt_dist = min(orbit_pt_dist, length2(Z - orbit_pt));
        orbit_plane_dist.x = min( orbit_plane_dist.x, distPointPlane(Z, orbit_plane.xyy, orbit_plane_origin) );
        orbit_plane_dist.y = min( orbit_plane_dist.y, distPointPlane(Z, orbit_plane.yxy, orbit_plane_origin) );
        orbit_plane_dist.z = min( orbit_plane_dist.z, distPointPlane(Z, orbit_plane.yyx, orbit_plane_origin) );
        orbit_coord_dist = min( orbit_coord_dist, fabs(dot(Z, P_in)) );
    }

    orbit_colors[0] = sqrt(orbit_pt_dist); // point at specified coordinates
    orbit_colors[1] = orbit_plane_dist.x; // YZ plane
    orbit_colors[2] = orbit_plane_dist.y; // XZ plane
    orbit_colors[3] = orbit_plane_dist.z; // XY plane
    orbit_colors[4] = orbit_coord_dist; // dot(Z, world coords)

    if (log_lin >= 0) out_de = 0.5 * log(distance) * distance/de;
    else out_de = distance / de;

    return out_de * size;
}


//// scene setup

static float scene( float3 P, float frame, float* orbit_colors ) {
    float dist_out;

    float3 P_rep = P;

    //float3 P_rep = spaceRepFixed( P, (float3)(21), (float3)(2,3,4) );

    //float16 xform = mtxIdent();
    //xform = mtxMult( xform, mtxScale( (float3)(1/2.0,1,1) ) );
    //xform = mtxMult( xform, mtxRotate( (float3)(0,0,90) ) );
    //xform = mtxMult( xform, mtxTranslate( (float3)(0,-4,0) ) );
    //xform = mtxInvert(xform);
    //P_rep = mtxPtMult(xform, P_rep);

    float shape1 = hybrid(P_rep, 250, 100, 1.0, orbit_colors);

    dist_out = shape1; ////////

    return dist_out;
}

//// main function

kernel void marchPerspCam(
        float timeinc, float time, 
        int P_length, global float* P,
        int planeZ_length, global float* planeZ,
        int width_length, global float* width,
        int height_length, global float* height,
        int px_length, global float* px,
        int camXform_length, global float* camXform,
        int camPos_length, global float* camPos,
        int N_length, global float* N,
        int iRel_length, global float* iRel,
        int Cd_length, global float* Cd,
        int orbits_length, global int* orbits_index, global float* orbits
        )
{
    // get current point id
    const int idx = get_global_id(0);

    // if current point is not valid, then end
    if ( idx >= P_length ) return;

    // read in P attrib
    const float3 pixel_P_origin = vload3(idx, P);
    float3 pixel_P_world = pixel_P_origin;

    //// transforming to near img plane

    // move to near img plane
    pixel_P_world.z = planeZ[0];

    // compute scale of near img plane
    const float16 near_plane_scale = mtxScale( (float3)(width[0]-px[0], height[0]-px[0], 1) );

    // read in cam world matrix
    const float16 cam_xform_world = (float16)(camXform[0],camXform[1],camXform[2],camXform[3],
                                  camXform[4],camXform[5],camXform[6],camXform[7],
                                  camXform[8],camXform[9],camXform[10],camXform[11],
                                  camXform[12],camXform[13],camXform[14],camXform[15] );

    // create a mtx to hold transformations
    float16 near_plane_xform = mtxIdent();

    // apply transformations, also produce alternative matrix with scaled near plane
    near_plane_xform = mtxMult(near_plane_xform, near_plane_scale);
    float16 near_plane_xform_scaled = mtxMult(near_plane_xform, mtxScale( (float3)(100000) ) );
    near_plane_xform = mtxMult(near_plane_xform, cam_xform_world);
    near_plane_xform_scaled = mtxMult(near_plane_xform_scaled, cam_xform_world);

    // create a scaled near plane position for more accurate ray_dir calculation
    float3 pixel_P_world_scaled = mtxPtMult(near_plane_xform_scaled, pixel_P_world);

    // transform pixels into near img plane
    pixel_P_world = mtxPtMult(near_plane_xform, pixel_P_world);

    // get camera world space position and compute ray direction vector
    const float3 cam_P_world = (float3)(camPos[0], camPos[1], camPos[2]);
    const float3 ray_dir = normalize(pixel_P_world_scaled - cam_P_world);

    //// raymarching

    // raymarch settings
    float3 color = (float3)(0,0,0);    
    float orbit_colors[ORBITS_ARRAY_LENGTH];
    float orbit_colors_null[ORBITS_ARRAY_LENGTH];

    const float frame = time/timeinc + 1;

    float3 ray_P_world = pixel_P_world;
    float cam_dist = scene(cam_P_world, frame, orbit_colors_null);
    float de = 0;
    int i = 0;
    float step_size = 0.6f;
    float iso_limit_mult = 2.0f;
    float ray_dist = planeZ[0];
    const int max_steps = 1000;
    const float max_dist = 1000;

    //float4 scene_tmp;
    float16 scene_tmp;    

    float iso_limit = cam_dist * 0.0001 * iso_limit_mult;  

    // raymarch
    for (i=0; i<max_steps; i++)
    {
        de = scene(ray_P_world, frame, orbit_colors) * step_size;

        if ( de <= iso_limit || ray_dist >= max_dist )
        {
            break;
        }

        ray_dist += de;
        ray_P_world += ray_dir * de;
    }

    // relative amount of steps
    float i_rel = (float)(i)/(float)(max_steps);
    i_rel = 1-pow(i_rel, 1.0f/3.0f);

    // initialize variables
    float3 Cd_out = (float3)(1);
    float3 N_grad;

    // remove missed
    if ( de > iso_limit )
    {
        i_rel = -1;
    }
    else
    {
        // compute N
        float2 e2 = (float2)(1.0,-1.0) * iso_limit * 0.01f;
        N_grad = normalize( e2.xyy * scene( ray_P_world + e2.xyy, frame, orbit_colors_null) + 
                            e2.yyx * scene( ray_P_world + e2.yyx, frame, orbit_colors_null) + 
                            e2.yxy * scene( ray_P_world + e2.yxy, frame, orbit_colors_null) + 
                            e2.xxx * scene( ray_P_world + e2.xxx, frame, orbit_colors_null) );
        
        // Coloring
        float Cd_mix_N = 0.0f;
        float Cd_mix_orbit = 1.0f;
        float Cd_mix_AO = 0.8f;

        // AO
        float AO;
        float AO_occ = 0.0f;
        float AO_sca = 1.0f;

        for(int j=0; j<5; j++)
        {
            float AO_hr = 0.01f + 0.12f * (float)(j)/4.0f;
            float3 AO_pos =  N_grad * AO_hr + ray_P_world;
            float AO_dd = scene(AO_pos, frame, orbit_colors_null);
            AO_occ += -(AO_dd-AO_hr)*AO_sca;
            AO_sca *= 0.95f;
        }
        
        AO = clamp( 1.0f - 3.4f * AO_occ, 0.0f, 1.0f );
        AO = pow(AO, 0.8f);

        color.x = orbit_colors[1];
        color.y = orbit_colors[2];
        color.z = orbit_colors[3];
        color *= orbit_colors[0];

        color = fmod(color, (float3)(1));

        Cd_out = mix(Cd_out, Cd_out * fabs(N_grad), Cd_mix_N);
        Cd_out = mix(Cd_out, color, Cd_mix_orbit);
        Cd_out = mix(Cd_out, Cd_out * AO, Cd_mix_AO);

        // export attribs
        vstore3(ray_P_world, idx, P);
        vstore3(N_grad, idx, N);
        vstore3(Cd_out, idx, Cd);

        int orbits_idx_start = orbits_index[idx];
        int orbits_idx_end = orbits_idx_start + ORBITS_ARRAY_LENGTH;
        for (int j=orbits_idx_start; j<orbits_idx_end; j++)
        {
            orbits[j] = orbit_colors[j-orbits_idx_start];
        }
    }
    
    vstore1(i_rel, idx, iRel);

}







// testing new formulas

// amazing surf from M3D
// does nothing
static float amazingSurf(float3 P, float size)
{
//void AmazingSurfIteration(CVector4 &z, const sFractal *fractal, sExtendedAux &aux)
//{
//    // update aux.actualScale
//    aux.actualScale =
//        fractal->mandelbox.scale + fractal->mandelboxVary4D.scaleVary * (fabs(aux.actualScale) - 1.0);

//    CVector4 c = aux.const_c;
//    z.x = fabs(z.x + fractal->transformCommon.additionConstant111.x)
//                - fabs(z.x - fractal->transformCommon.additionConstant111.x) - z.x;
//    z.y = fabs(z.y + fractal->transformCommon.additionConstant111.y)
//                - fabs(z.y - fractal->transformCommon.additionConstant111.y) - z.y;
//    // no z fold

//    double rr = z.Dot(z);
//    if (fractal->transformCommon.functionEnabledFalse) // force cylinder fold
//        rr -= z.z * z.z;

//    double sqrtMinR = sqrt(fractal->transformCommon.minR05);
//    double dividend = rr < sqrtMinR ? sqrtMinR : min(rr, 1.0);

//    // use aux.actualScale
//    double m = aux.actualScale / dividend;

//    z *= (m - 1.0) * fractal->transformCommon.scale1 + 1.0;
//    // z *= m * fractal->transformCommon.scale1 + 1.0 * (1.0 - fractal->transformCommon.scale1);
//    aux.DE = aux.DE * fabs(m) + 1.0;

//    if (fractal->transformCommon.addCpixelEnabledFalse)
//        z += CVector4(c.y, c.x, c.z, c.w) * fractal->transformCommon.constantMultiplier111;

//    z = fractal->transformCommon.rotationMatrix.RotateVector(z);
//}
    //P /= size;
    float3 z = P;
    float dr = 1.0;
    int Iterations = 10;
    //int Bailout = 6;

    float actualScale = 1.39;
    float scaleVary = 0;
    float2 fold = (float2)(1.076562, 1.05);
    float minRad = 0.18;
    float scaleInf = 1;
    float auxScale = 1;

    for (int i = 0; i < Iterations ; i++)
    {
        //update aux.actualScale
        actualScale = actualScale + scaleVary * (fabs(actualScale) - 1.0f);
    
        //CVector4 c = aux.const_c;
        z.x = fabs(z.x + fold.x) - fabs(z.x - fold.x) - z.x;
        z.y = fabs(z.y + fold.y) - fabs(z.y - fold.y) - z.y;
        // no z fold
    
        float rr = z.x*z.x + z.y*z.y + z.z*z.z;
        //if (fractal->transformCommon.functionEnabledFalse) // force cylinder fold
        //    rr -= z.z * z.z;
    
        float sqrtMinR = sqrt(minRad);
        float dividend = rr < sqrtMinR ? sqrtMinR : min(rr, 1.0f);
    
        // use aux.actualScale
        //float m = auxScale / dividend;
        float m = actualScale / dividend;
    
        z *= (m - 1.0f) * scaleInf + 1.0f;
        dr = dr * fabs(m) + 1.0;
    
        //if (fractal->transformCommon.addCpixelEnabledFalse)
        //    z += CVector4(c.y, c.x, c.z, c.w) * fractal->transformCommon.constantMultiplier111;
    
        //z = fractal->transformCommon.rotationMatrix.RotateVector(z);
        float16 rotMtx = mtxRotate( (float3)(8.414060, 3.340000, 18.125000) );
        //z = mtxPtMult(rotMtx, z);

        z += P;
    }

    //float out = 0.5 * log(r) * r/dr;
    //return out * size;
    return dr;
}

// quaternion fractals, kind of works, but not sure what to do with z.w component :)
static float quaternion(float3 P, float size)
{
//void QuaternionIteration(CVector4 &z, const sFractal *fractal, sExtendedAux &aux)
//{
//    Q_UNUSED(fractal);

//    aux.r_dz = aux.r_dz * 2.0 * aux.r;
//    double newx = z.x * z.x - z.y * z.y - z.z * z.z - z.w * z.w;
//    double newy = 2.0 * z.x * z.y;
//    double newz = 2.0 * z.x * z.z;
//    double neww = 2.0 * z.x * z.w;
//    z.x = newx;
//    z.y = newy;
//    z.z = newz;
//    z.w = neww;
//}
    P /= size;

    float4 z = (float4)(P, 1);
    float dr = 1.0;
    float r = 0.0;
    int Iterations = 50;
    int Bailout = 40;

    for (int i = 0; i < Iterations ; i++)
    {
        r = length(z);
        if (r > Bailout) break;

        dr = dr * 2.0f * r;
        float newx = z.x * z.x - z.y * z.y - z.z * z.z - z.w * z.w;
        float newy = 2.0f * z.x * z.y;
        float newz = 2.0f * z.x * z.z;
        float neww = 2.0f * z.x * z.w;
        z.x = newx;
        z.y = newy;
        z.z = newz;
        //z.w = neww;
    }

    float out = 0.5f * log(r) * r/dr;
    return out * size;
}

// quaternion3d
// kind of works, but does not exactly match M2 visual, but parameters deform it in a similar manner, I hardcoded some of the parameters into values, there are some buggy areas, missing parts, noisy normals etc.
static float quaternion3d(float3 P, float size)
{
//void Quaternion3dIteration(CVector4 &z, const sFractal *fractal, sExtendedAux &aux)
//{
//
//    aux.r_dz = aux.r_dz * 2.0 * aux.r;
//    z = CVector4(z.x * z.x - z.y * z.y - z.z * z.z, z.x * z.y, z.x * z.z, z.w);
//
//    double tempL = z.Length();
//    z *= fractal->transformCommon.constantMultiplier122;
//    // if (tempL < 1e-21) tempL = 1e-21;
//    CVector4 tempAvgScale = CVector4(z.x, z.y / 2.0, z.z / 2.0, z.w);
//    double avgScale = tempAvgScale.Length() / tempL;
//    double tempAux = aux.r_dz * avgScale;
//    aux.r_dz = aux.r_dz + (tempAux - aux.r_dz) * fractal->transformCommon.scaleA1;
//
//    if (fractal->transformCommon.rotationEnabled)
//        z = fractal->transformCommon.rotationMatrix.RotateVector(z);
//
//    z += fractal->transformCommon.additionConstant000;
//}
    P /= size;

    float4 z = (float4)(P, 1);
    float dr = 1.0;
    float r = 0.0;
    int Iterations = 250;
    int Bailout = 20;

    for (int i = 0; i < Iterations ; i++)
    {
        r = length(z);
        if (r > Bailout) break;
        
        dr = dr * 2.0 * r;
        z = (float4)(z.x * z.x - z.y * z.y - z.z * z.z, z.x * z.y, z.x * z.z, z.w);

        float tempL = r;
        z *= (float4)(1,1,1,1);

        float4 tempAvgScale = (float4)(z.x, z.y / 2.0, z.z / 2.0, z.w);
        float avgScale = length(tempAvgScale) / tempL;
        float tempAux = dr * avgScale;
        dr = dr + (tempAux - dr) * 1.0f;

        //if (fractal->transformCommon.rotationEnabled)
        //    z = fractal->transformCommon.rotationMatrix.RotateVector(z);

        z += (float4)(0,0,0,0);
    }

    //float out = 0.5f * log(r) * r/dr;
    float out = r / dr;
    return out * size;
}

