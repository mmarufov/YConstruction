import SwiftUI
import SceneKit

struct Scene2DMarkerOverlay: View {
    let renderer: SceneRendererService
    let defects: [Defect]
    let currentStorey: String?
    @Binding var tappedDefectId: String?

    var body: some View {
        GeometryReader { geo in
            Canvas2DOverlay(
                renderer: renderer,
                defects: defects.filter { currentStorey == nil || $0.storey == currentStorey },
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
            guard let ctx = UIGraphicsGetCurrentContext(), let renderer = renderer else { return }
            _ = renderer
            let red = UIColor.systemRed.cgColor
            ctx.setStrokeColor(red)
            ctx.setFillColor(UIColor.systemRed.withAlphaComponent(0.4).cgColor)
            ctx.setLineWidth(2)
            for defect in defects {
                drawBoxAndCentroid(ctx: ctx, defect: defect)
            }
        }

        private func drawBoxAndCentroid(ctx: CGContext, defect: Defect) {
            let corners = [
                (defect.bboxMinX, defect.bboxMinY, defect.bboxMinZ),
                (defect.bboxMaxX, defect.bboxMinY, defect.bboxMinZ),
                (defect.bboxMaxX, defect.bboxMaxY, defect.bboxMinZ),
                (defect.bboxMinX, defect.bboxMaxY, defect.bboxMinZ)
            ]
            var pts: [CGPoint] = corners.map { worldToScreen(x: $0.0, y: $0.1, z: $0.2) }
            guard !pts.isEmpty else { return }
            ctx.beginPath()
            ctx.move(to: pts[0])
            for p in pts.dropFirst() { ctx.addLine(to: p) }
            ctx.closePath()
            ctx.strokePath()

            let center = worldToScreen(x: defect.centroidX, y: defect.centroidY, z: defect.centroidZ)
            let r: CGFloat = defect.resolved ? 6 : 8
            ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            _ = pts.removeAll()
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
