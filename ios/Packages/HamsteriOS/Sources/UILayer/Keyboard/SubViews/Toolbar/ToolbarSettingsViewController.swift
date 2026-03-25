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
  private let completer = MKLocalSearchCompleter()
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private let emptyLabel: UILabel = {
    let label = UILabel()
    label.textAlignment = .center
    label.textColor = .secondaryLabel
    label.font = .systemFont(ofSize: 15)
    label.numberOfLines = 0
    return label
  }()
  private lazy var searchController: UISearchController = {
    let controller = UISearchController(searchResultsController: nil)
    controller.searchResultsUpdater = self
    controller.obscuresBackgroundDuringPresentation = false
    controller.searchBar.placeholder = "搜索城市"
    controller.searchBar.autocapitalizationType = .words
    return controller
  }()
  private var completions: [MKLocalSearchCompletion] = [] {
    didSet {
      updateEmptyState()
      tableView.reloadData()
    }
  }
  private var isResolvingSelection = false {
    didSet {
      tableView.allowsSelection = !isResolvingSelection
      navigationItem.searchController?.searchBar.isUserInteractionEnabled = !isResolvingSelection
    }
  }

  init(keyboardSettingsViewModel: KeyboardSettingsViewModel) {
    self.keyboardSettingsViewModel = keyboardSettingsViewModel
    super.init()
    completer.delegate = self
    completer.resultTypes = [.address]
  }

  override func loadView() {
    title = "选择固定城市"
    view = UIView()
    view.backgroundColor = .systemBackground

    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    view.addSubview(tableView)
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: view.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])

    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = false
    definesPresentationContext = true
    updateEmptyState()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    let currentQuery = keyboardSettingsViewModel.weatherIndicatorFixedLocationName
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !currentQuery.isEmpty {
      navigationItem.searchController?.searchBar.text = currentQuery
      completer.queryFragment = currentQuery
    }
  }

  private func updateEmptyState() {
    if let query = navigationItem.searchController?.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines),
       !query.isEmpty
    {
      emptyLabel.text = completions.isEmpty ? "没有找到匹配的城市，请换个关键词。" : nil
    } else {
      emptyLabel.text = "请输入城市名，例如东京、上海或 New York。"
    }
    tableView.backgroundView = emptyLabel.text == nil ? nil : emptyLabel
  }

  private func resolveSelection(_ completion: MKLocalSearchCompletion) {
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
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        let response = try await search.start()
        guard let mapItem = response.mapItems.first(where: { $0.placemark.location != nil }),
              let location = mapItem.placemark.location
        else {
          throw NSError(
            domain: "WeatherIndicatorCityPicker",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "没有解析到这个固定城市，请重新选择。"]
          )
        }
        let displayName = Self.displayName(for: mapItem.placemark, completion: completion)
        await MainActor.run {
          self.keyboardSettingsViewModel.setWeatherIndicatorFixedLocation(
            name: displayName,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
          )
          self.navigationController?.popViewController(animated: true)
        }
      } catch {
        await MainActor.run {
          let alert = UIAlertController(
            title: "城市选择失败",
            message: error.localizedDescription,
            preferredStyle: .alert
          )
          alert.addAction(UIAlertAction(title: "知道了", style: .default))
          self.present(alert, animated: true)
        }
      }
    }
  }

  private static func displayName(for placemark: MKPlacemark, completion: MKLocalSearchCompletion) -> String {
    if let locality = placemark.locality, !locality.isEmpty {
      if let administrativeArea = placemark.administrativeArea,
         !administrativeArea.isEmpty,
         administrativeArea != locality
      {
        return "\(locality), \(administrativeArea)"
      }
      return locality
    }
    if let name = placemark.name, !name.isEmpty {
      return name
    }
    let subtitle = completion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if subtitle.isEmpty {
      return completion.title
    }
    return "\(completion.title), \(subtitle)"
  }
}

extension WeatherIndicatorCityPickerViewController: UISearchResultsUpdating {
  func updateSearchResults(for searchController: UISearchController) {
    let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !query.isEmpty else {
      completions = []
      completer.queryFragment = ""
      return
    }
    completer.queryFragment = query
  }
}

extension WeatherIndicatorCityPickerViewController: MKLocalSearchCompleterDelegate {
  func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
    completions = completer.results.filter {
      !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
    completions = []
  }
}

extension WeatherIndicatorCityPickerViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    completions.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let identifier = "WeatherIndicatorCityCell"
    let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
      ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
    let completion = completions[indexPath.row]
    var config = cell.defaultContentConfiguration()
    config.text = completion.title
    let subtitle = completion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    config.secondaryText = subtitle.isEmpty ? "地图搜索结果" : subtitle
    config.secondaryTextProperties.color = .secondaryLabel
    config.image = UIImage(systemName: "mappin.and.ellipse")
    cell.contentConfiguration = config
    cell.accessoryType = .disclosureIndicator
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    resolveSelection(completions[indexPath.row])
  }
}
