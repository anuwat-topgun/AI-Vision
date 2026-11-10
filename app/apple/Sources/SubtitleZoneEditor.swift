import SwiftUI

/// Subtitle zone editor: drag over the video to draw the area where subtitles appear.
/// OCR (and so translation) only reads inside this zone. Coordinates are normalized to the video.
struct SubtitleZoneEditor: View {
    @ObservedObject var pipeline: SubtitlePipeline
    let videoSize: CGSize
    @State private var draft: CGRect?

    var body: some View {
        GeometryReader { geo in
            let rect = SubtitleOverlayView.aspectFit(videoSize, in: geo.size)
            let shown = draft ?? pipeline.roi
            ZStack(alignment: .topLeading) {
                // Dim everything outside the zone.
                Path { p in
                    p.addRect(rect)
                    p.addRect(Self.toView(shown, rect))
                }
                .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                Rectangle().stroke(.yellow, lineWidth: 2)
                    .frame(width: shown.width * rect.width, height: shown.height * rect.height)
                    .position(x: rect.minX + shown.midX * rect.width, y: rect.minY + shown.midY * rect.height)
                Text("Drag to draw the subtitle zone")
                    .font(.callout.bold()).foregroundStyle(.white)
                    .padding(8).background(.black.opacity(0.7), in: Capsule())
                    .position(x: rect.midX, y: rect.minY + 30)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { g in draft = Self.normalized(g.startLocation, g.location, in: rect) }
                .onEnded { g in
                    let r = Self.normalized(g.startLocation, g.location, in: rect)
                    if r.width > 0.02, r.height > 0.02 { pipeline.roi = r }
                    draft = nil
                })
        }
    }

    static func toView(_ r: CGRect, _ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + r.minX * rect.width, y: rect.minY + r.minY * rect.height,
               width: r.width * rect.width, height: r.height * rect.height)
    }

    static func normalized(_ a: CGPoint, _ b: CGPoint, in rect: CGRect) -> CGRect {
        func clamp(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }
        let x0 = clamp((a.x - rect.minX) / rect.width), x1 = clamp((b.x - rect.minX) / rect.width)
        let y0 = clamp((a.y - rect.minY) / rect.height), y1 = clamp((b.y - rect.minY) / rect.height)
        return CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
    }
}

/// Persisted per screen (live / file) in UserDefaults as [x, y, w, h].
enum SubtitleZoneStore {
    static func load(_ key: String) -> CGRect? {
        guard let a = UserDefaults.standard.array(forKey: key) as? [Double], a.count == 4 else { return nil }
        return CGRect(x: a[0], y: a[1], width: a[2], height: a[3])
    }
    static func save(_ r: CGRect, _ key: String) {
        UserDefaults.standard.set([r.minX, r.minY, r.width, r.height], forKey: key)
    }
}
