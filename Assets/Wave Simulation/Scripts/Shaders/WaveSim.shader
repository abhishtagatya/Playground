Shader "Playground/WaveSim"
{
    Properties
    {
    	[Header(Material Settings)]
    	[ToggleOff] _UsePBRLighting("PBR Lighting", Float) = 1.0
    	
        [MainColor] _BaseColor("Color", Color) = (0,0,1,1)
	    
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
    	_Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        _SpecColor("Specular", Color) = (0.2, 0.2, 0.2)
    	
    	[ToggleOff] _SpecularHighlights("Specular Highlights", Float) = 1.0
	    _EnvironmentReflections("Environment Reflections", Range(0.0, 1.0)) = 1.0
    	
    	_OcclusionStrength("Strength", Range(0.0, 1.0)) = 1.0
    	
    	[NoScaleOffset] _CustomReflection("Reflection Cubemap", CUBE) = "" {}
		_CustomReflection_HDR("HDR Decode Params", Vector) = (1, 1, 1, 1)
	    
    	[Header(Wave Settings)]
    	[KeywordEnum(Sine, Exponent)] _WaveFunc ("Wave Function", Int) = 0
    	
    	_WaveCount("Wave Count", Range(1.0, 64.0)) = 1.0
    	
	    _Frequency("Wave Frequency", Float) = 1.0
	    _Speed("Wave Speed", Float) = 1.0
	    _Amplitude("Wave Amplitude", Float) = 0.1
    	
    	[Header(Warp Settings)]
    	_WarpFrequency ("Warp Frequency", Float) = 0.5
		_WarpAmplitude ("Warp Amplitude", Float) = 0.2
		_WarpSpeed     ("Warp Speed", Float) = 0.3
    }
    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Transparent"
            "Queue"="Transparent"
            "UniversalMaterialType" = "Lit"
            "IgnoreProjector" = "True"
        }
        LOD 300
        
        Pass
        {
        	Name "ForwardLit"
        	
        	Tags
        	{
        		"LightMode" = "UniversalForward"
        	}
        	
        	Blend SrcAlpha OneMinusSrcAlpha
			ZWrite Off
        	
        	HLSLPROGRAM
        	#define _SPECULAR_COLOR
        	#pragma vertex Vertex
        	#pragma fragment Fragment
        	#pragma shader_feature _ _FORWARD_PLUS
        	#pragma shader_feature _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma shader_feature _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma shader_feature_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma shader_feature_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
        	#pragma multi_compile _WAVEFUNC_SINE _WAVEFUNC_EXPONENT
        	#pragma multi_compile_fog

        	#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        	#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        	#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
        	
        	CBUFFER_START(UnityPerMaterial)
        	// Lighting Parameters
        	half _UsePBRLighting;
        	half4 _BaseColor;
        	half _Smoothness;
        	half _Metallic;
        	half3 _SpecColor;
        	half _OcclusionStrength;

        	half _EnvironmentReflections;

        	// Wave Parameters
        	int _WaveCount;
			half _Frequency;
			half _Speed;
			half _Amplitude;

        	half _WarpFrequency;
        	half _WarpAmplitude;
        	half _WarpSpeed;
        	CBUFFER_END

        	TEXTURECUBE(_CustomReflection);
			SAMPLER(sampler_CustomReflection);
			half4 _CustomReflection_HDR; // Needed to decode HDR (exposure & bias)
        	
        	struct Attributes
        	{
        		half4 positionOS: POSITION;
        	};

        	struct Varyings
        	{
        		half4 positionCS: SV_POSITION;
        		half3 positionWS: TEXCOORD0;
        		half3 normalWS: TEXCOORD1;
        	};

        	inline half2 hash12(half n)
			{
			    half2 p = half2(n * 127.1h, n * 311.7h);
			    p = frac(sin(p) * 43758.5453h);
			    return p;
			}

        	inline half2 randomDir(int n)
			{
			    half2 h = hash12((half)n);
			    half angle = h.x * 6.2831853h; 
			    return half2(cos(angle), sin(angle));
			}

        	half2 domainWarp(half2 pos, int i)
			{
			    half2 offset = 0;
			    
			    for (int j = 0; j < 2; j++)
			    {
			        half2 dir = randomDir(i * 10 + j); 
			        half freq = _WarpFrequency * (1.0 + j * 0.4);
			        half speed = _WarpSpeed * (1.0 + j * 0.3);
			        half amp = _WarpAmplitude / (j + 1.0);

			        float phase = dot(pos, dir.xy) * freq + _Time.y * speed;
			        offset += sin(phase) * dir.xy * amp;
			    }

			    return offset;
			}

        	Varyings Vertex(Attributes input)
        	{
        		Varyings output;
        		
        		half displacement = 0.0;

        		for (int i = 0; i < _WaveCount; i++)
        		{
        			half2 warpedPos = input.positionOS.xz + domainWarp(input.positionOS.xz, i);
        			half wavePhase = dot(warpedPos, randomDir(i));
        			
        			half freq = _Frequency * (1.0 + i * 0.5);
        			half speed = _Speed * (1.0 + i * 0.3);
        			half amp = _Amplitude / (i + 1);

        			#ifdef _WAVEFUNC_SINE
        				displacement += sin(wavePhase * freq + (_Time.y + 0.1 * i) * speed) * amp;
        			#endif

        			#ifdef _WAVEFUNC_EXPONENT
        			    displacement += (exp(
        			    	sin(wavePhase * freq + (_Time.y + 0.1 * i) * speed)
        			    ) - 1) * amp;
        			#endif
        			
        		}

        		input.positionOS.y += displacement;

        		// Recalculate normal using numerical derivatives (central difference)
			    half delta = 0.001; // Smaller = more accurate, but watch performance
			    float3 posX = input.positionOS + float3(delta, 0, 0);
			    float3 posZ = input.positionOS + float3(0, 0, delta);

			    half dy_dx = 0.0;
			    half dy_dz = 0.0;

			    for (int i = 0; i < _WaveCount; i++)
			    {
			        half2 dir = randomDir(i);
			        half freq = _Frequency * (1.0 + i * 0.5);
			        half speed = _Speed * (1.0 + i * 0.3);
			        half amp = _Amplitude / (i + 1);
			        half t = _Time.y * speed;

			    	half2 warpedX = posX.xz + domainWarp(posX.xz, i);
					half2 warpedZ = posZ.xz + domainWarp(posZ.xz, i);

			    	#ifdef _WAVEFUNC_SINE
						dy_dx += cos(dot(warpedX, dir.xy) * freq + t) * freq * dir.x * amp;
						dy_dz += cos(dot(warpedZ, dir.xy) * freq + t) * freq * dir.y * amp;
			    	#endif

			    	#ifdef _WAVEFUNC_EXPONENT
						half waveX = dot(warpedX, dir.xy) * freq + t;
						half waveZ = dot(warpedZ, dir.xy) * freq + t;

						dy_dx += (exp(sin(waveX))) * cos(waveX) * amp * freq * dir.x;
						dy_dz += (exp(sin(waveZ))) * cos(waveZ) * amp * freq * dir.y;
			    	#endif
			    }
        					
			    half3 tangentX = float3(1, dy_dx, 0);
			    half3 tangentZ = float3(0, dy_dz, 1);
			    half3 normalOS = normalize(cross(tangentZ, tangentX));

                half3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                half3 normalWS = TransformObjectToWorldNormal(normalOS);

                output.positionWS = positionWS;
                output.normalWS = normalWS;
                output.positionCS = TransformWorldToHClip(positionWS);
                return output;
        	}

        	inline half3 DecodeHDREnvironment(half4 data, float4 decodeValues)
			{
			    return decodeValues.x * max(half3(0, 0, 0), data.rgb - decodeValues.yyy);
			}

        	half3 SampleReflection(half3 reflectDir, float roughness)
			{
			    float mip = roughness * 6.0;
			    half4 encoded = SAMPLE_TEXTURECUBE_LOD(_CustomReflection, sampler_CustomReflection, reflectDir, mip);
			    return DecodeHDREnvironment(encoded, _CustomReflection_HDR);
			}

        	half4 Fragment(Varyings input) : SV_Target
        	{
        		SurfaceData surfaceData = (SurfaceData)0;
                InputData inputData = (InputData)0;

                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalize(input.normalWS);
                inputData.viewDirectionWS = GetWorldSpaceViewDir(input.positionWS);
                inputData.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
        		
                surfaceData.albedo = _BaseColor.rgb;
                surfaceData.alpha = _BaseColor.a;
                surfaceData.metallic = _Metallic;
                surfaceData.smoothness = _Smoothness;
                surfaceData.occlusion = _OcclusionStrength;
                surfaceData.emission = 0;

        		 // Compute reflection direction
			    half3 viewDirWS = normalize(inputData.viewDirectionWS);
			    half3 normalWS = normalize(inputData.normalWS);
			    half3 reflectDirWS = reflect(-viewDirWS, normalWS);

        		half3 reflectionColor = SampleReflection(reflectDirWS, 1.0 - surfaceData.smoothness); // roughness = 1 - smoothness
        		surfaceData.emission += reflectionColor * _EnvironmentReflections; // scale to taste	
        		
        		half4 lit;
        		if (_UsePBRLighting)
        		{
        			lit = UniversalFragmentPBR(inputData, surfaceData);
        		}
        		else
        		{
        			lit = UniversalFragmentBlinnPhong(inputData, surfaceData);

        			lit.rgb += reflectionColor * _EnvironmentReflections; // manually add to final result
        			//lit.rgb += (unity_AmbientSky + unity_AmbientEquator + unity_AmbientGround) * 0.2;
        		}

        		return lit;
        	}
        	
        	ENDHLSL
        }
    }
}
