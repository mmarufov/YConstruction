import SwiftUI
import SceneKit

struct Scene2DMarkerOverlay: View {
    let renderer: SceneRendererService
    let defects: [Defect]
    @Binding var tappedDefectId: String?

    var body: some View {
        GeometryReader { geo in
            Canvas2DOverlay(
                renderer: renderer,
                defects: defects,
                size: geo.size,
                tappedDefectId: $tappedDefectId
            )
        }
        .allowsHitTesting(true)
    }
}

private struct Canvas2DOverlay: UIViewRepresentable {
    let renderer: SceneRendererService
    let defects: [Defect]
    let size: CGSize
    @Binding var tappedDefectId: String?

    func makeUIView(context: Context) -> OverlayView {
        let view = OverlayView()
        view.coordinator = context.coordinator
        context.coordinator.overlayView = view
        return view
    }

    func updateUIView(_ uiView: OverlayView, context: Context) {
        context.coordinator.parent = self
        uiView.defects = defects
        uiView.renderer = renderer
        uiView.frameSize = size
        uiView.setNeedsLayout()
        uiView.setNeedsDisplay()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: Canvas2DOverlay
        weak var overlayView: OverlayView?
        init(parent: Canvas2DOverlay) { self.parent = parent }
    }

    final class OverlayView: UIView {
        var renderer: SceneRendererService?
        var defects: [Defect] = []
        var frameSize: CGSize = .zero
        weak var coordinator: Coordinator?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
            addGestureRecognizer(tap)
        }
        required init?(coder: NSCoder) { fatalError() }

        @objc func onTap(_ g: UITapGestureRecognizer) {
            let pt = g.location(in: self)
            for defect in defects {
                let center = worldToScreen(x: defect.centroidX, y: defect.centroidY, z: defect.centroidZ)
                let dist = hypot(center.x - pt.x, center.y - pt.y)
                if dist < 22 {
                    coordinator?.parent.tappedDefectId = defect.id
                    return
                }
            }
        }

        override func draw(_ rect: CGRect) {
            guard let ctx = UIGraphicsGetCurrentContext(), renderer != nil else { return }
            ctx.setLineWidth(2)
            for defect in defects {
                drawBoxAndCentroid(ctx: ctx, defect: defect)
            }
        }

        private func drawBoxAndCentroid(ctx: CGContext, defect: Defect) {
            let colorIndex = WorkerDirectoryService.shared.colorIndex(forReporter: defect.reporter)
            let color = WorkerColorPalette.uiColor(for: colorIndex)

            ctx.setStrokeColor(color.cgColor)
            ctx.setFillColor(color.withAlphaComponent(0.35).cgColor)

            let corners = [
                (defect.bboxMinX, defect.bboxMinY, defect.bboxMinZ),
                (defect.bboxMaxX, defect.bboxMinY, defect.bboxMinZ),
                (defect.bboxMaxX, defect.bboxMaxY, defect.bboxMinZ),
                (defect.bboxMinX, defect.bboxMaxY, defect.bboxMinZ)
            ]
            let pts: [CGPoint] = corners.map { worldToScreen(x: $0.0, y: $0.1, z: $0.2) }
            guard !pts.isEmpty else { return }
            ctx.beginPath()
            ctx.move(to: pts[0])
            for p in pts.dropFirst() { ctx.addLine(to: p) }
            ctx.closePath()
            ctx.drawPath(using: .fillStroke)

            let center = worldToScreen(x: defect.centroidX, y: defect.centroidY, z: defect.centroidZ)
            let r: CGFloat = defect.resolved ? 10 : 14

            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - r - 2, y: center.y - r - 2, width: (r + 2) * 2, height: (r + 2) * 2))

            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))

            drawNameChip(ctx: ctx, text: defect.reporter, color: color, at: CGPoint(x: center.x, y: center.y - r - 10))
        }

        private func drawNameChip(ctx: CGContext, text: String, color: UIColor, at anchor: CGPoint) {
            let font = UIFont.systemFont(ofSize: 11, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]
            let attributed = NSAttributedString(string: text, attributes: attrs)
            let textSize = attributed.size()

            let padX: CGFloat = 8
            let padY: CGFloat = 3
            let chipRect = CGRect(
                x: anchor.x - (textSize.width + padX * 2) / 2,
                y: anchor.y - (textSize.height + padY * 2),
                width: textSize.width + padX * 2,
                height: textSize.height + padY * 2
            )

            let path = UIBezierPath(roundedRect: chipRect, cornerRadius: chipRect.height / 2)
            ctx.setFillColor(color.cgColor)
            ctx.addPath(path.cgPath)
            ctx.fillPath()

            UIGraphicsPushContext(ctx)
            attributed.draw(at: CGPoint(x: chipRect.minX + padX, y: chipRect.minY + padY))
            UIGraphicsPopContext()
        }

        private func worldToScreen(x: Double, y: Double, z: Double) -> CGPoint {
            guard frameSize.width > 0, frameSize.height > 0 else { return .zero }
            guard let cam = renderer?.pointOfView2D.camera else {
                return CGPoint(x: bounds.midX, y: bounds.midY)
            }
            let orthoScale = CGFloat(cam.orthographicScale)
            let aspect = frameSize.width / frameSize.height
            let camPos = renderer?.pointOfView2D.position ?? SCNVector3Zero
            let relX = CGFloat(x) - CGFloat(camPos.x)
            let relY = CGFloat(y) - CGFloat(camPos.y)
            let screenX = (relX / (orthoScale * aspect)) * (frameSize.width / 2) + frameSize.width / 2
            let screenY = (-relY / orthoScale) * (frameSize.height / 2) + frameSize.height / 2
            _ = z
            return CGPoint(x: screenX, y: screenY)
        }
    }
}
