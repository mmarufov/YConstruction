import Foundation
import SceneKit
import GLTFKit2
import UIKit

enum SceneCameraMode {
    case perspective3D
    case orthographic2D
}

@MainActor
final class SceneRendererService {
    let scene = SCNScene()
    let rootNode: SCNNode
    let markersNode = SCNNode()
    let pointOfView3D = SCNNode()
    let pointOfView2D = SCNNode()

    private var markersByDefectId: [String: SCNNode] = [:]
    private var modelBounds: (min: SCNVector3, max: SCNVector3) = (SCNVector3(-5, -5, 0), SCNVector3(5, 5, 5))
    private var storeys: [ElementIndex.Storey] = []
    private(set) var currentStorey: String?
    private(set) var currentMode: SceneCameraMode = .perspective3D

    init() {
        self.rootNode = scene.rootNode
        rootNode.addChildNode(markersNode)
        setupCameras()
        setupLighting()
    }

    // MARK: - Load

    func load(glbURL: URL) async throws {
        let asset: GLTFAsset = try await withCheckedThrowingContinuation { cont in
            // GLTFKit2's handler fires repeatedly (parsing → validating → processing
            // → complete/error). Resume exactly once, on complete OR error.
            var resumed = false
            GLTFAsset.load(with: glbURL, options: [:]) { _, status, maybeAsset, maybeError, _ in
                if resumed { return }
                switch status {
                case .complete:
                    if let asset = maybeAsset {
                        resumed = true
                        cont.resume(returning: asset)
                    } else {
                        resumed = true
                        cont.resume(throwing: maybeError ?? NSError(
                            domain: "SceneRenderer",
                            code: 0,
                            userInfo: [NSLocalizedDescriptionKey: "glTF load completed with no asset"]
                        ))
                    }
                case .error:
                    resumed = true
                    cont.resume(throwing: maybeError ?? NSError(
                        domain: "SceneRenderer",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "glTF load failed"]
                    ))
                default:
                    break
                }
            }
        }

        let loadedScene = SCNScene(gltfAsset: asset)
        loadedScene.rootNode.enumerateChildNodes { node, _ in
            self.rootNode.addChildNode(node.clone())
        }

