import EmbeddedMainModuleHost
import HamsterUIKit
import UIKit

@MainActor
final class VoiceBytePasteSlotPickerViewController: NibLessViewController {
  private let summaries: [EmbeddedMainModuleHostSlotSummary]
  private let onSelect: (Int) -> Void

  private lazy var titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 20, weight: .bold)
    label.textColor = .label
    label.text = "选择格子"
    return label
  }()

  private lazy var subtitleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .regular)
    label.textColor = .secondaryLabel
    label.text = "仅可选未解锁格子"
    return label
  }()

  private lazy var closeButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("取消", for: .normal)
    button.addTarget(self, action: #selector(handleCloseTap), for: .touchUpInside)
    return button
  }()

  private lazy var collectionView: UICollectionView = {
    let layout = UICollectionViewFlowLayout()
    layout.minimumLineSpacing = 12
    layout.minimumInteritemSpacing = 12
    layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 20, right: 16)
    let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.alwaysBounceVertical = true
    view.dataSource = self
    view.delegate = self
    view.register(VoiceBytePasteSlotPickerCell.self, forCellWithReuseIdentifier: VoiceBytePasteSlotPickerCell.reuseIdentifier)
    return view
  }()

  init(
    summaries: [EmbeddedMainModuleHostSlotSummary],
    onSelect: @escaping (Int) -> Void
  ) {
    self.summaries = summaries
    self.onSelect = onSelect
    super.init()
    modalPresentationStyle = .pageSheet
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    setupView()
  }

  private func setupView() {
    view.addSubview(closeButton)
    view.addSubview(titleLabel)
    view.addSubview(subtitleLabel)
    view.addSubview(collectionView)

    NSLayoutConstraint.activate([
      closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

      titleLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
      titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),

      subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
      subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      collectionView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
      collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
    ])
  }

  @objc private func handleCloseTap() {
    dismiss(animated: true)
  }

  private func slotLabel(for index: Int) -> String {
    String(format: "%02X", index)
  }
}

extension VoiceBytePasteSlotPickerViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    summaries.count
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let summary = summaries[indexPath.item]
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: VoiceBytePasteSlotPickerCell.reuseIdentifier,
      for: indexPath
    ) as! VoiceBytePasteSlotPickerCell
    cell.configure(
      title: slotLabel(for: summary.index),
      previewText: summary.isEmpty ? "空格子" : summary.previewText,
      isLocked: summary.isLocked
    )
    return cell
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    let summary = summaries[indexPath.item]
    guard !summary.isLocked else { return }
    dismiss(animated: true) { [onSelect] in
      onSelect(summary.index)
    }
  }

  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    let horizontalInset: CGFloat = 16 * 2
    let spacing: CGFloat = 12 * 3
    let width = floor((collectionView.bounds.width - horizontalInset - spacing) / 4)
    return CGSize(width: max(width, 72), height: 88)
  }
}

private final class VoiceBytePasteSlotPickerCell: UICollectionViewCell {
  static let reuseIdentifier = "VoiceBytePasteSlotPickerCell"

  private let titleLabel = UILabel()
  private let previewLabel = UILabel()
  private let lockView = UIImageView(image: UIImage(systemName: "lock.fill"))

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.backgroundColor = .secondarySystemGroupedBackground
    contentView.layer.cornerRadius = 12
    contentView.layer.borderWidth = 1
    contentView.layer.borderColor = UIColor.separator.cgColor

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
    titleLabel.textColor = .secondaryLabel

    previewLabel.translatesAutoresizingMaskIntoConstraints = false
    previewLabel.font = .systemFont(ofSize: 13, weight: .medium)
    previewLabel.textColor = .label
    previewLabel.numberOfLines = 2

    lockView.translatesAutoresizingMaskIntoConstraints = false
    lockView.tintColor = .secondaryLabel

    contentView.addSubview(titleLabel)
    contentView.addSubview(previewLabel)
    contentView.addSubview(lockView)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: lockView.leadingAnchor, constant: -8),

      lockView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
      lockView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      lockView.widthAnchor.constraint(equalToConstant: 12),
      lockView.heightAnchor.constraint(equalToConstant: 12),

      previewLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
      previewLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
      previewLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
      previewLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(title: String, previewText: String, isLocked: Bool) {
    titleLabel.text = title
    previewLabel.text = previewText
    lockView.isHidden = !isLocked
    contentView.alpha = isLocked ? 0.45 : 1.0
  }
}
