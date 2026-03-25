//
//  CandidateTextBarSettingViewController.swift
//  Hamster
//
//  Created by morse on 2023/6/15.
//

import Combine
import HamsterUIKit
import MapKit
import UIKit

public class ToolbarSettingsViewController: NibLessViewController {
  private let keyboardSettingsViewModel: KeyboardSettingsViewModel
  private var subscriptions = Set<AnyCancellable>()
  private var toolbarSettingsRootView: ToolbarSettingsRootView? {
    view as? ToolbarSettingsRootView
  }

  init(keyboardSettingsViewModel: KeyboardSettingsViewModel) {
    self.keyboardSettingsViewModel = keyboardSettingsViewModel

    super.init()

    keyboardSettingsViewModel.weatherIndicatorCityPickerPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        self?.openWeatherIndicatorCityPicker()
      }
      .store(in: &subscriptions)
  }

  override public func loadView() {
    title = "候选栏"
    view = ToolbarSettingsRootView(keyboardSettingsViewModel: keyboardSettingsViewModel)
  }

  override public func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    toolbarSettingsRootView?.scrollToPendingFocusIfNeeded(animated: true)
  }

  private func openWeatherIndicatorCityPicker() {
    let viewController = WeatherIndicatorCityPickerViewController(keyboardSettingsViewModel: keyboardSettingsViewModel)
    navigationController?.pushViewController(viewController, animated: true)
  }
}

