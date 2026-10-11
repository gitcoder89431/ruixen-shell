// Preview image selection is independent of desktop selection.
function nextPreviewArtwork(currentBackground, entries) {
  currentBackground=String(currentBackground || "")
  entries=Array.isArray(entries) ? entries : []
  var currentName=currentBackground.substring(currentBackground.lastIndexOf("/")+1).replace(/\.[^.]+$/, "").toLowerCase()
  for(var i=0;i<entries.length;i++) {
    var entry=entries[i]
    if(!entry || entry.kind!=="image" || typeof entry.real!=="string" || !entry.real) continue
    var name=entry.real.substring(entry.real.lastIndexOf("/")+1).replace(/\.[^.]+$/, "").toLowerCase()
    if(entry.kind === "image" && entry.real !== currentBackground && (!currentName || (!name.endsWith(currentName) && !currentName.endsWith(name)))) return entry.real
  }
  return ""
}
