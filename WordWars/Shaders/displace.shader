shader_type canvas_item;

uniform vec2 center;
uniform float force;
uniform float size;
uniform float thickness;
uniform float offset;

void fragment(){
	float ratio = SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y;
	vec2 scaledUV = ( SCREEN_UV - vec2(0.5, 0.0) ) / vec2(ratio, 1.0) + vec2(0.5, 0.0);
	float mask =  ( 1.0 - smoothstep(size-0.1, size, length(scaledUV - center)) ) *
	  smoothstep(size-thickness-0.1, size-thickness, length(scaledUV - center));
	vec2 disp = normalize(scaledUV - center) * force * mask;
	vec2 dispUV = SCREEN_UV - disp;
	
//	COLOR = texture( SCREEN_TEXTURE, dispUV ); //Vanila
	
	vec4 greenv = texture( SCREEN_TEXTURE, dispUV ); //chromatic
	vec4 redv = texture( SCREEN_TEXTURE, vec2(dispUV.x + offset*SCREEN_PIXEL_SIZE.x, dispUV.y) );
	vec4 bluev = texture( SCREEN_TEXTURE, vec2(dispUV.x - offset*SCREEN_PIXEL_SIZE.x, dispUV.y) );
	COLOR = vec4( redv.r, greenv.g, bluev.b, 1f);
}