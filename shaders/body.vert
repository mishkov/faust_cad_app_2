#version 450
#include "camera.glsl"
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 positionLow;
layout(location = 2) in vec3 normal;
layout(location = 3) in vec2 faceInfo; // selected, source face identifier
layout(location = 0) out vec4 color;
void main() {
  vec3 p = cameraPoint(position, positionLow);
  vec3 n = normalize(cameraDirection(normal));
  // Test facing before the float camera rotation; on a plane through the eye,
  // rotating first loses the small signed distance to cancellation.
  vec3 relativeWorld = (position-camera.eye.xyz)+(positionLow-camera.eyeLow.xyz);
  if (dot(normal, relativeWorld) > 0.0) n = -n;
  float gray = round(255.0*(0.32+0.5*max(0.0,
      dot(n, normalize(vec3(0.55, -0.65, 0.8))))));
  vec3 lit = faceInfo.x > 0.5 ? vec3(floor(gray/2.0), gray, 255.0)/255.0
                           : vec3(gray/255.0);
  gl_Position = projectPoint(p);
  // Reconstruct screen-linear interpolation without noperspective, which
  // crashes this SDK compiler while it emits the bundled GLES variant.
  color = vec4(lit*gl_Position.w, gl_Position.w);
}
