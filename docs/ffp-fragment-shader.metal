#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct render_state_t
{
    packed_float3 fog_color;
    float fog_scale;
    float fog_end;
    float fog_density;
    float alpha_ref;
};

constant uint point_mode_tmp [[function_constant(1230)]];
constant uint point_mode = is_function_constant_defined(point_mode_tmp) ? point_mode_tmp : 0u;

struct D3D9FixedFunctionPS
{
    float4 textureFactor;
};

constant bool s0_bound_tmp [[function_constant(2)]];
constant bool s0_bound = is_function_constant_defined(s0_bound_tmp) ? s0_bound_tmp : true;
constant bool s1_bound_tmp [[function_constant(3)]];
constant bool s1_bound = is_function_constant_defined(s1_bound_tmp) ? s1_bound_tmp : true;
constant bool s2_bound_tmp [[function_constant(4)]];
constant bool s2_bound = is_function_constant_defined(s2_bound_tmp) ? s2_bound_tmp : true;
constant bool s3_bound_tmp [[function_constant(5)]];
constant bool s3_bound = is_function_constant_defined(s3_bound_tmp) ? s3_bound_tmp : true;
constant bool s4_bound_tmp [[function_constant(6)]];
constant bool s4_bound = is_function_constant_defined(s4_bound_tmp) ? s4_bound_tmp : true;
constant bool s5_bound_tmp [[function_constant(7)]];
constant bool s5_bound = is_function_constant_defined(s5_bound_tmp) ? s5_bound_tmp : true;
constant bool s6_bound_tmp [[function_constant(8)]];
constant bool s6_bound = is_function_constant_defined(s6_bound_tmp) ? s6_bound_tmp : true;
constant bool s7_bound_tmp [[function_constant(9)]];
constant bool s7_bound = is_function_constant_defined(s7_bound_tmp) ? s7_bound_tmp : true;

struct _95
{
    float4 _m0;
    float2 _m1;
    float2 _m2;
    float _m3;
    float _m4;
    float4 _m5;
    float2 _m6;
    float2 _m7;
    float _m8;
    float _m9;
    float4 _m10;
    float2 _m11;
    float2 _m12;
    float _m13;
    float _m14;
    float4 _m15;
    float2 _m16;
    float2 _m17;
    float _m18;
    float _m19;
    float4 _m20;
    float2 _m21;
    float2 _m22;
    float _m23;
    float _m24;
    float4 _m25;
    float2 _m26;
    float2 _m27;
    float _m28;
    float _m29;
    float4 _m30;
    float2 _m31;
    float2 _m32;
    float _m33;
    float _m34;
    float4 _m35;
    float2 _m36;
    float2 _m37;
    float _m38;
    float _m39;
};

constant uint pixel_fog_mode_tmp [[function_constant(1229)]];
constant uint pixel_fog_mode = is_function_constant_defined(pixel_fog_mode_tmp) ? pixel_fog_mode_tmp : 0u;
constant bool fog_enabled_tmp [[function_constant(1227)]];
constant bool fog_enabled = is_function_constant_defined(fog_enabled_tmp) ? fog_enabled_tmp : false;
constant uint alpha_func_tmp [[function_constant(1225)]];
constant uint alpha_func = is_function_constant_defined(alpha_func_tmp) ? alpha_func_tmp : 0u;

struct spvDescriptorSetBuffer0
{
    constant void* _m0_pad [[id(0)]];
    constant void* _m1_pad [[id(1)]];
    constant D3D9FixedFunctionPS* consts [[id(2)]];
};

struct main0_out
{
    float4 out_Color0 [[color(0)]];
    uint gl_SampleMask [[sample_mask]];
};

struct main0_in
{
    float4 in_Texcoord0 [[user(locn1)]];
    float4 in_Texcoord1 [[user(locn2)]];
    float4 in_Texcoord2 [[user(locn3)]];
    float4 in_Texcoord3 [[user(locn4)]];
    float4 in_Texcoord4 [[user(locn5)]];
    float4 in_Texcoord5 [[user(locn6)]];
    float4 in_Texcoord6 [[user(locn7)]];
    float4 in_Texcoord7 [[user(locn8)]];
    float4 in_Color0 [[user(locn9)]];
    float4 in_Color1 [[user(locn10)]];
    float in_Fog0 [[user(locn11)]];
};

fragment main0_out main0(main0_in in [[stage_in]], constant spvDescriptorSetBuffer0& spvDescriptorSet0 [[buffer(0)]], constant uint* spvDynamicOffsets [[buffer(30)]], constant render_state_t& render_state [[buffer(1)]], float2 gl_PointCoord [[point_coord]], float4 gl_FragCoord [[position]])
{
    constant auto& consts = *(constant D3D9FixedFunctionPS* )((constant char* )spvDescriptorSet0.consts + spvDynamicOffsets[0]);
    main0_out out = {};
    float4 _23 = float4(gl_PointCoord, 0.0, 0.0);
    bool4 _32 = bool4(extract_bits(point_mode, uint(1), uint(1)) == 1u);
    float4 _119 = in.in_Color0;
    if (fog_enabled)
    {
        float _123 = gl_FragCoord.z * (1.0 / gl_FragCoord.w);
        float _139;
        switch (pixel_fog_mode)
        {
            case 1u:
            {
                _139 = exp(-(_123 * render_state.fog_density));
                break;
            }
            case 2u:
            {
                float _132 = _123 * render_state.fog_density;
                _139 = exp(-(_132 * _132));
                break;
            }
            case 3u:
            {
                _139 = precise::clamp((render_state.fog_end - _123) * render_state.fog_scale, 0.0, 1.0);
                break;
            }
            default:
            {
                _139 = in.in_Fog0;
                break;
            }
        }
        float3 _142 = mix(float3(render_state.fog_color), in.in_Color0.xyz, float3(_139));
        _119 = float4(_142.x, _142.y, _142.z, in.in_Color0.w);
    }
    out.out_Color0 = _119;
    if (alpha_func != 7u)
    {
        bool _174;
        switch (alpha_func)
        {
            case 0u:
            {
                _174 = false;
                break;
            }
            case 1u:
            {
                _174 = out.out_Color0.w < render_state.alpha_ref;
                break;
            }
            case 2u:
            {
                _174 = out.out_Color0.w == render_state.alpha_ref;
                break;
            }
            case 3u:
            {
                _174 = out.out_Color0.w <= render_state.alpha_ref;
                break;
            }
            case 4u:
            {
                _174 = out.out_Color0.w > render_state.alpha_ref;
                break;
            }
            case 5u:
            {
                _174 = out.out_Color0.w != render_state.alpha_ref;
                break;
            }
            case 6u:
            {
                _174 = out.out_Color0.w >= render_state.alpha_ref;
                break;
            }
            default:
            {
                _174 = true;
                break;
            }
        }
        if (!_174)
        {
            discard_fragment();
        }
    }
    out.gl_SampleMask = 0xffff;
    return out;
}

