layout(set = 0, binding = 0) uniform Camera {
  vec4 eye;
  vec4 eyeLow; // double-single translation preserves close views at world offsets
  vec4 rotation; // cos(-yaw), sin(-yaw), cos(-pitch), sin(-pitch)
  vec4 viewport; // logical width, height, focal length, DPR
} camera;

vec3 cameraDirection(vec3 p) {
  vec4 r = camera.rotation;
  vec3 yaw = vec3(p.x*r.x-p.y*r.y, p.x*r.y+p.y*r.x, p.z);
  return vec3(yaw.x, yaw.y*r.z-yaw.z*r.w, yaw.y*r.w+yaw.z*r.z);
}
vec3 cameraPoint(vec3 p, vec3 low) {
  return cameraDirection((p-camera.eye.xyz)+(low-camera.eyeLow.xyz));
}

// Infinite reverse Z. Metal clips to 0 <= z <= w. Keep the reference 1e-6
// near plane; float depth retains relative precision even at distant views.
vec4 projectPoint(vec3 p) {
  return vec4(2.0*camera.viewport.z*p.x/camera.viewport.x,
              2.0*camera.viewport.z*p.z/camera.viewport.y, 1e-6, p.y);
}
