#version 440
// Matrix trail adapted from DasPoxy preview.frag (MIT; GLITCH-LICENSE.txt).
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
 mat4 qt_Matrix; float qt_Opacity; float time; vec2 resolution;
 float mode; float strength; vec4 tint;
};
float hash(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void main() {
 vec2 uv=qt_TexCoord0;
 if(mode<0.5) {
  float scan=.5+.5*sin(uv.y*resolution.y*3.14159265);
  float grille=mod(floor(uv.x*resolution.x),3.0);
  vec3 ink=grille<1.0?vec3(.25,0,0):grille<2.0?vec3(0,.25,0):vec3(0,0,.25);
  float alpha=strength*(.11+.22*scan+.15*dot(uv-.5,uv-.5));
  fragColor=vec4(ink*alpha,alpha)*qt_Opacity;
 } else {
  vec2 n=max(vec2(1),floor(resolution/vec2(13,20)));
  vec2 g=uv*n,cell=floor(g),f=fract(g);
  float head=fract(time*(.12+.3*hash(vec2(cell.x,1.3)))+hash(vec2(cell.x,9.1)));
  float trail=pow(1.0-smoothstep(0.0,.4,fract(head-cell.y/n.y)),2.0);
  // Procedural binary glyphs, no font atlas dependency.
  float digit=step(.5,hash(cell+floor(time*2.0)));
  float vertical=step(.32,f.x)*step(f.x,.68)*step(.15,f.y)*step(f.y,.85);
  float hollow=step(.42,f.x)*step(f.x,.58)*step(.27,f.y)*step(f.y,.73);
  float glyph=vertical*(1.0-hollow*(1.0-digit));
  float alpha=glyph*trail*strength*.55;
  fragColor=vec4(tint.rgb*alpha,alpha)*qt_Opacity;
 }
}
