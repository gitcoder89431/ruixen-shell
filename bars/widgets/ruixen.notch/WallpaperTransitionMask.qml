import QtQuick

// Low-resolution alpha mask, shared by desktop transitions and hover previews.
// Only paints while a transition/preview is active; no idle render timer.
Item {
  id: root
  property string effect: "iris"
  property real progress: 0
  property bool active: false
  readonly property int maskWidth: 480
  readonly property int maskHeight: Math.max(1, Math.round(480 * height / Math.max(1, width)))
  visible: false
  layer.enabled: active
  layer.textureSize: Qt.size(maskWidth, maskHeight)
  onProgressChanged: if (canvas) canvas.requestPaint()
  onEffectChanged: if (canvas) canvas.requestPaint()
  onActiveChanged: if (canvas) canvas.requestPaint()
  Canvas {
    id: canvas
    width: root.maskWidth; height: root.maskHeight
    transform: Scale { xScale: root.width / root.maskWidth; yScale: root.height / root.maskHeight }
    onPaint: {
      var ctx=getContext("2d"), w=width, h=height, p=Math.max(0,Math.min(1,root.progress))
      ctx.reset(); ctx.clearRect(0,0,w,h)
      if (!root.active || p<=0) return
      ctx.fillStyle="white"
      if(p>=1) { ctx.fillRect(0,0,w,h); return }
      if(root.effect==="reveal") {
        var slant=-.18, reach=w/2+Math.abs(slant)*h/2+1, spread=reach*p
        ctx.beginPath();ctx.moveTo(w/2-slant*h/2-spread,0);ctx.lineTo(w/2-slant*h/2+spread,0)
        ctx.lineTo(w/2+slant*h/2+spread,h);ctx.lineTo(w/2+slant*h/2-spread,h);ctx.closePath();ctx.fill()
      } else if(root.effect==="iris") {
        var r=Math.sqrt(w*w+h*h)*.53*p
        var g=ctx.createRadialGradient(w/2,h/2,Math.max(0,r-12),w/2,h/2,r+12)
        g.addColorStop(0,"white");g.addColorStop(1,"transparent");ctx.fillStyle=g;ctx.fillRect(0,0,w,h)
      } else if(root.effect==="shutters") {
        for(var i=0;i<18;i++) {
          var t=Math.max(0,Math.min(1,(p-(i%3)*.08)/.84)), span=w/18
          ctx.fillRect(i*span+span*(1-t)/2,0,span*t,h)
        }
      } else if(root.effect==="scanline") {
        for(var row=0;row<45;row++) {
          var t=Math.max(0,Math.min(1,(p-row/45*.65)/.35))
          ctx.fillRect(row%2===0 ? 0 : w*(1-t),row*h/45,w*t,h/45+.5)
        }
      } else if(root.effect==="ink-spread") {
        for(var i=0;i<17;i++) {
          var x=((i*73+19)%97)/97*w, y=((i*43+7)%89)/89*h
          var radius=Math.max(.1,(p-i%4*.045)*Math.sqrt(w*w+h*h)*.68)
          var g=ctx.createRadialGradient(x,y,radius*.65,x,y,radius)
          g.addColorStop(0,"white");g.addColorStop(1,"transparent");ctx.fillStyle=g;ctx.fillRect(0,0,w,h)
        }
      } else if(root.effect==="aurora") {
        for(var x=0;x<w;x+=3) {
          var edge=h*(1.22-1.44*p+Math.sin(x/w*9+p*5)*.09+Math.sin(x/w*21-p*3)*.035)
          var g=ctx.createLinearGradient(0,edge-10,0,edge+10)
          g.addColorStop(0,"transparent");g.addColorStop(1,"white");ctx.fillStyle=g;ctx.fillRect(x,0,3,h)
        }
      } else {
        var columns=48, rows=27
        for(var index=0;index<columns*rows;index++) {
          var col=index%columns, row=Math.floor(index/columns), threshold
          if(root.effect==="vortex") {
            var dx=(col+.5)/columns-.5, dy=(row+.5)/rows-.5
            var angle=(Math.atan2(dy,dx)+Math.PI)/(2*Math.PI)
            threshold=Math.sqrt(dx*dx+dy*dy)*.88+((angle+Math.sqrt(dx*dx+dy*dy)*2)%1)*.22
          } else threshold=((index*73+row*41)%997)/997*.8
          ctx.globalAlpha=Math.max(0,Math.min(1,(p-threshold)*5));ctx.fillStyle="white"
          ctx.fillRect(col*w/columns,row*h/rows,w/columns+.5,h/rows+.5)
        }
      }
    }
  }
}