        let (minVec, maxVec) = scene.rootNode.boundingBox
        modelBounds = (minVec, maxVec)
        frameCameras(to: minVec, max: maxVec)
    }

    /// Hide any glb mesh whose IFC GUID isn't in the resolver's element index.
    /// IfcConvert emits every IFC product as a mesh named `product-{uuid}-body`.
    /// Our element_index.json only keeps walls/doors/windows/spaces — so
    /// stairs, railings, furniture, fixtures, etc. survive in the glb. This
    /// filter prunes them so the 3D view shows only the structural shell.
    func filterMeshes(keepingIndexed index: ElementIndex) {
        var allowedNodeNames = Set<String>()
        for (ifcGuid, _) in index.elements {
            guard let uuid = IfcGuid.decompress(ifcGuid) else { continue }
            allowedNodeNames.insert("product-\(uuid)-body")
        }

        rootNode.enumerateChildNodes { node, _ in
            guard let name = node.name,
                  name.hasPrefix("product-"),
                  name.hasSuffix("-body") else { return }
            if !allowedNodeNames.contains(name) {
                node.isHidden = true
            }
        }
    }

    func configure(storeys: [ElementIndex.Storey]) {
        self.storeys = storeys
        if currentStorey == nil {
            currentStorey = storeys.first(where: { $0.name == "Level 1" })?.name ?? storeys.first?.name
        }
        refreshStoreyVisibility()
    }

    // MARK: - Camera

    private func setupCameras() {
        let cam3D = SCNCamera()
        cam3D.usesOrthographicProjection = false
        cam3D.fieldOfView = 60
        cam3D.zFar = 1000
        cam3D.zNear = 0.01
        pointOfView3D.camera = cam3D
        pointOfView3D.position = SCNVector3(15, -15, 10)
        pointOfView3D.look(at: SCNVector3Zero)
        rootNode.addChildNode(pointOfView3D)

        let cam2D = SCNCamera()
        cam2D.usesOrthographicProjection = true
        cam2D.orthographicScale = 15
        cam2D.zFar = 1000
        cam2D.zNear = -1000
        pointOfView2D.camera = cam2D
        pointOfView2D.position = SCNVector3(0, 0, 50)
        pointOfView2D.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        rootNode.addChildNode(pointOfView2D)
    }

    private func setupLighting() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 600
        rootNode.addChildNode(ambient)

        let directional = SCNNode()
        directional.light = SCNLight()
        directional.light?.type = .directional
        directional.light?.intensity = 800
        directional.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        rootNode.addChildNode(directional)
    }

    private func frameCameras(to min: SCNVector3, max: SCNVector3) {
        let extents = SCNVector3(max.x - min.x, max.y - min.y, max.z - min.z)
        let center = SCNVector3((min.x + max.x) / 2, (min.y + max.y) / 2, (min.z + max.z) / 2)
        let largestHoriz = Swift.max(abs(extents.x), abs(extents.y))
        let diag = sqrt(extents.x * extents.x + extents.y * extents.y + extents.z * extents.z)

        pointOfView3D.position = SCNVector3(
            center.x + diag * 0.8,
            center.y - diag * 0.8,
            center.z + diag * 0.6
        )
        pointOfView3D.look(at: center)

        pointOfView2D.position = SCNVector3(center.x, center.y, center.z + diag)
        pointOfView2D.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        pointOfView2D.camera?.orthographicScale = Double(largestHoriz / 2) + 1
    }

    func pointOfView(for mode: SceneCameraMode) -> SCNNode {
        switch mode {
        case .perspective3D: return pointOfView3D
        case .orthographic2D: return pointOfView2D
        }
    }

    // MARK: - Storey filter

    func setStorey(_ storey: String?) {
        currentStorey = storey
        refreshStoreyVisibility()
    }

    func setMode(_ mode: SceneCameraMode) {
        currentMode = mode
    }

    private func refreshStoreyVisibility() {
        for child in markersNode.childNodes {
            let markerStorey = child.value(forKey: "storey") as? String
            child.isHidden = (currentStorey != nil && markerStorey != currentStorey)
        }
    }

    // MARK: - Markers

    func syncMarkers(with defects: [Defect]) {
        let existingIds = Set(markersByDefectId.keys)
        let currentIds = Set(defects.map { $0.id })

        for removedId in existingIds.subtracting(currentIds) {
            markersByDefectId[removedId]?.removeFromParentNode()
            markersByDefectId.removeValue(forKey: removedId)
        }

        for defect in defects {
            if let existing = markersByDefectId[defect.id] {
                updateMarkerState(existing, defect: defect)
            } else {
                let node = makeMarkerNode(for: defect)
                markersNode.addChildNode(node)
                markersByDefectId[defect.id] = node
            }
        }

        refreshStoreyVisibility()
    }

    private func makeMarkerNode(for defect: Defect) -> SCNNode {
        let container = SCNNode()
        container.name = "marker:\(defect.id)"
        container.setValue(defect.id, forKey: "defectId")
        container.setValue(defect.storey, forKey: "storey")

        let width = CGFloat(defect.bboxMaxX - defect.bboxMinX)
        let height = CGFloat(defect.bboxMaxZ - defect.bboxMinZ)
        let length = CGFloat(defect.bboxMaxY - defect.bboxMinY)

        let box = SCNBox(width: max(width, 0.05), height: max(height, 0.05), length: max(length, 0.05), chamferRadius: 0)
        let material = SCNMaterial()
        material.fillMode = .lines
        material.diffuse.contents = UIColor.systemRed
        material.emission.contents = UIColor.systemRed
        material.isDoubleSided = true
        material.lightingModel = .constant
        box.materials = [material]

        let boxNode = SCNNode(geometry: box)
        boxNode.position = SCNVector3(
            (defect.bboxMinX + defect.bboxMaxX) / 2,
            (defect.bboxMinY + defect.bboxMaxY) / 2,
            (defect.bboxMinZ + defect.bboxMaxZ) / 2
        )
        container.addChildNode(boxNode)

        let centroid = SCNSphere(radius: 0.15)
        let dotMaterial = SCNMaterial()
        dotMaterial.diffuse.contents = UIColor.systemRed
        dotMaterial.emission.contents = UIColor.systemRed
        dotMaterial.lightingModel = .constant
        centroid.materials = [dotMaterial]

        let centroidNode = SCNNode(geometry: centroid)
        centroidNode.position = SCNVector3(defect.centroidX, defect.centroidY, defect.centroidZ)
        centroidNode.constraints = [SCNBillboardConstraint()]

        let pulse = CABasicAnimation(keyPath: "scale")
        pulse.fromValue = SCNVector3(1, 1, 1)
        pulse.toValue = SCNVector3(1.6, 1.6, 1.6)
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        centroidNode.addAnimation(pulse, forKey: "pulse")
        container.addChildNode(centroidNode)

        updateMarkerState(container, defect: defect)
        return container
    }

    private func updateMarkerState(_ node: SCNNode, defect: Defect) {
        node.opacity = defect.resolved ? 0.35 : 1.0
    }

    // MARK: - Helpers

    func flyTo(defectId: String, in view: SCNView, duration: TimeInterval = 0.8) {
        guard let marker = markersByDefectId[defectId] else { return }
        let target = marker.worldPosition
        let cam = pointOfView(for: currentMode)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        let offset: SCNVector3
        switch currentMode {
        case .perspective3D:
            offset = SCNVector3(target.x + 4, target.y - 4, target.z + 2)
        case .orthographic2D:
            offset = SCNVector3(target.x, target.y, cam.position.z)
        }
        cam.position = offset
        if currentMode == .perspective3D { cam.look(at: target) }
        SCNTransaction.commit()
        _ = view
    }

    func worldPosition(for marker: SCNNode) -> SCNVector3 {
        marker.worldPosition
    }

    func markerNode(for defectId: String) -> SCNNode? {
        markersByDefectId[defectId]
    }
}
