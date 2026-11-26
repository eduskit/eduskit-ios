import SwiftUI

/// Core provides final angles and polygons. History and current snapshots render immediately.
struct TeachingToolRandomResult: View {
    let frame: TeachingToolRandom
    private let palette: [Color] = [Color(red:0.47,green:0.41,blue:0.85),Color(red:0.19,green:0.61,blue:0.55),Color(red:0.86,green:0.58,blue:0.38),Color(red:0.76,green:0.42,blue:0.64),Color(red:0.33,green:0.54,blue:0.79),Color(red:0.61,green:0.62,blue:0.31)]
    private func polygon(_ points: [[Double]]) -> Path {
        var path=Path()
        for (index,p) in points.enumerated() {
            let point=CGPoint(x:p[0],y:p[1])
            if index==0 {path.move(to:point)} else {path.addLine(to:point)}
        }
        path.closeSubpath();return path
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(EduI18n.text("tool_selectedResults"))
            if frame.mode=="wheel" {
                Canvas { context,size in
                    context.scaleBy(x:size.width/100,y:size.height/100)
                    var wheel=context
                    wheel.translateBy(x:50,y:50);wheel.rotate(by:.degrees(frame.rotationDegrees));wheel.translateBy(x:-50,y:-50)
                    for slice in frame.slices {wheel.fill(polygon(slice.points),with:.color(palette[slice.colorIndex]))}
                    context.fill(polygon([[46,1],[54,1],[50,10]]),with:.color(.primary))
                    context.fill(Path(ellipseIn:CGRect(x:43,y:43,width:14,height:14)),with:.color(Color(.systemBackground)))
                }.frame(width:200,height:200).frame(maxWidth:.infinity).accessibilityHidden(true)
            }
            LazyVGrid(columns: frame.mode=="list" ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum:88))],alignment:.leading,spacing:8) {
                ForEach(frame.rows) { row in
                    VStack {
                        if let glyph=row.glyph {Text(glyph).font(.system(size:48)).accessibilityHidden(true)}
                        Text(row.labelKey.map { EduI18n.text($0) } ?? row.label).bold().fixedSize(horizontal:false,vertical:true)
                    }.padding(frame.mode=="cards" ? 12 : 8)
                        .frame(minHeight:frame.mode=="coin" ? 88 : nil)
                        .background(frame.mode=="cards" ? Color(.secondarySystemBackground) : .clear,in:RoundedRectangle(cornerRadius:8))
                        .overlay {if frame.mode=="coin" {Circle().stroke(Color(red:0.71,green:0.57,blue:0.3),lineWidth:2)}}
                }
            }
            if frame.mode=="wheel" {
                Text(EduI18n.text("tool_candidatePool")+" · \(frame.poolWeight)")
                ForEach(Array(frame.slices.enumerated()),id:\.offset) { _,slice in Text((slice.label ?? EduI18n.text("tool_otherCandidates"))+" · \(slice.weight)") }
            }
        }
    }
}
