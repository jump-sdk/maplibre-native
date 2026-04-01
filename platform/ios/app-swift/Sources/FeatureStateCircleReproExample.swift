import MapLibre
import SwiftUI
import UIKit

final class FeatureStateCircleReproExample: UIViewController, MLNMapViewDelegate {
    private enum Constants {
        static let sourceID = "feature-state-repro-source"
        static let debugCirclesLayerID = "feature-state-repro-debug-circles"
        static let circlesLayerID = "feature-state-repro-circles"
        static let labelsLayerID = "feature-state-repro-labels"
        static let availableState = "available"
        static let selectedState = "selected"
        static let defaultState = "default"
    }

    private var mapView: MLNMapView!
    private let statusLabel = UILabel()
    private let applyButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private var didApplyInitialState = false

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Feature State Circle Repro"
        view.backgroundColor = .systemBackground

        mapView = MLNMapView(frame: view.bounds)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.setCenter(CLLocationCoordinate2D(latitude: 45.52214, longitude: -122.63748), zoomLevel: 16, animated: false)
        mapView.delegate = self
        view.addSubview(mapView)

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
        for recognizer in mapView.gestureRecognizers ?? [] where recognizer is UITapGestureRecognizer {
            tapRecognizer.require(toFail: recognizer)
        }
        mapView.addGestureRecognizer(tapRecognizer)

