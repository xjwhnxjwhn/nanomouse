//
//  KeyboardVisualEffectPreviewTableViewCell.swift
//
//
//  Created by Codex on 2026/05/24.
//

import HamsterUIKit
import UIKit

final class KeyboardVisualEffectPreviewTableViewCell: NibLessTableViewCell {
  static let identifier = "KeyboardVisualEffectPreviewTableViewCell"

  private var settingItem: SettingItemModel?

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .preferredFont(forTextStyle: .body)
    label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    return label
  }()

  private let valueLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
    label.textColor = .secondaryLabel
    label.textAlignment = .right
    label.widthAnchor.constraint(equalToConstant: 52).isActive = true
    return label
  }()

  private let valueSlider: UISlider = {
    let slider = UISlider()
    slider.translatesAutoresizingMaskIntoConstraints = false
    slider.minimumValue = 0
    slider.maximumValue = 100
    slider.isContinuous = true
    return slider
  }()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    setupView()
  }

  func updateWithSettingItem(_ item: SettingItemModel) {
    settingItem = item
    titleLabel.text = item.text
    valueSlider.minimumValue = Float(item.minValue)
    valueSlider.maximumValue = Float(item.maxValue > item.minValue ? item.maxValue : 100)
    updateSliderValueFromSettingItem()
  }

  private func setupView() {
    selectionStyle = .none
    valueSlider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)

    contentView.addSubview(titleLabel)
    contentView.addSubview(valueLabel)
    contentView.addSubview(valueSlider)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      titleLabel.widthAnchor.constraint(equalToConstant: 126),
      titleLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),
      titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

      valueSlider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
      valueSlider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -8),
      valueSlider.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

      valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
    ])
  }

  @objc private func sliderValueChanged() {
    let percent = Int(valueSlider.value.rounded())
    valueSlider.value = Float(percent)
    valueLabel.text = "\(percent)%"
    settingItem?.valueChangeHandled?(Double(percent))
  }

  private func updateSliderValueFromSettingItem() {
    let rawValue = Int(settingItem?.textValue?() ?? "") ?? 100
    let percent = max(Int(valueSlider.minimumValue), min(Int(valueSlider.maximumValue), rawValue))
    valueSlider.value = Float(percent)
    valueLabel.text = "\(percent)%"
  }
}
