import Combine
import HamsterUIKit
import UIKit

public class FullAccessGuideViewController: NibLessViewController {
  private let viewModel: FullAccessGuideViewModel

  // MARK: - UI Components

  private lazy var scrollView: UIScrollView = {
    let scrollView = UIScrollView()
    scrollView.alwaysBounceVertical = true
    return scrollView
  }()

  private lazy var stackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 24
    stack.alignment = .fill
    stack.isLayoutMarginsRelativeArrangement = true
    stack.layoutMargins = UIEdgeInsets(top: 20, left: 16, bottom: 40, right: 16)
    return stack
  }()

  // 功能说明列表容器
  private lazy var featuresStack: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 20
    return stack
  }()

  // 隐私说明容器
  private lazy var privacyContainer: UIView = {
    let view = UIView()
    view.backgroundColor = UIColor.secondarySystemBackground
    view.layer.cornerRadius = 12
    view.clipsToBounds = true
    return view
  }()

  private lazy var privacyLabel: UILabel = {
    let label = UILabel()
    label.numberOfLines = 0
    label.font = .preferredFont(forTextStyle: .subheadline)
    label.textColor = .secondaryLabel
    return label
  }()

  // 底部操作区域
  private lazy var actionLabel: UILabel = {
    let label = UILabel()
    label.textAlignment = .center
    label.font = .preferredFont(forTextStyle: .footnote)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    return label
  }()

  private lazy var actionButton: UIButton = {
    var config = UIButton.Configuration.filled()
    config.cornerStyle = .capsule
    config.buttonSize = .large
    config.title = "打开设置"
    
    let button = UIButton(configuration: config)
    button.addTarget(self, action: #selector(handleActionButton), for: .touchUpInside)
    return button
  }()

  // MARK: - Lifecycle

  public init(viewModel: FullAccessGuideViewModel) {
    self.viewModel = viewModel
    super.init()
  }

  override public func viewDidLoad() {
    super.viewDidLoad()
    title = viewModel.title
    setupView()
    configureContent()
  }

  private func setupView() {
    view.backgroundColor = .systemBackground

    view.addSubview(scrollView)
    scrollView.addSubview(stackView)

    scrollView.fillSuperview()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
        stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
        stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
        stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
    ])

    // Build hierarchy
    // Action (顶部：按钮在上，提示文字在下)
    stackView.addArrangedSubview(actionButton)
    stackView.addArrangedSubview(actionLabel)

    // Separator
    let separator = UIView()
    separator.heightAnchor.constraint(equalToConstant: 24).isActive = true
    stackView.addArrangedSubview(separator)

    // Features (说明文案)
    stackView.addArrangedSubview(featuresStack)

    // Spacing
    let spacer = UIView()
    spacer.heightAnchor.constraint(equalToConstant: 20).isActive = true
    stackView.addArrangedSubview(spacer)

    // Privacy (底部)
    privacyContainer.addSubview(privacyLabel)
    privacyLabel.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        privacyLabel.topAnchor.constraint(equalTo: privacyContainer.topAnchor, constant: 16),
        privacyLabel.leadingAnchor.constraint(equalTo: privacyContainer.leadingAnchor, constant: 16),
        privacyLabel.trailingAnchor.constraint(equalTo: privacyContainer.trailingAnchor, constant: -16),
        privacyLabel.bottomAnchor.constraint(equalTo: privacyContainer.bottomAnchor, constant: -16)
    ])
    stackView.addArrangedSubview(privacyContainer)
  }

  private func configureContent() {
    // Fill Features
    for item in viewModel.guideItems {
      let itemStack = UIStackView()
      itemStack.axis = .horizontal
      itemStack.alignment = .top
      itemStack.spacing = 16

      let iconConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
      let icon = UIImageView(image: UIImage(systemName: item.icon, withConfiguration: iconConfig))
      icon.tintColor = .systemBlue
      icon.contentMode = .center
      icon.setContentHuggingPriority(.required, for: .horizontal)
      icon.widthAnchor.constraint(equalToConstant: 30).isActive = true

      let textStack = UIStackView()
      textStack.axis = .vertical
      textStack.spacing = 4
      
      let titleLabel = UILabel()
      titleLabel.text = item.title
      titleLabel.font = .preferredFont(forTextStyle: .headline)
      
      let descLabel = UILabel()
      descLabel.text = item.description
      descLabel.font = .preferredFont(forTextStyle: .body)
      descLabel.textColor = .secondaryLabel
      descLabel.numberOfLines = 0

      textStack.addArrangedSubview(titleLabel)
      textStack.addArrangedSubview(descLabel)

      itemStack.addArrangedSubview(icon)
      itemStack.addArrangedSubview(textStack)
      
      featuresStack.addArrangedSubview(itemStack)
    }

    // Fill Privacy
    privacyLabel.text = viewModel.privacyPromise

    // Fill Action
    actionLabel.text = viewModel.actionGuide
  }

  @objc private func handleActionButton() {
    Task { @MainActor in
        viewModel.openSystemSettings()
    }
  }
}
