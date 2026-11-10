import SwiftUI

/// Thai overlay (E05, FR-006, OVERLAY mode §9.1): drawn above the original subtitle,
/// which stays visible. Positioned in video coordinates, not device pixels (§9.2).
struct SubtitleOverlayView: View {
    @ObservedObject var pipeline: SubtitlePipeline
    let videoSize: CGSize
    var showDebug: Bool
    var fontScale: CGFloat = 1
    /// MASK_REPLACE (§9.1, FR-011): cover the source text box and draw Thai in its place.
    var replace = false

    var body: some View {
        GeometryReader { geo in
            let rect = Self.aspectFit(videoSize, in: geo.size)
            ZStack(alignment: .topLeading) {
                if showDebug { debugLayer(rect) }
                if let o = pipeline.overlay {
                    if replace, o.status == .shown { replaced(o, rect) } else { subtitle(o, rect) }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private func subtitle(_ o: SubtitlePipeline.Overlay, _ rect: CGRect) -> some View {
        let fontSize = max(14, rect.height * 0.045 * fontScale) // ~48pt at 1080p reference
        let top = rect.minY + o.bbox.minY * rect.height
        Group {
            switch o.status {
            case .shown:
                Text(o.thai ?? "")
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 0, x: 2, y: 2)
                    .shadow(color: .black, radius: 3)
                    .lineLimit(2) // max 2 rows default (§9.2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("thai_overlay")
            case .translating:
                ProgressView().controlSize(.small).tint(.white)
                    .padding(6).background(.black.opacity(0.4), in: Capsule())
            case .failed(let why):
                if showDebug { Text("⚠︎ \(why)").font(.caption).foregroundStyle(.yellow) }
            }
        }
        .frame(width: rect.width * 0.92)
        .fixedSize(horizontal: false, vertical: true)
        .position(x: rect.midX, y: max(rect.minY + fontSize, top - fontSize * 1.1))
    }

    /// Patch over the original box (sampled panel colour, else dark translucent), Thai sized to fit it.
    @ViewBuilder private func replaced(_ o: SubtitlePipeline.Overlay, _ rect: CGRect) -> some View {
        let pad: CGFloat = 0.006
        let box = o.bbox.insetBy(dx: -pad * 1.5, dy: -pad)
        let w = box.width * rect.width, h = box.height * rect.height
        let bg = pipeline.background
        let fill = bg.map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) } ?? .black.opacity(0.8)
        let luma = bg.map { 0.299 * $0.x + 0.587 * $0.y + 0.114 * $0.z } ?? 0
        let ink: Color = luma > 0.55 ? .black : .white
        // Thai needs ~1.3× the Latin line height; never smaller than readable.
        let fontSize = max(13, min(rect.height * 0.06 * fontScale, h * 0.75))
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(fill)
            Text(o.thai ?? "")
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 4)
                .accessibilityIdentifier("thai_overlay")
        }
        .frame(width: max(w, rect.width * 0.12))
        .frame(minHeight: h)
        .fixedSize(horizontal: false, vertical: true)
        .position(x: rect.minX + box.midX * rect.width, y: rect.minY + box.midY * rect.height)
    }

    @ViewBuilder private func debugLayer(_ rect: CGRect) -> some View {
        let roi = pipeline.roi
        Rectangle().stroke(.yellow.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [6]))
            .frame(width: roi.width * rect.width, height: roi.height * rect.height)
            .position(x: rect.minX + roi.midX * rect.width, y: rect.minY + roi.midY * rect.height)
        if let b = pipeline.lastOcrBox {
            Rectangle().stroke(.green, lineWidth: 2)
                .frame(width: b.width * rect.width, height: b.height * rect.height)
                .position(x: rect.minX + b.midX * rect.width, y: rect.minY + b.midY * rect.height)
        }
        let d = pipeline.debug
        VStack(alignment: .leading, spacing: 2) {
            Text("OCR \(Int(d.ocrMs)) ms · conf \(d.lastOcrConfidence, specifier: "%.2f")")
            Text("src: \(d.lastOcrText.isEmpty ? "—" : d.lastOcrText)").lineLimit(2)
            Text("translate \(Int(d.translateMs)) ms · done \(d.translations) · cache \(d.cacheHits) · stale \(d.staleDropped) · ??? \(d.unreadable) · invalid \(d.invalid)")
            Text("model: \(pipeline.translator?.modelId ?? "none") · prompt \(pipeline.translator?.promptVersion ?? "-")")
        }
        .font(.caption.monospaced()).foregroundStyle(.white)
        .padding(6).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: 520, alignment: .leading)
        .position(x: rect.minX + 270, y: rect.minY + 50)
    }

    static func aspectFit(_ content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else { return CGRect(origin: .zero, size: container) }
        let s = min(container.width / content.width, container.height / content.height)
        let w = content.width * s, h = content.height * s
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}
