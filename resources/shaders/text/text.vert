#version 450

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec2 texCoord;

layout(location = 0) out vec2 frag_tex_coord;

struct CharData {
    uint x;
    uint y;
    uint index;
};

layout(binding = 1) uniform Characters {
    CharData glyph_data[100];
};

void main() {
    CharData glyph = glyph_data[gl_InstanceIndex];

    // Calculate position
    gl_Position = vec4((inPosition + vec2(glyph.x, glyph.y)) * vec2(0.1, 0.1) - vec2(1.0, 1.0), 0.0, 1.0);

    // calculate texture
    vec2 glyph_factor = vec2(1.0 / 30.0,  1.0 / 3.0);
    vec2 glyph_coord = vec2(float(glyph.index % 30), float (glyph.index / 30));

    frag_tex_coord = texCoord * glyph_factor +  glyph_coord * glyph_factor;
}
