// Defensive rendering defaults for external/malformed state-file edits.
var effects = ["reveal","bleed","pixel-dissolve","iris","shutters","scanline","ink-spread","aurora","vortex","signal-tear","datamosh","vhs","code-bleed"]
function number(value, fallback, low, high) {
  return typeof value === "number" && isFinite(value) ? Math.max(low, Math.min(high, value)) : fallback
}
function normalize(value) {
  var c=value && typeof value==="object" && !Array.isArray(value) ? value : {}
  var options={}
  for(var i=9;i<effects.length;i++) {
    var entry=c.transitionOptions && c.transitionOptions[effects[i]]
    if(entry && typeof entry==="object") options[effects[i]]={strength:number(entry.strength,.65,0,1),density:number(entry.density,1,.5,2)}
  }
  return {
    version:1,
    transitionEffect:effects.indexOf(c.transitionEffect)>=0 ? c.transitionEffect : "reveal",
    transitionDurationMs:Math.round(number(c.transitionDurationMs,420,0,30000)),
    transitionSoftness:number(c.transitionSoftness,.02,.001,.5),
    ambientZoom:c.ambientZoom===true, ambientGlow:c.ambientGlow===true,
    disableMotion:c.disableMotion===true,
    backgroundEffect:["none","crt","matrix"].indexOf(c.backgroundEffect)>=0 ? c.backgroundEffect : "none",
    backgroundIntensity:number(c.backgroundIntensity,.25,0,1),
    backgroundSpeed:number(c.backgroundSpeed,1,.1,3), transitionOptions:options
  }
}
