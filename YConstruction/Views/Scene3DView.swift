import SwiftUI
import SceneKit

struct Scene3DView: UIViewRepresentable {
    let renderer: SceneRendererService
    let mode: SceneCameraMode
    @Binding var tappedDefectId: String?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = renderer.scene
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = UIColor.systemBackground
        view.antialiasingMode = .multisampling4X
        view.pointOfView = renderer.pointOfView(for: mode)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.pointOfView = renderer.pointOfView(for: mode)
        uiView.allowsCameraControl = (mode == .perspective3D)
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: Scene3DView
        weak var view: SCNView?

        init(parent: Scene3DView) { self.parent = parent }

        @objc func onTap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let location = gesture.location(in: view)
            let hits = view.hitTest(location, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue])
            for hit in hits {
                var node: SCNNode? = hit.node
                while let n = node {
                    if let id = n.value(forKey: "defectId") as? String {
                        parent.tappedDefectId = id
                        return
                    }
                    node = n.parent
                }
            }
        }
    }
}
