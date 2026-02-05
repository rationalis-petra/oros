#version 450

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec3 inColor;
layout(location = 2) in vec2 texCoord;

layout(location = 0) out vec3 fragColor;
layout(location = 1) out vec2 fragTexCoord;

void main() {
    gl_Position = vec4(inPosition, 0.0, 1.0);

    //uint glyph_index = glyph_indices[gl_InstanceIndex];
    uint glyph_index = 60;
    vec2 glyph_factor = vec2(1.0 / 30.0,  1.0 / 3.0);
    vec2 glyph_coord = vec2(float(glyph_index % 30), float (glyph_index / 30));

    fragColor = inColor;
    fragTexCoord = texCoord * glyph_factor +  glyph_coord * glyph_factor;
    //fragTexCoord = texCoord;
}
