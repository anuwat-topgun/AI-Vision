import SwiftUI

/// Subtitle zone editor. Each zone is read and translated on its own, so separate text on screen
/// (dialogue, name tag, choices) is never joined into one sentence. Drag on empty video to add a
/// zone; drag on the selected zone's area to redraw it; tap a zone to select it.
struct SubtitleZoneEditor: View {
    @Binding var zones: [CGRect]
    @Binding var roles: [ZoneRole]
    @Binding var selected: Int
    let videoSize: CGSize
    @State private var draft: CGRect?

    var body: some View {
        GeometryReader { geo in
            let rect = SubtitleOverlayView.aspectFit(videoSize, in: geo.size)
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.addRect(rect)
                    for z in zones { p.addRect(Self.toView(z, rect)) }
                }
                .fill(.black.opacity(0.5), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .gesture(drawGesture(rect, addNew: true))

                ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                    let v = Self.toView(z, rect)
                    Rectangle().fill(.white.opacity(0.001))
                        .overlay(Rectangle().stroke(i == selected ? .yellow : .cyan, lineWidth: i == selected ? 3 : 2))
                        .overlay(alignment: .topLeading) {
                            Text(i == 0 ? "1 · dialogue"
                                 : roles.indices.contains(i) && roles[i] == .speaker ? "\(i + 1) · speaker name" : "\(i + 1)")
                                .font(.caption.bold()).foregroundStyle(.black)
                                .padding(.horizontal, 5).background(i == selected ? .yellow : .cyan)
                        }
                        .frame(width: v.width, height: v.height)
                        .position(x: v.midX, y: v.midY)
                        .onTapGesture { selected = i }
                        .gesture(drawGesture(rect, addNew: false))
                }
                if let d = draft {
                    let v = Self.toView(d, rect)
                    Rectangle().stroke(.yellow, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .frame(width: v.width, height: v.height).position(x: v.midX, y: v.midY)
                }
                Text("Drag on the video to add a zone · tap a zone to select · drag inside it to redraw")
                    .font(.callout.bold()).foregroundStyle(.white)
                    .padding(8).background(.black.opacity(0.7), in: Capsule())
                    .position(x: rect.midX, y: rect.minY + 24)
                    .allowsHitTesting(false)
            }
        }
    }

    private func drawGesture(_ rect: CGRect, addNew: Bool) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { g in draft = Self.normalized(g.startLocation, g.location, in: rect) }
            .onEnded { g in
                defer { draft = nil }
                let r = Self.normalized(g.startLocation, g.location, in: rect)
                guard r.width > 0.02, r.height > 0.015 else { return }
                if addNew { zones.append(r); roles.append(.translate); selected = zones.count - 1 }
                else if zones.indices.contains(selected) { zones[selected] = r }
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

/// Zones persisted in UserDefaults as a flat [x, y, w, h, x, y, w, h, …].
enum SubtitleZoneStore {
    static func load(_ key: String) -> [CGRect] {
        guard let a = UserDefaults.standard.array(forKey: key) as? [Double], a.count >= 4, a.count % 4 == 0
        else { return [] }
        return stride(from: 0, to: a.count, by: 4).map { CGRect(x: a[$0], y: a[$0 + 1], width: a[$0 + 2], height: a[$0 + 3]) }
    }
    static func save(_ zones: [CGRect], _ key: String) {
        UserDefaults.standard.set(zones.flatMap { [$0.minX, $0.minY, $0.width, $0.height] }, forKey: key)
    }
}

/// What a zone is for. Zone 1 always translates.
enum ZoneRole: String, CaseIterable, Identifiable {
    case translate, speaker
    var id: String { rawValue }
    var label: String { self == .translate ? "Translate" : "Speaker name (not translated)" }

    static func load(_ key: String, count: Int) -> [ZoneRole] {
        let saved = (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(ZoneRole.init(rawValue:))
        return (0..<count).map { $0 < saved.count && $0 > 0 ? saved[$0] : .translate }
    }
    static func save(_ roles: [ZoneRole], _ key: String) {
        UserDefaults.standard.set(roles.map(\.rawValue), forKey: key)
    }
}
