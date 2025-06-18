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

inline half2 domainWarp(half2 pos, half freqency, half speed, half amplitude, half time, int i)
{
    half2 offset = 0;
			    
    for (int j = 0; j < 2; j++)
    {
        half2 dir = randomDir(i * 10 + j); 
        half f = freqency * (1.0 + j * 0.4);
        half s = speed * (1.0 + j * 0.3);
        half a = amplitude / (j + 1.0);

        float phase = dot(pos, dir.xy) * f + time * s;
        offset += sin(phase) * dir.xy * a;
    }

    return offset;
}

void WaveDisplacement_half(half3 PositionWS, int WaveCount, half Frequency, half Speed, half Amplitude, half Time, out half3 Displacement)
{
    half d = 0.0;
    
    for (int i = 0; i < WaveCount; i++)
    {
        half2 warpedPos = PositionWS.xz + domainWarp(PositionWS.xz, Frequency, Speed, Amplitude, Time, i);
        half wavePhase = dot(warpedPos, randomDir(i));
        			
        half freq = Frequency * (1.0 + i * 0.5);
        half speed = Speed * (1.0 + i * 0.3);
        half amp = Amplitude / (i + 1);
        
        d += (exp(
            sin(wavePhase * freq + (Time + 0.1 * i) * speed)
        ) - 1) * amp;
    }

    Displacement = half3(0, d, 0);
}

void FDNormalDisplacement_half(half3 PositionWS, int WaveCount, half Frequency, half Speed, half Amplitude, half Time, out half3 normalOS)
{
    half delta = 0.0001;
    
    float3 posX = PositionWS + float3(delta, 0, 0);
    float3 posZ = PositionWS + float3(0, 0, delta);

    half dy_dx = 0.0;
    half dy_dz = 0.0;

    for (int i = 0; i < WaveCount; i++)
    {
        half2 dir = randomDir(i);
        half freq = Frequency * (1.0 + i * 0.5);
        half speed = Speed * (1.0 + i * 0.3);
        half amp = Amplitude / (i + 1);
        half t = Time * speed;

        half2 warpedX = posX.xz + domainWarp(posX.xz, Frequency, Speed, Amplitude, Time, i);
        half2 warpedZ = posZ.xz + domainWarp(posZ.xz, Frequency, Speed, Amplitude, Time, i);

        half waveX = dot(warpedX, dir.xy) * freq + t;
        half waveZ = dot(warpedZ, dir.xy) * freq + t;

        dy_dx += (exp(sin(waveX))) * cos(waveX) * amp * freq * dir.x;
        dy_dz += (exp(sin(waveZ))) * cos(waveZ) * amp * freq * dir.y;
    }
        					
    half3 tangentX = float3(1, dy_dx, 0);
    half3 tangentZ = float3(0, dy_dz, 1);
    normalOS = normalize(cross(tangentZ, tangentX));
}

void CDNormalDisplacement_half(half3 PositionOS, int WaveCount, half Frequency, half Speed, half Amplitude, half Time, out half3 normalOS)
{
    half delta = 0.001;

    float3 posXPlus  = PositionOS + float3( delta, 0, 0);
    float3 posXMinus = PositionOS + float3(-delta, 0, 0);
    float3 posZPlus  = PositionOS + float3(0, 0,  delta);
    float3 posZMinus = PositionOS + float3(0, 0, -delta);

    half dy_dx = 0.0;
    half dy_dz = 0.0;

    for (int i = 0; i < WaveCount; i++)
    {
        half2 dir = randomDir(i);
        half freq = Frequency * (1.0 + i * 0.5);
        half speed = Speed * (1.0 + i * 0.3);
        half amp = Amplitude / (i + 1);
        half t = Time * speed;

        // Domain warp positions
        half2 warpedXPlus  = posXPlus.xz  + domainWarp(posXPlus.xz,  Frequency, Speed, Amplitude, Time, i);
        half2 warpedXMinus = posXMinus.xz + domainWarp(posXMinus.xz, Frequency, Speed, Amplitude, Time, i);
        half2 warpedZPlus  = posZPlus.xz  + domainWarp(posZPlus.xz,  Frequency, Speed, Amplitude, Time, i);
        half2 warpedZMinus = posZMinus.xz + domainWarp(posZMinus.xz, Frequency, Speed, Amplitude, Time, i);

        // Wave phase for X and Z axis
        half waveXPlus  = dot(warpedXPlus,  dir.xy) * freq + t;
        half waveXMinus = dot(warpedXMinus, dir.xy) * freq + t;
        half waveZPlus  = dot(warpedZPlus,  dir.xy) * freq + t;
        half waveZMinus = dot(warpedZMinus, dir.xy) * freq + t;

        // Central difference derivative
        dy_dx += ((exp(sin(waveXPlus)) * cos(waveXPlus)) - (exp(sin(waveXMinus)) * cos(waveXMinus))) * amp * freq * dir.x / (2.0 * delta);
        dy_dz += ((exp(sin(waveZPlus)) * cos(waveZPlus)) - (exp(sin(waveZMinus)) * cos(waveZMinus))) * amp * freq * dir.y / (2.0 * delta);
    }

    half3 tangentX = float3(1, dy_dx, 0);
    half3 tangentZ = float3(0, dy_dz, 1);
    normalOS = normalize(cross(tangentZ, tangentX));
}