        configureOverlay()
    }

    func mapView(_: MLNMapView, didFinishLoading style: MLNStyle) {
        guard style.source(withIdentifier: Constants.sourceID) == nil else { return }

        addReproSourceAndLayers(style: style)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.didApplyInitialState else { return }
            self.didApplyInitialState = true
            self.applyFeatureState()
        }
    }

    @objc
    private func applyFeatureState() {
        mapView.setFeatureState(
            forSource: Constants.sourceID,
            sourceLayer: nil,
            featureID: "seat-a",
            state: ["seatStyleCategory": Constants.availableState]
        )
        mapView.setFeatureState(
            forSource: Constants.sourceID,
            sourceLayer: nil,
            featureID: "seat-b",
            state: ["seatStyleCategory": Constants.selectedState]
        )

        let seatAState = mapView.featureState(forSource: Constants.sourceID, sourceLayer: nil, featureID: "seat-a")
        let seatBState = mapView.featureState(forSource: Constants.sourceID, sourceLayer: nil, featureID: "seat-b")
        let message = "Applied state. seat-a=\(describe(state: seatAState)) seat-b=\(describe(state: seatBState))"

        print("[FeatureStateCircleRepro] \(message)")
        statusLabel.text = message
    }

    @objc
    private func clearFeatureState() {
        mapView.removeFeatureState(forSource: Constants.sourceID, sourceLayer: nil, featureID: "seat-a", stateKey: nil)
        mapView.removeFeatureState(forSource: Constants.sourceID, sourceLayer: nil, featureID: "seat-b", stateKey: nil)

        let seatAState = mapView.featureState(forSource: Constants.sourceID, sourceLayer: nil, featureID: "seat-a")
        let seatBState = mapView.featureState(forSource: Constants.sourceID, sourceLayer: nil, featureID: "seat-b")
        let message = "Cleared state. seat-a=\(describe(state: seatAState)) seat-b=\(describe(state: seatBState))"

        print("[FeatureStateCircleRepro] \(message)")
        statusLabel.text = message
    }

    @objc
    private func handleMapTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }

        let point = recognizer.location(in: mapView)
        let layerIDs: Set<String> = [Constants.debugCirclesLayerID, Constants.circlesLayerID, Constants.labelsLayerID]
        guard let tappedFeature = mapView.visibleFeatures(at: point, styleLayerIdentifiers: layerIDs).first else {
            let message = "Tap hit no repro feature."
            print("[FeatureStateCircleRepro] \(message)")
            statusLabel.text = message
            return
        }

        let runtimeID = tappedFeature.identifier ?? "nil"
        let attributesID = tappedFeature.attributes["id"] ?? "nil"
        let featureID = String(describing: runtimeID)
        let state = mapView.featureState(forSource: Constants.sourceID, sourceLayer: nil, featureID: featureID)
        let message = "Tapped runtimeID=\(runtimeID) attributesID=\(attributesID) state=\(describe(state: state))"

        print("[FeatureStateCircleRepro] \(message)")
        statusLabel.text = message
    }

    private func configureOverlay() {
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 12
        blurView.clipsToBounds = true
        view.addSubview(blurView)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        blurView.contentView.addSubview(stack)

        let buttonRow = UIStackView()
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fillEqually

        applyButton.setTitle("Apply State", for: .normal)
        applyButton.addTarget(self, action: #selector(applyFeatureState), for: .touchUpInside)

        clearButton.setTitle("Clear State", for: .normal)
        clearButton.addTarget(self, action: #selector(clearFeatureState), for: .touchUpInside)

        buttonRow.addArrangedSubview(applyButton)
        buttonRow.addArrangedSubview(clearButton)

        statusLabel.numberOfLines = 0
        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .label
        statusLabel.text = "Waiting for style to load."

        let instructionsLabel = UILabel()
        instructionsLabel.numberOfLines = 0
        instructionsLabel.font = .systemFont(ofSize: 12)
        instructionsLabel.textColor = .secondaryLabel
        instructionsLabel.text = "Expected after Apply State: seat-a circle and label turn green, seat-b turns orange, seat-c stays gray."

        stack.addArrangedSubview(buttonRow)
        stack.addArrangedSubview(instructionsLabel)
        stack.addArrangedSubview(statusLabel)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            blurView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            blurView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            stack.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -12),
        ])
    }

    private func addReproSourceAndLayers(style: MLNStyle) {
        let source = makeGeoJSONShapeSource()
        style.addSource(source)

        let coordinates = makeSeatFeatures().map(\.coordinate)
        mapView.setVisibleCoordinates(
            coordinates,
            count: UInt(coordinates.count),
            edgePadding: UIEdgeInsets(top: 140, left: 60, bottom: 240, right: 60),
            animated: false
        )

        let debugCircles = MLNCircleStyleLayer(identifier: Constants.debugCirclesLayerID, source: source)
        debugCircles.circleRadius = NSExpression(forConstantValue: 26)
        debugCircles.circleOpacity = NSExpression(forConstantValue: 0.6)
        debugCircles.circleColor = NSExpression(forConstantValue: UIColor.systemBlue)
        style.addLayer(debugCircles)

        let circles = MLNCircleStyleLayer(identifier: Constants.circlesLayerID, source: source)
        circles.circleRadius = NSExpression(forConstantValue: 12)
        circles.circleStrokeWidth = NSExpression(forConstantValue: 2)
        circles.circleStrokeColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.6))
        circles.circleOpacity = NSExpression(forConstantValue: 1)
        circles.circleColor = seatCategoryColorExpression()
        style.addLayer(circles)

        let labels = MLNSymbolStyleLayer(identifier: Constants.labelsLayerID, source: source)
        labels.text = NSExpression(forKeyPath: "label")
        labels.textFontSize = NSExpression(forConstantValue: 12)
        labels.textAnchor = NSExpression(forConstantValue: NSValue(mlnTextAnchor: .top))
        labels.textOffset = NSExpression(forConstantValue: [0, 1.6])
        labels.textColor = NSExpression(forConstantValue: UIColor.black)
        labels.textHaloColor = NSExpression(forConstantValue: UIColor.white.withAlphaComponent(0.9))
        labels.textHaloWidth = NSExpression(forConstantValue: 1.5)
        style.addLayer(labels)

        statusLabel.text = "Source and layers added. Blue debug circles should always be visible."
    }

    private func seatCategoryColorExpression() -> NSExpression {
        NSExpression(
            mglJSONObject: [
                "match",
                [
                    "to-string",
                    [
                        "coalesce",
                        ["feature-state", "seatStyleCategory"],
                        Constants.defaultState,
                    ],
                ],
                Constants.availableState,
                "#2ECC71",
                Constants.selectedState,
                "#F39C12",
                "#B0B8C2",
            ]
        )
    }

    private func makeSeatFeatures() -> [MLNPointFeature] {
        [
            makeSeatFeature(id: "seat-a", label: "seat-a", latitude: 45.52214, longitude: -122.63748),
            makeSeatFeature(id: "seat-b", label: "seat-b", latitude: 45.52214, longitude: -122.63710),
            makeSeatFeature(id: "seat-c", label: "seat-c", latitude: 45.52242, longitude: -122.63729),
        ]
    }

    private func makeGeoJSONShapeSource() -> MLNShapeSource {
        let geoJSON = """
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "id": "seat-a",
              "geometry": {
                "type": "Point",
                "coordinates": [-122.63748, 45.52214]
              },
              "properties": {
                "id": "seat-a",
                "label": "seat-a",
                "type": "seat"
              }
            },
            {
              "type": "Feature",
              "id": "seat-b",
              "geometry": {
                "type": "Point",
                "coordinates": [-122.63710, 45.52214]
              },
              "properties": {
                "id": "seat-b",
                "label": "seat-b",
                "type": "seat"
              }
            },
            {
              "type": "Feature",
              "id": "seat-c",
              "geometry": {
                "type": "Point",
                "coordinates": [-122.63729, 45.52242]
              },
              "properties": {
                "id": "seat-c",
                "label": "seat-c",
                "type": "seat"
              }
            }
          ]
        }
        """

        let data = Data(geoJSON.utf8)
        let shape = try! MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
        return MLNShapeSource(identifier: Constants.sourceID, shape: shape, options: nil)
    }

    private func makeSeatFeature(id: String, label: String, latitude: CLLocationDegrees, longitude: CLLocationDegrees) -> MLNPointFeature {
        let feature = MLNPointFeature()
        feature.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        feature.identifier = id
        feature.attributes = [
            "id": id,
            "label": label,
            "type": "seat",
        ]
        return feature
    }

    private func describe(state: [String: Any]?) -> String {
        guard let state, !state.isEmpty else { return "nil" }
        return String(describing: state)
    }
}

struct FeatureStateCircleReproExampleUIViewControllerRepresentable: UIViewControllerRepresentable {
    typealias UIViewControllerType = FeatureStateCircleReproExample

    func makeUIViewController(context _: Context) -> FeatureStateCircleReproExample {
        FeatureStateCircleReproExample()
    }

    func updateUIViewController(_: FeatureStateCircleReproExample, context _: Context) {}
}
