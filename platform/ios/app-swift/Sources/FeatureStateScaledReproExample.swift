import MapLibre
import SwiftUI
import UIKit

/// Reproduces a bug where feature-state does NOT propagate to circle layer rendering
/// when a GeoJSON source has many features (~18000).
///
/// Root cause: GeometryTile::setFeatureState() silently drops state when `layoutResult`
/// is null (tile still parsing). SourceFeatureState::coalesceChanges() clears stateChanges
/// after attempting to apply, so the state is lost for tiles that weren't ready.
/// On subsequent frames, currentStates IS re-sent, but tiles may still not be ready.
/// Once tiles ARE ready, if no new setFeatureState call triggers a render, the state
/// is never applied.
///
/// With 3 features (single tile, fast layout): works.
/// With 18000 features (many tiles, slower layout): fails.
final class FeatureStateScaledReproExample: UIViewController, MLNMapViewDelegate {
    private enum Constants {
        static let sourceID = "scaled-repro-source"
        static let circlesLayerID = "scaled-repro-circles"
        static let featureStateKey = "seatStyleCategory"
        static let availableState = "available"
        static let defaultState = "default"
    }

    private var mapView: MLNMapView!
    private let statusLabel = UILabel()
    private let featureCountSlider = UISlider()
    private let featureCountLabel = UILabel()
    private let applyButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private var didApplyInitialState = false
    private var currentFeatureCount = 18000

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Feature State Scaled Repro"
        view.backgroundColor = .systemBackground

        mapView = MLNMapView(frame: view.bounds)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: 45.52, longitude: -122.64),
            zoomLevel: 12,
            animated: false
        )
        mapView.delegate = self
        view.addSubview(mapView)

        configureOverlay()
    }

    func mapView(_: MLNMapView, didFinishLoading style: MLNStyle) {
        guard style.source(withIdentifier: Constants.sourceID) == nil else { return }
        reloadSource()
    }

    private func reloadSource() {
        guard let style = mapView.style else { return }

        if let oldLayer = style.layer(withIdentifier: Constants.circlesLayerID) {
            style.removeLayer(oldLayer)
        }
        if let oldSource = style.source(withIdentifier: Constants.sourceID) {
            style.removeSource(oldSource)
        }

        didApplyInitialState = false
        let count = currentFeatureCount

        let source = makeGeoJSONSource(featureCount: count)
        style.addSource(source)

        let circles = MLNCircleStyleLayer(identifier: Constants.circlesLayerID, source: source)
        circles.circleRadius = NSExpression(forConstantValue: 3)
        circles.circleColor = NSExpression(mglJSONObject: [
            "match",
            [
                "to-string",
                ["coalesce", ["feature-state", Constants.featureStateKey], Constants.defaultState],
            ],
            Constants.availableState, "#2ECC71",
            "#95A5A6",
        ])
        style.addLayer(circles)

        statusLabel.text = "Source loaded with \(count) features. Applying state in 0.5s..."

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.didApplyInitialState else { return }
            self.didApplyInitialState = true
            self.applyFeatureState()
        }
    }

    @objc
    private func applyFeatureState() {
        let count = currentFeatureCount
        let halfCount = count / 2
        var appliedCount = 0

        for i in 0 ..< halfCount {
            let featureID = "feat-\(i)"
            mapView.setFeatureState(
                forSource: Constants.sourceID,
                sourceLayer: nil,
                featureID: featureID,
                state: [Constants.featureStateKey: Constants.availableState]
            )
            appliedCount += 1
        }

        let sampleID = "feat-0"
        let readback = mapView.featureState(
            forSource: Constants.sourceID,
            sourceLayer: nil,
            featureID: sampleID
        )

        let message = """
        Applied state to \(appliedCount)/\(count) features.
        Readback feat-0: \(readback.map { String(describing: $0) } ?? "nil")
        Expected: \(halfCount) green circles, \(count - halfCount) gray circles.
        If ALL gray: bug confirmed (state not reaching tiles).
        """
        print("[ScaledRepro] \(message)")
        statusLabel.text = message
    }

    @objc
    private func retryApplyState() {
        didApplyInitialState = false
        statusLabel.text = "Retrying state application..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.didApplyInitialState = true
            self?.applyFeatureState()
        }
    }

    @objc
    private func reloadWithCurrentCount() {
        currentFeatureCount = Int(featureCountSlider.value)
        featureCountLabel.text = "Features: \(currentFeatureCount)"
        reloadSource()
    }

    @objc
    private func sliderChanged() {
        currentFeatureCount = Int(featureCountSlider.value)
        featureCountLabel.text = "Features: \(currentFeatureCount)"
    }

    private func makeGeoJSONSource(featureCount: Int) -> MLNShapeSource {
        let centerLat = 45.52
        let centerLng = -122.64
        let spread = 0.05

        var featuresJSON = [String]()
        featuresJSON.reserveCapacity(featureCount)

        for i in 0 ..< featureCount {
            let row = i / 150
            let col = i % 150
            let lat = centerLat - spread + Double(row) * (2 * spread / 120)
            let lng = centerLng - spread + Double(col) * (2 * spread / 150)
            featuresJSON.append("""
            {"type":"Feature","id":"feat-\(i)","geometry":{"type":"Point","coordinates":[\(lng),\(lat)]},"properties":{"id":"feat-\(i)","type":"seat"}}
            """)
        }

        let geoJSON = """
        {"type":"FeatureCollection","features":[\(featuresJSON.joined(separator: ","))]}
        """

        let data = Data(geoJSON.utf8)
        let shape = try! MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
        return MLNShapeSource(identifier: Constants.sourceID, shape: shape, options: nil)
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

        featureCountLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        featureCountLabel.text = "Features: \(currentFeatureCount)"

        featureCountSlider.minimumValue = 3
        featureCountSlider.maximumValue = 20000
        featureCountSlider.value = Float(currentFeatureCount)
        featureCountSlider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        let buttonRow = UIStackView()
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fillEqually

        applyButton.setTitle("Apply State", for: .normal)
        applyButton.addTarget(self, action: #selector(applyFeatureState), for: .touchUpInside)

        retryButton.setTitle("Retry State", for: .normal)
        retryButton.addTarget(self, action: #selector(retryApplyState), for: .touchUpInside)

        reloadButton.setTitle("Reload Source", for: .normal)
        reloadButton.addTarget(self, action: #selector(reloadWithCurrentCount), for: .touchUpInside)

        buttonRow.addArrangedSubview(applyButton)
        buttonRow.addArrangedSubview(retryButton)
        buttonRow.addArrangedSubview(reloadButton)

        statusLabel.numberOfLines = 0
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .label
        statusLabel.text = "Waiting for style to load."

        let instructionsLabel = UILabel()
        instructionsLabel.numberOfLines = 0
        instructionsLabel.font = .systemFont(ofSize: 11)
        instructionsLabel.textColor = .secondaryLabel
        instructionsLabel.text = """
        Bug: With ~18000 features, circles stay gray (feature-state not applied).
        With 3 features, half turn green correctly.
        Use slider to adjust count, then Reload Source.
        """

        stack.addArrangedSubview(featureCountLabel)
        stack.addArrangedSubview(featureCountSlider)
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
}

struct FeatureStateScaledReproExampleRepresentable: UIViewControllerRepresentable {
    typealias UIViewControllerType = FeatureStateScaledReproExample

    func makeUIViewController(context _: Context) -> FeatureStateScaledReproExample {
        FeatureStateScaledReproExample()
    }

    func updateUIViewController(_: FeatureStateScaledReproExample, context _: Context) {}
}
