#version 450
#include "camera.glsl"
layout(location = 0) in vec3 begin;
layout(location = 1) in vec3 beginLow;
layout(location = 2) in vec3 end;
layout(location = 3) in vec3 endLow;
layout(location = 4) in vec3 stroke; // endpoint [0,1], side [-1,1], boundary
layout(location = 0) out vec3 color;

bool clipPlane(vec4 plane, inout vec3 a, inout vec3 b) {
  float da = dot(plane, vec4(a,1.0));
  float db = dot(plane, vec4(b,1.0));
  if (da < 0.0 && db < 0.0) return false;
  if ((da < 0.0) != (db < 0.0)) {
    vec3 p = mix(a,b,da/(da-db));
    if (da < 0.0) a = p; else b = p;
  }
  return true;
}
void main() {
  vec3 a = cameraPoint(begin,beginLow), b = cameraPoint(end,endLow);
  vec2 halfSize = (camera.viewport.xy+vec2(2.0))/(2.0*camera.viewport.z);
  bool visible = clipPlane(vec4(0,1,0,-1e-6), a,b);
  visible = clipPlane(vec4(1,halfSize.x,0,0),a,b) && visible;
  visible = clipPlane(vec4(-1,halfSize.x,0,0),a,b) && visible;
  visible = clipPlane(vec4(0,halfSize.y,1,0),a,b) && visible;
  visible = clipPlane(vec4(0,halfSize.y,-1,0),a,b) && visible;
  if (!visible) { gl_Position = vec4(2,2,2,1); color=vec3(0); return; }
  vec4 pa = projectPoint(a), pb = projectPoint(b);
  vec2 delta = (pb.xy/pb.w-pa.xy/pa.w)*camera.viewport.xy;
  vec2 direction = delta/max(length(delta),1e-10);
  vec4 p = stroke.x < 0.5 ? pa : pb;
  // One logical pixel, independent of DPR, butt caps as Canvas.drawLine.
  p.xy += vec2(-direction.y,direction.x)*stroke.y/camera.viewport.xy*p.w;
  // Relative reverse-depth bias (about 8-16 float ULPs) rather than a constant depth
  // offset, which would pull distant hidden lines through nearer bodies.
  p.z *= 1.0000009536743164;
  gl_Position = p;
  color = stroke.z > 0.5 ? vec3(0) : vec3(244,67,54)/255.0; // Colors.red
}
