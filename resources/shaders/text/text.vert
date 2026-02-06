#version 450

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec2 texCoord;

layout(location = 0) out vec2 frag_tex_coord;

struct CharData {
    uint x;
    uint y;
    uint index;
};

layout(std140, binding = 1) uniform Characters {
    CharData glyph_data[100];
};

void main() {
    CharData glyph = glyph_data[gl_InstanceIndex];
    // glyph.x = gl_InstanceIndex % 10;
    // glyph.y = gl_InstanceIndex / 10;

    // scale position by 1/width, 1/height (cols/rows)
    vec2 scaled_pos = inPosition * vec2(0.1, 0.1);
    // move position so top-left is at position -1, -1
    vec2 tl_pos = scaled_pos - vec2(0.9, 0.9);
    // Finally, add x, y coords
    gl_Position = vec4(tl_pos + vec2(glyph.x * 0.2, glyph.y * 0.2), 0.0, 1.0);

    // calculate texture
    vec2 glyph_factor = vec2(1.0 / 30.0,  1.0 / 3.0);
    vec2 glyph_coord = vec2(float(glyph.index % 30), float (glyph.index / 30));

    frag_tex_coord = texCoord * glyph_factor +  glyph_coord * glyph_factor;
}
