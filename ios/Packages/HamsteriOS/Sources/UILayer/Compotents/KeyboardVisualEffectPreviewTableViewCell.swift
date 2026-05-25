//
//  KeyboardVisualEffectPreviewTableViewCell.swift
//
//
//  Created by Codex on 2026/05/24.
//

import HamsterKeyboardKit
import HamsterUIKit
import UIKit

final class KeyboardVisualEffectPreviewTableViewCell: NibLessTableViewCell {
  static let identifier = "KeyboardVisualEffectPreviewTableViewCell"

  private var settingItem: SettingItemModel?
  private var calloutVisible = false
  private let calloutMaskLayer = CAShapeLayer()

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

  private let previewBackdrop: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.clipsToBounds = true
    view.layer.cornerCurve = .continuous
    view.layer.cornerRadius = 12
    view.backgroundColor = .secondarySystemGroupedBackground
    return view
  }()

  private let iconImageView: UIImageView = {
    let imageView = UIImageView(image: UIImage(named: "Hamster") ?? UIImage(named: "NanomouseLaunch"))
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFill
    imageView.alpha = 0.84
    return imageView
  }()

  private let iconContrastView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isUserInteractionEnabled = false
    return view
  }()

  private let previewBackgroundEffectView: UIVisualEffectView = {
    let view = UIVisualEffectView(effect: nil)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.clipsToBounds = true
    view.layer.cornerCurve = .continuous
    view.layer.cornerRadius = 12
    view.layer.shadowOffset = CGSize(width: 0, height: 4)
    view.layer.shadowRadius = 12
    return view
  }()

  private let previewBackgroundTintView = UIView(frame: .zero)

  private let previewKeyEffectView: UIVisualEffectView = {
    let view = UIVisualEffectView(effect: nil)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.clipsToBounds = true
    view.layer.cornerCurve = .continuous
    view.layer.cornerRadius = 11
    view.layer.shadowOffset = CGSize(width: 0, height: 3)
    view.layer.shadowRadius = 8
    return view
  }()

  private let previewKeyTintView = UIView(frame: .zero)
  private let previewKeyWhiteOverlayView = UIView(frame: .zero)
  private let previewKeyStrokeLayer = CAShapeLayer()

  private let previewKeyLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "A"
    label.textAlignment = .center
    label.font = .systemFont(ofSize: 26, weight: .semibold)
    label.textColor = .label
    return label
  }()

  private let calloutEffectView: UIVisualEffectView = {
    let view = UIVisualEffectView(effect: nil)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.clipsToBounds = true
    view.isHidden = true
    view.layer.cornerCurve = .continuous
    view.layer.cornerRadius = 18
    return view
  }()

  private let calloutTintView = UIView(frame: .zero)

  private let calloutLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "A"
    label.textAlignment = .center
    label.font = .systemFont(ofSize: 32, weight: .semibold)
    label.textColor = .label
    return label
  }()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    setupView()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    previewKeyTintView.frame = previewKeyEffectView.contentView.bounds
    previewKeyWhiteOverlayView.frame = previewKeyEffectView.contentView.bounds
    previewKeyStrokeLayer.frame = previewKeyEffectView.bounds
    previewKeyStrokeLayer.path = UIBezierPath(
      roundedRect: previewKeyEffectView.bounds,
      cornerRadius: previewKeyEffectView.layer.cornerRadius
    ).cgPath
    previewBackgroundTintView.frame = previewBackgroundEffectView.contentView.bounds
    calloutTintView.frame = calloutEffectView.contentView.bounds
    calloutMaskLayer.frame = calloutEffectView.bounds
    calloutMaskLayer.path = CAShapeLayer.inputCalloutPath(
      popSize: calloutEffectView.bounds.size,
      originButtonSize: previewKeyEffectView.bounds.size,
      cornerRadius: 18,
      buttonCornerRadius: 11,
      leftTopPointContainsSuperview: false,
      rightTopPointContainsSuperview: false
    ).cgPath
  }

  func updateWithSettingItem(_ item: SettingItemModel) {
    settingItem = item
    titleLabel.text = item.text
    valueSlider.minimumValue = Float(item.minValue)
    valueSlider.maximumValue = Float(item.maxValue > item.minValue ? item.maxValue : 100)
    updateSliderValueFromSettingItem()
    refreshPreview()
  }

  private func setupView() {
    selectionStyle = .none
    valueSlider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
    previewBackdrop.isHidden = true

    contentView.addSubview(titleLabel)
    contentView.addSubview(valueLabel)
    contentView.addSubview(valueSlider)
    contentView.addSubview(previewBackdrop)
    previewBackdrop.addSubview(iconImageView)
    previewBackdrop.addSubview(previewBackgroundEffectView)
    previewBackdrop.addSubview(iconContrastView)
    previewBackdrop.addSubview(calloutEffectView)
    previewBackdrop.addSubview(previewKeyEffectView)
    previewBackgroundEffectView.contentView.addSubview(previewBackgroundTintView)
    previewKeyEffectView.contentView.addSubview(previewKeyTintView)
    previewKeyEffectView.contentView.addSubview(previewKeyWhiteOverlayView)
    previewKeyEffectView.contentView.addSubview(previewKeyLabel)
    previewKeyEffectView.layer.addSublayer(previewKeyStrokeLayer)
    calloutEffectView.contentView.addSubview(calloutTintView)
    calloutEffectView.contentView.addSubview(calloutLabel)
    calloutEffectView.layer.mask = calloutMaskLayer

    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleKeyLongPress(_:)))
    longPress.minimumPressDuration = 0.18
    previewKeyEffectView.addGestureRecognizer(longPress)
    previewKeyEffectView.isUserInteractionEnabled = true

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

      valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
      valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

      valueSlider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
      valueSlider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      valueSlider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

      previewBackdrop.topAnchor.constraint(equalTo: valueSlider.bottomAnchor, constant: 8),
      previewBackdrop.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      previewBackdrop.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      previewBackdrop.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
      previewBackdrop.heightAnchor.constraint(equalToConstant: 0),

      iconImageView.topAnchor.constraint(equalTo: previewBackdrop.topAnchor),
      iconImageView.leadingAnchor.constraint(equalTo: previewBackdrop.leadingAnchor),
      iconImageView.trailingAnchor.constraint(equalTo: previewBackdrop.trailingAnchor),
      iconImageView.bottomAnchor.constraint(equalTo: previewBackdrop.bottomAnchor),

      iconContrastView.topAnchor.constraint(equalTo: previewBackdrop.topAnchor),
      iconContrastView.leadingAnchor.constraint(equalTo: previewBackdrop.leadingAnchor),
      iconContrastView.trailingAnchor.constraint(equalTo: previewBackdrop.trailingAnchor),
      iconContrastView.bottomAnchor.constraint(equalTo: previewBackdrop.bottomAnchor),

      previewBackgroundEffectView.topAnchor.constraint(equalTo: previewBackdrop.topAnchor),
      previewBackgroundEffectView.leadingAnchor.constraint(equalTo: previewBackdrop.leadingAnchor),
      previewBackgroundEffectView.trailingAnchor.constraint(equalTo: previewBackdrop.trailingAnchor),
      previewBackgroundEffectView.bottomAnchor.constraint(equalTo: previewBackdrop.bottomAnchor),

      previewKeyEffectView.centerXAnchor.constraint(equalTo: previewBackdrop.centerXAnchor),
      previewKeyEffectView.bottomAnchor.constraint(equalTo: previewBackdrop.bottomAnchor, constant: -18),
      previewKeyEffectView.widthAnchor.constraint(equalToConstant: 82),
      previewKeyEffectView.heightAnchor.constraint(equalToConstant: 54),

      previewKeyLabel.topAnchor.constraint(equalTo: previewKeyEffectView.contentView.topAnchor),
      previewKeyLabel.leadingAnchor.constraint(equalTo: previewKeyEffectView.contentView.leadingAnchor),
      previewKeyLabel.trailingAnchor.constraint(equalTo: previewKeyEffectView.contentView.trailingAnchor),
      previewKeyLabel.bottomAnchor.constraint(equalTo: previewKeyEffectView.contentView.bottomAnchor),

      calloutEffectView.centerXAnchor.constraint(equalTo: previewKeyEffectView.centerXAnchor),
      calloutEffectView.bottomAnchor.constraint(equalTo: previewKeyEffectView.bottomAnchor),
      calloutEffectView.widthAnchor.constraint(equalToConstant: 110),
      calloutEffectView.heightAnchor.constraint(equalToConstant: 104),

      calloutLabel.topAnchor.constraint(equalTo: calloutEffectView.contentView.topAnchor, constant: 4),
      calloutLabel.leadingAnchor.constraint(equalTo: calloutEffectView.contentView.leadingAnchor),
      calloutLabel.trailingAnchor.constraint(equalTo: calloutEffectView.contentView.trailingAnchor),
      calloutLabel.heightAnchor.constraint(equalToConstant: 56)
    ])
  }

  @objc private func sliderValueChanged() {
    let percent = Int(valueSlider.value.rounded())
    valueSlider.value = Float(percent)
    valueLabel.text = "\(percent)%"
    settingItem?.valueChangeHandled?(Double(percent))
    refreshPreview()
  }

  @objc private func handleKeyLongPress(_ sender: UILongPressGestureRecognizer) {
    switch sender.state {
    case .began, .changed:
      calloutVisible = true
    default:
      calloutVisible = false
    }
    refreshPreview()
  }

  private func refreshPreview() {
    guard !previewBackdrop.isHidden else { return }
    var configuration = HamsterAppDependencyContainer.shared.configuration.keyboard?.visualEffect ?? KeyboardVisualEffectConfiguration()
    configuration.keyboardBackgroundStyle = nil
    let fixedBackgroundConfiguration = KeyboardVisualEffectConfiguration()
    let userInterfaceStyle = settingItem?.visualEffectPreviewUserInterfaceStyle
      ?? (traitCollection.userInterfaceStyle == .dark ? UIUserInterfaceStyle.dark : .light)
    let previewTraitCollection = UITraitCollection(userInterfaceStyle: userInterfaceStyle)
    [previewBackdrop, previewBackgroundEffectView, previewKeyEffectView, calloutEffectView].forEach {
      $0.overrideUserInterfaceStyle = userInterfaceStyle
    }
    previewBackdrop.backgroundColor = (userInterfaceStyle == .dark ? UIColor.systemGray6 : .secondarySystemGroupedBackground)
      .resolvedColor(with: previewTraitCollection)
    iconImageView.alpha = 1
    iconContrastView.backgroundColor = (userInterfaceStyle == .dark
      ? UIColor.black.withAlphaComponent(0.10)
      : UIColor.black.withAlphaComponent(0.24))
      .resolvedColor(with: previewTraitCollection)
    previewKeyLabel.textColor = (userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.84) : .label)
      .resolvedColor(with: previewTraitCollection)
    calloutLabel.textColor = previewKeyLabel.textColor

    previewBackgroundEffectView.effect = KeyboardLiquidGlass.effect(
      userInterfaceStyle: userInterfaceStyle,
      configuration: fixedBackgroundConfiguration,
      target: .keyboardBackground
    )
    previewBackgroundTintView.backgroundColor = KeyboardLiquidGlass.tintColor(
      userInterfaceStyle: userInterfaceStyle,
      configuration: fixedBackgroundConfiguration,
      target: .keyboardBackground
    )
    previewBackgroundEffectView.layer.shadowColor = UIColor.black.cgColor
    previewBackgroundEffectView.layer.shadowOpacity = KeyboardLiquidGlass.shadowOpacity(
      userInterfaceStyle: userInterfaceStyle,
      configuration: fixedBackgroundConfiguration,
      target: .keyboardBackground
    )

    previewKeyEffectView.effect = KeyboardLiquidGlass.effect(
      userInterfaceStyle: userInterfaceStyle,
      configuration: configuration,
      target: .keySurface
    )
    previewKeyTintView.backgroundColor = KeyboardLiquidGlass.tintColor(
      userInterfaceStyle: userInterfaceStyle,
      configuration: configuration,
      target: .keySurface
    )
    let whiteOverlayIntensity = CGFloat(configuration.keySurfaceWhiteOverlayIntensity(for: userInterfaceStyle))
    let whiteOverlayMaximumAlpha: CGFloat = userInterfaceStyle == .dark ? 0.34 : 0.44
    previewKeyWhiteOverlayView.backgroundColor = UIColor.white.withAlphaComponent(
      whiteOverlayMaximumAlpha * whiteOverlayIntensity
    )
    previewKeyEffectView.layer.shadowOpacity = KeyboardLiquidGlass.shadowOpacity(
      userInterfaceStyle: userInterfaceStyle,
      configuration: configuration,
      target: .keySurface
    )
    previewKeyEffectView.layer.shadowColor = UIColor.black.cgColor
    let keyStrokeWidth = KeyboardLiquidGlass.defaultKeySurfaceStrokeWidth(
      userInterfaceStyle: userInterfaceStyle,
      configuration: configuration
    )
    previewKeyStrokeLayer.lineWidth = keyStrokeWidth
    previewKeyStrokeLayer.fillColor = UIColor.clear.cgColor
    previewKeyStrokeLayer.strokeColor = keyStrokeWidth > 0
      ? KeyboardLiquidGlass.strokeColor(
        userInterfaceStyle: userInterfaceStyle,
        configuration: configuration,
        target: .keySurface
      ).cgColor
      : UIColor.clear.cgColor

    calloutEffectView.effect = KeyboardLiquidGlass.effect(
      userInterfaceStyle: userInterfaceStyle,
      configuration: configuration,
      target: .keyInputCallout
    )
    calloutTintView.backgroundColor = KeyboardLiquidGlass.tintColor(
      userInterfaceStyle: userInterfaceStyle,
      configuration: configuration,
      target: .keyInputCallout
    )
    calloutEffectView.isHidden = !calloutVisible
    if calloutVisible {
      setNeedsLayout()
      layoutIfNeeded()
    }
  }

  private func updateSliderValueFromSettingItem() {
    let rawValue = Int(settingItem?.textValue?() ?? "") ?? 100
    let percent = max(Int(valueSlider.minimumValue), min(Int(valueSlider.maximumValue), rawValue))
    valueSlider.value = Float(percent)
    valueLabel.text = "\(percent)%"
  }
}
