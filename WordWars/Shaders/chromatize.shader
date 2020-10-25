shader_type canvas_item;

uniform float offset;

void fragment(){
	vec4 greenv = texture( SCREEN_TEXTURE, SCREEN_UV ); //chromatic
	vec4 redv = texture( SCREEN_TEXTURE, vec2(SCREEN_UV.x + offset*SCREEN_PIXEL_SIZE.x, SCREEN_UV.y) );
	vec4 bluev = texture( SCREEN_TEXTURE, vec2(SCREEN_UV.x - offset*SCREEN_PIXEL_SIZE.x, SCREEN_UV.y) );
	COLOR = vec4( redv.r, greenv.g, bluev.b, 1f);
}