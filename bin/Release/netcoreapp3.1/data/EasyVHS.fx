#include "ReShade.fxh"

uniform float EVHS_PixelSize <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 10.0;
	ui_label = "Pixel Size [EasyVHS]";
> = 3.0;

uniform float EVHS_CRTFade <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "CRT Fade [EasyVHS]";
> = 0.0;

uniform float EVHS_Brightness <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Brightness [EasyVHS]";
> = 0.0;

uniform float EVHS_YFrequency <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 10.0;
	ui_label = "Y Frequency [EasyVHS]";
> = 6.0;

uniform float EVHS_IFrequency <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 10.0;
	ui_label = "I Frequency [EasyVHS]";
> = 1.2;

uniform float EVHS_QFrequency <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 10.0;
	ui_label = "Q Frequency [EasyVHS]";
> = 0.6;

uniform float EVHS_distortionStrength <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Distortion Strength [EasyVHS]";
> = 0.5;

uniform float EVHS_fisheyeStrength <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Fisheye Strength [EasyVHS]";
> = 0.5;

uniform float EVHS_stripesStrength <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Scanlines Strength [EasyVHS]";
> = 0.5;

uniform float EVHS_noiseStrength <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Noise Strength [EasyVHS]";
> = 0.5;

uniform float EVHS_vignetteStrength <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Vignette Strength [EasyVHS]";
> = 0.5;

uniform bool EVHS_VHSScanlines <
	ui_type = "boolean";
	ui_label = "VHS Scanlines [EasyVHS]";
> = false;

uniform float EVHS_blurAmount <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 10.0;
	ui_label = "Blur Amount [EasyVHS]";
> = 1.0;

uniform float EVHS_channelDif <
	ui_type = "drag";
	ui_min = 1.0;
	ui_max = 10.0;
	ui_label = "Channel Difference [EasyVHS]";
> = 4.0;

uniform float time < source = "timer"; >;

texture2D EVHS_NoiseTexture <source="evhs_noise.jpg";> { Width=512; Height=512;};
sampler2D EVHS_NoiseTex { Texture=EVHS_NoiseTexture; MinFilter=LINEAR; MagFilter=LINEAR; };

//Constants and useful shit
float fmod(float a, float b) {
	float c = frac(abs(a / b)) * abs(b);
	return a < 0 ? -c : c;
}

uniform int random < source = "random"; min = 0; max = 23; >;

float4 PS_EVHSBlur(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
	float4 col = tex2D(ReShade::BackBuffer, uv);

	// blur amount transformed into texel space
	float blurH = EVHS_blurAmount / ReShade::ScreenSize.y;
	float blurV = EVHS_blurAmount / ReShade::ScreenSize.x;

	// Kernel
	float2 offsets[8] = 
	{
		float2(blurH, 0),
		float2(-blurH, 0),
		float2(0, blurV),
		float2(0, -blurV),
		float2(blurH, blurV),
		float2(blurH, -blurV),
		float2(-blurH, blurV),
		float2(-blurH, -blurV),
	};

	float4 samples[8];
	float4 samplesRed[8];
	for (int ii = 0; ii < 8; ii++)
	{
		samples[ii] = tex2D(ReShade::BackBuffer, uv + offsets[ii]);
		samplesRed[ii] = tex2D(ReShade::BackBuffer, uv - offsets[ii]-float2((0)/ReShade::ScreenSize.x, 0.0));

		col.r += samplesRed[ii].r;
		col.gb += samples[ii].gb;
	}

	col /= 9.0;

	return col;
}

float onOff(float a, float b, float c)
{
	float4 _Time = float4(time*0.001/20, time*0.001, time*0.001*2, time*0.001*3);
	//Scale time for better looking distortion
	float time = _Time * 16;
	return step(c, sin(time + a*cos(time*b)));
}

float3 getVideo(float2 uv)
{
	float4 _Time = float4(time*0.001/20, time*0.001, time*0.001*2, time*0.001*3);
	float2 olduv = uv;

	//Scale time for better looking distortion
	float time = _Time * 16;
	float2 look = uv;
	float window = 1./(1.+20.*(look.y-fmod(time/4.,1.))*(look.y-fmod(time/4.,1.)));
	look.x = look.x + sin(look.y*10. + time)/50.*onOff(4.,4.,.3)*(1.+cos(time*80.))*window;
	float vShift = onOff(2.,3.,.9)*(sin(time)*sin(time*20.) + 
													 (0.5 + 0.1*sin(time*200.)*cos(time)));
	look.y = fmod(look.y + vShift, 1.);

	look = lerp(olduv, look, EVHS_distortionStrength);

	float3 video = float3(tex2D(ReShade::BackBuffer, look).xyz);

	return video;
}

float4 PS_EVHSTVDist(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
	float4 _Time = float4(time*0.001/20, time*0.001, time*0.001*2, time*0.001*3);
	//Apply TV distortion
	float xScanline;
	float yScanline;
	
	yScanline += _Time * 0.1f;
	xScanline -= _Time * 0.1f;

	//VHS scanlines
	

	//TV screen distortion
	//uv = screenDistort(uv);
	float3 video = getVideo(uv);
	//float vigAmt = EVHS_vignetteStrength*(3.+.3*sin(_Time + 5.*cos(_Time*5.)));
	//float vignette = (1.-vigAmt*(uv.y-.5)*(uv.y-.5))*(1.-vigAmt*(uv.x-.5)*(uv.x-.5));
	//video += EVHS_stripesStrength*stripes(uv);
	//video += EVHS_noiseStrength*noise(uv*2.)/2.;
	//video *= vignette;
	//video *= (12.+fmod(uv.y*30.+_Time,1.))/13.;

	float4 col=float4(video,1.0);

	return col;
}

technique EasyVHS_Blur
{
	pass EVHS_Blur
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_EVHSBlur;
	}
}

technique EasyVHS_TVDistortion
{
	pass EVHS_TVDist
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_EVHSTVDist;
	}
}