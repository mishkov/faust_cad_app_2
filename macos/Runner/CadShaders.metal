#include <metal_stdlib>
using namespace metal;
struct Uniforms { float4 eyeHi, eyeLo, rotation, viewport, options; };
struct Body { packed_float3 hi,lo,normal; float unused,face,facing; };
struct Line { packed_float3 aHi,aLo,bHi,bLo; packed_float3 corner; };
struct Out {
  float4 position [[position]];
  float4 color [[center_no_perspective]];
};
float3 rotate(float3 p,constant Uniforms& u) {
  float x=p.x*u.rotation.x-p.y*u.rotation.y;
  float y=p.x*u.rotation.y+p.y*u.rotation.x;
  return float3(x,y*u.rotation.z-p.z*u.rotation.w,y*u.rotation.w+p.z*u.rotation.z);
}
float3 camera(float3 hi,float3 lo,constant Uniforms& u) {
  return rotate((hi-u.eyeHi.xyz)+(lo-u.eyeLo.xyz),u);
}
float4 project(float3 p,constant Uniforms& u) {
  return float4(2*u.viewport.z*p.x/u.viewport.x,2*u.viewport.z*p.z/u.viewport.y,u.options.y,p.y);
}
vertex Out cadBody(uint id [[vertex_id]],device const Body* v [[buffer(0)]],
  constant Uniforms& u [[buffer(1)]],device const uint* selected [[buffer(2)]]) {
  Body b=v[id];
  float3 p=u.options.x>0 ? float3(b.hi) : camera(b.hi,b.lo,u);
  float3 n=normalize(float3(b.normal));
  float facing=b.facing;
  if(facing==0) facing=dot(n,(float3(b.hi)-u.eyeHi.xyz)+(float3(b.lo)-u.eyeLo.xyz))>0 ? -1 : 1;
  n=rotate(n,u)*facing;
  float gray=round(255*(.32f+.5f*max(0.f,dot(n,normalize(float3(.55f,-.65f,.8f))))));
  float3 rgb=float3(gray)/255;
  if(b.face>=0 && selected[uint(b.face)]!=0) rgb=float3(floor(gray/2),gray,255)/255;
  if(b.face<0) {
    float4 clip=project(p,u); clip.z=min(clip.w,clip.z*(1+0x1p-20f));
    return {clip,float4(float3(33,150,243)/255*.1f,.1f)};
  }
  return {project(p,u),float4(rgb,1)};
}
fragment float4 cadFill(Out in [[stage_in]]) { return in.color; }
struct LineOut {
  float4 position [[position]];
  float4 color [[flat]];
  float4 distances [[center_no_perspective]];
};
vertex LineOut cadLine(uint id [[vertex_id]],device const Line* lines [[buffer(0)]],constant Uniforms& u [[buffer(1)]]) {
  Line l=lines[id];
  float3 a=camera(l.aHi,l.aLo,u),b=camera(l.bHi,l.bLo,u);
  float halfW=u.viewport.x/(2*u.viewport.z),halfH=u.viewport.y/(2*u.viewport.z);
  float3 planes[5]={float3(0,1,0),float3(1,halfW,0),float3(-1,halfW,0),float3(0,halfH,1),float3(0,halfH,-1)};
  bool rejected=false;
  for(int i=0;i<5;i++) {
    float offset=i==0 ? 1e-6f : 0.f;
    float da=dot(planes[i],a)-offset, db=dot(planes[i],b)-offset;
    if(da<0 && db<0) { rejected=true; break; }
    if((da<0)!=(db<0)) { float3 c=mix(a,b,da/(da-db)); if(da<0) a=c; else b=c; }
  }
  if(rejected) return {float4(0,0,-1,1),float4(0),float4(0)};
  float4 ca=project(a,u),cb=project(b,u);
  float2 pa=ca.xy/ca.w*u.viewport.xy*.5f,pb=cb.xy/cb.w*u.viewport.xy*.5f;
  float2 delta=pb-pa;
  float lengthLogical=length(delta);
  if(lengthLogical<1e-8f) return {float4(0,0,-1,1),float4(0),float4(0)};
  float2 tangent=delta/lengthLogical,normal=float2(-tangent.y,tangent.x);
  float halfPhysical=(l.corner.z==2 ? 1.f : .5f)*u.viewport.w;
  float inflate=(halfPhysical+1)/u.viewport.w;
  float t=l.corner.x,side=l.corner.y;
  float4 clip=mix(ca,cb,t);
  float2 pixel=mix(pa,pb,t)+normal*side*inflate+tangent*(t*2-1)/u.viewport.w;
  clip.xy=pixel*2/u.viewport.xy*clip.w;
  clip.z=min(clip.w,clip.z*(1+0x1p-20f));
  float3 color=l.corner.z==2 ? float3(33,150,243)/255 :
    (l.corner.z==0 || u.options.z>0 ? float3(244,67,54)/255 : float3(0));
  return {clip,float4(color,1),float4(side*(halfPhysical+1),mix(-1.f,lengthLogical*u.viewport.w+1,t),lengthLogical*u.viewport.w,halfPhysical)};
}
fragment float4 cadStroke(LineOut in [[stage_in]]) {
  float alpha=clamp(in.distances.w+.5f-abs(in.distances.x),0.f,1.f)*clamp(.5f+min(in.distances.y,in.distances.z-in.distances.y),0.f,1.f);
  return float4(in.color.rgb*alpha,alpha);
}
