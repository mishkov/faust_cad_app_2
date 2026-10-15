#version 450
layout(location = 0) in vec4 color;
layout(location = 0) out vec4 fragColor;
void main() { fragColor = vec4(color.xyz/color.w, 1.0); }