private final class WeatherIndicatorCityPickerViewController: NibLessViewController {
  private let keyboardSettingsViewModel: KeyboardSettingsViewModel
  private let geocoder = CLGeocoder()
  private let mapView = MKMapView()
  private let pinImageView: UIImageView = {
    let imageView = UIImageView(image: UIImage(systemName: "mappin.circle.fill"))
    imageView.tintColor = .systemRed
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.isUserInteractionEnabled = false
    return imageView
  }()
  private let helperLabel: UILabel = {
    let label = UILabel()
    label.text = "拖动地图，让探针落在要使用的城市上。"
    label.font = .systemFont(ofSize: 13)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()
  private let selectedTitleLabel: UILabel = {
    let label = UILabel()
    label.font = .boldSystemFont(ofSize: 17)
    label.textColor = .label
    label.numberOfLines = 1
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()
  private let selectedSubtitleLabel: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 13)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()
  private lazy var confirmButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.configuration = .filled()
    button.configuration?.title = "使用当前位置"
    button.addTarget(self, action: #selector(confirmSelection), for: .touchUpInside)
    button.isEnabled = false
    return button
  }()
  private let loadingIndicator: UIActivityIndicatorView = {
    let indicator = UIActivityIndicatorView(style: .medium)
    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.hidesWhenStopped = true
    return indicator
  }()
  private var reverseGeocodeTask: Task<Void, Never>?
  private var selectedCoordinate: CLLocationCoordinate2D?
  private var selectedLocationName: String?
  private var isResolvingSelection = false {
    didSet {
      navigationItem.rightBarButtonItem?.isEnabled = !isResolvingSelection
      confirmButton.isEnabled = !isResolvingSelection && selectedCoordinate != nil && selectedLocationName != nil
      mapView.isUserInteractionEnabled = !isResolvingSelection
      if isResolvingSelection {
        loadingIndicator.startAnimating()
      } else {
        loadingIndicator.stopAnimating()
      }
    }
  }

  init(keyboardSettingsViewModel: KeyboardSettingsViewModel) {
    self.keyboardSettingsViewModel = keyboardSettingsViewModel
    super.init()
  }

  override func loadView() {
    title = "选择固定城市"
    view = UIView()
    view.backgroundColor = .systemBackground

    mapView.translatesAutoresizingMaskIntoConstraints = false
    mapView.delegate = self
    mapView.showsCompass = true
    mapView.pointOfInterestFilter = .excludingAll
    view.addSubview(mapView)
    view.addSubview(pinImageView)
    view.addSubview(helperLabel)
    view.addSubview(selectedTitleLabel)
    view.addSubview(selectedSubtitleLabel)
    view.addSubview(confirmButton)
    view.addSubview(loadingIndicator)

    NSLayoutConstraint.activate([
      mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      mapView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),

      pinImageView.centerXAnchor.constraint(equalTo: mapView.centerXAnchor),
      pinImageView.centerYAnchor.constraint(equalTo: mapView.centerYAnchor, constant: -18),
      pinImageView.widthAnchor.constraint(equalToConstant: 36),
      pinImageView.heightAnchor.constraint(equalToConstant: 36),

      helperLabel.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: 16),
      helperLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      helperLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      selectedTitleLabel.topAnchor.constraint(equalTo: helperLabel.bottomAnchor, constant: 20),
      selectedTitleLabel.leadingAnchor.constraint(equalTo: helperLabel.leadingAnchor),
      selectedTitleLabel.trailingAnchor.constraint(equalTo: helperLabel.trailingAnchor),

      selectedSubtitleLabel.topAnchor.constraint(equalTo: selectedTitleLabel.bottomAnchor, constant: 8),
      selectedSubtitleLabel.leadingAnchor.constraint(equalTo: helperLabel.leadingAnchor),
      selectedSubtitleLabel.trailingAnchor.constraint(equalTo: helperLabel.trailingAnchor),

      confirmButton.topAnchor.constraint(equalTo: selectedSubtitleLabel.bottomAnchor, constant: 24),
      confirmButton.leadingAnchor.constraint(equalTo: helperLabel.leadingAnchor),
      confirmButton.trailingAnchor.constraint(equalTo: helperLabel.trailingAnchor),
      confirmButton.heightAnchor.constraint(equalToConstant: 50),

      loadingIndicator.centerYAnchor.constraint(equalTo: helperLabel.centerYAnchor),
      loadingIndicator.trailingAnchor.constraint(equalTo: helperLabel.trailingAnchor)
    ])

    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "location.magnifyingglass"),
      style: .plain,
      target: self,
      action: #selector(openSearch)
    )

    selectedTitleLabel.text = "正在等待地图定位..."
    selectedSubtitleLabel.text = "请拖动地图，系统会按探针所在位置解析城市。"
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureInitialRegion()
    scheduleReverseGeocode(for: mapView.centerCoordinate)
  }

  private func configureInitialRegion() {
    if let latitude = keyboardSettingsViewModel.weatherIndicatorFixedLatitude,
       let longitude = keyboardSettingsViewModel.weatherIndicatorFixedLongitude
    {
      let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
      let region = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35))
      mapView.setRegion(region, animated: false)
      return
    }
    let fallback = CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)
    let region = MKCoordinateRegion(center: fallback, span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8))
    mapView.setRegion(region, animated: false)
  }

  @objc private func openSearch() {
    let alert = UIAlertController(title: "搜索城市", message: nil, preferredStyle: .alert)
    alert.addTextField {
      $0.placeholder = "例如：东京 / 上海 / New York"
      $0.autocapitalizationType = .words
      let currentQuery = self.keyboardSettingsViewModel.weatherIndicatorFixedLocationName
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !currentQuery.isEmpty {
        $0.text = currentQuery
      }
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "搜索", style: .default) { [weak self, weak alert] _ in
      guard let self,
            let query = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !query.isEmpty
      else { return }
      self.searchCity(named: query)
    })
    present(alert, animated: true)
  }

  private func searchCity(named query: String) {
    guard !isResolvingSelection else { return }
    isResolvingSelection = true
    Task { [weak self] in
      guard let self else { return }
      defer {
        Task { @MainActor [weak self] in
          self?.isResolvingSelection = false
        }
      }
      do {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        let response = try await MKLocalSearch(request: request).start()
        guard let mapItem = response.mapItems.first(where: { $0.placemark.location != nil }),
              let location = mapItem.placemark.location
        else {
          throw NSError(
            domain: "WeatherIndicatorCityPicker",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "没有解析到这个固定城市，请重新搜索。"]
          )
        }
        let region = MKCoordinateRegion(
          center: location.coordinate,
          span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )
        await MainActor.run {
          self.mapView.setRegion(region, animated: true)
          self.scheduleReverseGeocode(for: location.coordinate)
        }
      } catch {
        await MainActor.run {
          self.presentError(title: "城市搜索失败", message: error.localizedDescription)
        }
      }
    }
  }

  private func scheduleReverseGeocode(for coordinate: CLLocationCoordinate2D) {
    reverseGeocodeTask?.cancel()
    reverseGeocodeTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else { return }
      await self?.reverseGeocode(coordinate: coordinate)
    }
  }

  @MainActor
  private func reverseGeocode(coordinate: CLLocationCoordinate2D) async {
    guard CLLocationCoordinate2DIsValid(coordinate) else { return }
    isResolvingSelection = true
    selectedCoordinate = nil
    selectedLocationName = nil
    selectedTitleLabel.text = "正在解析城市..."
    selectedSubtitleLabel.text = "请稍候，系统正在读取探针位置。"

    do {
      let placemarks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
      guard let placemark = placemarks.first else {
        throw NSError(
          domain: "WeatherIndicatorCityPicker",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "当前探针位置没有解析到可用城市，请继续移动地图。"]
        )
      }
      let name = Self.displayName(for: placemark, fallbackCoordinate: coordinate)
      let detail = Self.detailText(for: placemark, coordinate: coordinate)
      selectedCoordinate = coordinate
      selectedLocationName = name
      selectedTitleLabel.text = name
      selectedSubtitleLabel.text = detail
    } catch {
      selectedTitleLabel.text = "当前位置不可用"
      selectedSubtitleLabel.text = error.localizedDescription
      selectedCoordinate = nil
      selectedLocationName = nil
    }
    isResolvingSelection = false
  }

  @objc private func confirmSelection() {
    guard let coordinate = selectedCoordinate,
          let name = selectedLocationName,
          !isResolvingSelection
    else { return }
    keyboardSettingsViewModel.setWeatherIndicatorFixedLocation(
      name: name,
      latitude: coordinate.latitude,
      longitude: coordinate.longitude
    )
    navigationController?.popViewController(animated: true)
  }

  private func presentError(title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .default))
    present(alert, animated: true)
  }

  private static func displayName(for placemark: CLPlacemark, fallbackCoordinate: CLLocationCoordinate2D) -> String {
    if let locality = placemark.locality, !locality.isEmpty {
      if let administrativeArea = placemark.administrativeArea,
         !administrativeArea.isEmpty,
         administrativeArea != locality
      {
        return "\(locality), \(administrativeArea)"
      }
      return locality
    }
    if let subAdministrativeArea = placemark.subAdministrativeArea, !subAdministrativeArea.isEmpty {
      return subAdministrativeArea
    }
    if let name = placemark.name, !name.isEmpty {
      return name
    }
    return String(format: "%.4f, %.4f", fallbackCoordinate.latitude, fallbackCoordinate.longitude)
  }

  private static func detailText(for placemark: CLPlacemark, coordinate: CLLocationCoordinate2D) -> String {
    let components = [
      placemark.country,
      placemark.administrativeArea,
      placemark.locality,
      placemark.subLocality,
      placemark.thoroughfare
    ].compactMap { value -> String? in
      guard let value else { return nil }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    if !components.isEmpty {
      return components.joined(separator: " · ")
    }
    return String(format: "纬度 %.4f，经度 %.4f", coordinate.latitude, coordinate.longitude)
  }
}

extension WeatherIndicatorCityPickerViewController: MKMapViewDelegate {
  func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
    scheduleReverseGeocode(for: mapView.centerCoordinate)
  }
}
