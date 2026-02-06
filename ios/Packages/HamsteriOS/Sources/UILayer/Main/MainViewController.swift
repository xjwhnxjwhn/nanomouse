//
//  File.swift
//
//
//  Created by morse on 2023/7/5.
//

import Combine
import HamsterKit
import HamsterUIKit
import UIKit

protocol SubViewControllerFactory {
  func makeSettingsViewController() -> SettingsViewController
  func makeInputSchemaViewController() -> InputSchemaSelectViewController
  func makeFinderViewController() -> FinderViewController
  func makeKeyboardSettingsViewController() -> KeyboardSettingsViewController
  func makeKeyboardLayoutViewController() -> KeyboardLayoutViewController
  func makeKeyboardColorViewController() -> KeyboardColorViewController
  func makeKeyboardFeedbackViewController() -> KeyboardFeedbackViewController
  func makeUploadInputSchemaViewController() -> UploadInputSchemaViewController
  func makeAppleCloudViewController() -> AppleCloudViewController
  func makeBackupViewController() -> BackupViewController
  func makeAboutViewController() -> AboutViewController
  func makeRimeViewController() -> RimeViewController
  func makeFullAccessGuideViewController() -> FullAccessGuideViewController

}

open class MainViewController: UISplitViewController {
  private let mainViewModel: MainViewModel
  private let subViewControllerFactory: SubViewControllerFactory
  private let settingsViewController: SettingsViewController

  private lazy var inputSchemaViewController: InputSchemaSelectViewController
    = subViewControllerFactory.makeInputSchemaViewController()

  private lazy var finderViewController: FinderViewController
    = subViewControllerFactory.makeFinderViewController()

  private lazy var keyboardSettingsViewController: KeyboardSettingsViewController
    = subViewControllerFactory.makeKeyboardSettingsViewController()

  private lazy var keyboardLayoutViewController: KeyboardLayoutViewController
    = subViewControllerFactory.makeKeyboardLayoutViewController()

  private lazy var keyboardColorViewController: KeyboardColorViewController
    = subViewControllerFactory.makeKeyboardColorViewController()

  private lazy var keyboardFeedbackViewController: KeyboardFeedbackViewController
    = subViewControllerFactory.makeKeyboardFeedbackViewController()

  private lazy var uploadInputSchemaViewController: UploadInputSchemaViewController
    = subViewControllerFactory.makeUploadInputSchemaViewController()

  private lazy var rimeViewController: RimeViewController
    = subViewControllerFactory.makeRimeViewController()

  private lazy var backupViewController: BackupViewController
    = subViewControllerFactory.makeBackupViewController()

  private lazy var iCloudViewController: AppleCloudViewController
    = subViewControllerFactory.makeAppleCloudViewController()

  private lazy var aboutViewController: AboutViewController
    = subViewControllerFactory.makeAboutViewController()

  private lazy var fullAccessGuideViewController: FullAccessGuideViewController
    = subViewControllerFactory.makeFullAccessGuideViewController()

  private lazy var primaryNavigationViewController: UINavigationController = {
    let vc = UINavigationController(rootViewController: settingsViewController)
    return vc
  }()

  private lazy var secondaryNavigationViewController: UINavigationController = {
    let vc = UINavigationController(rootViewController: aboutViewController)
    return vc
  }()

  private var subscriptions = Set<AnyCancellable>()

  init(mainViewModel: MainViewModel, subViewControllerFactory: SubViewControllerFactory) {
    self.mainViewModel = mainViewModel
    self.subViewControllerFactory = subViewControllerFactory
    self.settingsViewController = subViewControllerFactory.makeSettingsViewController()

    super.init(style: .doubleColumn)
    self.delegate = self
    // primary 视图始终可见
    self.presentsWithGesture = false
    self.preferredDisplayMode = .twoBesideSecondary
    self.preferredSplitBehavior = .tile
    self.displayModeButtonVisibility = .never
    self.showsSecondaryOnlyButton = false
    self.setViewController(primaryNavigationViewController, for: .primary)
    self.setViewController(secondaryNavigationViewController, for: .secondary)
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - override UIViewController

extension MainViewController {
  override open func viewDidLoad() {
    super.viewDidLoad()

    /// 动态控制导航
    mainViewModel.subViewPublished
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] in
        self.navigationResponse(to: $0)
      }
      .store(in: &subscriptions)

    mainViewModel.shortcutItemTypePublished
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] type in
        Task {
          switch type {
          case .rimeDeploy:
            await rimeViewController.rimeViewModel.rimeDeploy()
          case .rimeSync:
            await rimeViewController.rimeViewModel.rimeSync()
          default:
            break
          }
        }
      }
      .store(in: &subscriptions)
  }
}

// MARK: - implementation UISplitViewControllerDelegate

extension MainViewController: UISplitViewControllerDelegate {
  public func splitViewController(_ svc: UISplitViewController, topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column) -> UISplitViewController.Column {
    /// 首选显示 primary 列
    return .primary
  }
}

// MARK: - custom method

extension MainViewController {
  func navigationResponse(to subView: SettingsSubView) {
    switch subView {
    case .inputSchema:
      presentInputSchemaViewController()
    case .finder:
      presentFinderViewController()
    case .uploadInputSchema:
      presentUploadInputSchemaViewController()
    case .keyboardSettings:
      presentKeyboardSettingsViewController()
    case .keyboardLayout:
      presentKeyboardLayoutViewController()
    case .colorSchema:
      presentKeyboardColorViewController()
    case .feedback:
      presentKeyboardFeedbackViewController()
    case .rime:
      presentRimeViewController()
    case .backup:
      presentBackupViewController()
    case .iCloud:
      presentAppleCloudViewController()
    case .about:
      presentAboutViewController()
    case .fullAccessGuide:
      presentFullAccessGuideViewController()
    case .main:
      presentMainViewController()
    default:
      return
    }
  }

  func presentMainViewController() {
    primaryNavigationViewController.popToRootViewController(animated: false)
  }

  func presentInputSchemaViewController() {
    presentViewController(inputSchemaViewController)
  }

  func presentFinderViewController() {
    presentViewController(finderViewController)
  }

  func presentUploadInputSchemaViewController() {
    presentViewController(uploadInputSchemaViewController)
  }

  func presentKeyboardSettingsViewController() {
    presentViewController(keyboardSettingsViewController)
  }

  func presentKeyboardLayoutViewController() {
    presentViewController(keyboardLayoutViewController)
  }

  func presentKeyboardColorViewController() {
    presentViewController(keyboardColorViewController)
  }

  func presentKeyboardFeedbackViewController() {
    presentViewController(keyboardFeedbackViewController)
  }

  func presentRimeViewController() {
    presentViewController(rimeViewController)
  }

  func presentBackupViewController() {
    presentViewController(backupViewController)
  }

  func presentAppleCloudViewController() {
    presentViewController(iCloudViewController)
  }

  func presentAboutViewController() {
    presentViewController(aboutViewController)
  }

  func presentFullAccessGuideViewController() {
    presentViewController(fullAccessGuideViewController)
  }

  private func presentViewController(_ vc: UIViewController) {
    primaryNavigationViewController.popToRootViewController(animated: false)
    if isCollapsed {
      primaryNavigationViewController.pushViewController(vc, animated: true)
      return
    }
    secondaryNavigationViewController.viewControllers = [vc]
  }
}

// MARK: - Tab Bar Root

open class MainTabBarController: UITabBarController {
  private let mainViewModel: MainViewModel
  private let subViewControllerFactory: SubViewControllerFactory
  private var pendingVoiceRequestId: String?

  private lazy var settingsController = MainViewController(
    mainViewModel: mainViewModel,
    subViewControllerFactory: subViewControllerFactory
  )

  private lazy var homeController = VoiceHomeViewController()
  private lazy var historyController = VoiceHistoryViewController()
  private lazy var dictionaryController = VoiceDictionaryViewController()
  private lazy var accountController = VoiceAccountViewController()

  init(mainViewModel: MainViewModel, subViewControllerFactory: SubViewControllerFactory) {
    self.mainViewModel = mainViewModel
    self.subViewControllerFactory = subViewControllerFactory
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override open func viewDidLoad() {
    super.viewDidLoad()
    setupTabs()
    deliverPendingVoiceRequestIfNeeded()
  }

  private func setupTabs() {
    tabBar.backgroundColor = .systemBackground
    tabBar.tintColor = .label
    tabBar.unselectedItemTintColor = .secondaryLabel

    // 以设置为最左侧入口，其余四栏用于语音相关功能占位
    settingsController.tabBarItem = UITabBarItem(
      title: "设置",
      image: UIImage(systemName: "gearshape"),
      selectedImage: UIImage(systemName: "gearshape.fill")
    )

    let homeNavigationController = UINavigationController(rootViewController: homeController)
    homeNavigationController.navigationBar.isHidden = true
    homeNavigationController.tabBarItem = UITabBarItem(
      title: "首页",
      image: UIImage(systemName: "house"),
      selectedImage: UIImage(systemName: "house.fill")
    )

    let historyNavigationController = UINavigationController(rootViewController: historyController)
    historyNavigationController.navigationBar.prefersLargeTitles = true
    historyNavigationController.tabBarItem = UITabBarItem(
      title: "历史记录",
      image: UIImage(systemName: "clock"),
      selectedImage: UIImage(systemName: "clock.fill")
    )

    let dictionaryNavigationController = UINavigationController(rootViewController: dictionaryController)
    dictionaryNavigationController.navigationBar.prefersLargeTitles = true
    dictionaryNavigationController.tabBarItem = UITabBarItem(
      title: "词典",
      image: UIImage(systemName: "book"),
      selectedImage: UIImage(systemName: "book.fill")
    )

    let accountNavigationController = UINavigationController(rootViewController: accountController)
    accountNavigationController.navigationBar.prefersLargeTitles = true
    accountNavigationController.tabBarItem = UITabBarItem(
      title: "账户",
      image: UIImage(systemName: "person"),
      selectedImage: UIImage(systemName: "person.fill")
    )

    viewControllers = [
      settingsController,
      homeNavigationController,
      historyNavigationController,
      dictionaryNavigationController,
      accountNavigationController
    ]
  }

  open func activateSettingsTab() {
    selectedIndex = 0
    settingsController.presentMainViewController()
  }

  open func activateVoiceDictation(requestId: String) {
    pendingVoiceRequestId = requestId
    selectedIndex = 1
    deliverPendingVoiceRequestIfNeeded()
  }

  private func deliverPendingVoiceRequestIfNeeded() {
    guard let requestId = pendingVoiceRequestId else { return }
    guard isViewLoaded else { return }
    pendingVoiceRequestId = nil
    homeController.startDictation(requestId: requestId)
  }
}

// MARK: - Home

final class VoiceHomeViewController: NibLessViewController {
  private lazy var homeRootView = VoiceHomeRootView()
  private let voiceInputBridge: AppVoiceInputBridge = .shared

  override func loadView() {
    homeRootView.onStartDictation = { [weak self] in
      guard let self = self else { return }
      let requestId = self.voiceInputBridge.makeRequestId()
      self.startDictation(requestId: requestId)
    }
    view = homeRootView
  }

  func startDictation(requestId: String) {
    if let dictationController = presentedViewController as? VoiceDictationViewController {
      dictationController.updateRequestId(requestId)
      return
    }
    let controller = VoiceDictationViewController(requestId: requestId)
    controller.modalPresentationStyle = .fullScreen
    present(controller, animated: true)
  }
}

final class VoiceHomeRootView: NibLessView {
  var onStartDictation: (() -> Void)?
  private let statsCard = VoiceCardView(style: .standard)
  private let desktopCard = VoiceCardView(style: .standard)
  private let statusCard = VoiceCardView(style: .accent)

  private lazy var scrollView: UIScrollView = {
    let view = UIScrollView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var contentStack: UIStackView = {
    let stack = UIStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 18
    return stack
  }()

  private lazy var brandLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 26, weight: .semibold)
    label.text = "Nanomouse"
    return label
  }()

  private lazy var brandSubtitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .regular)
    label.textColor = .secondaryLabel
    label.text = "AI 语音输入"
    return label
  }()

  private lazy var brandStack: UIStackView = {
    let stack = UIStackView(arrangedSubviews: [brandLabel, brandSubtitleLabel])
    stack.axis = .vertical
    stack.spacing = 4
    return stack
  }()

  private lazy var statsGrid: UIStackView = {
    let topRow = UIStackView(arrangedSubviews: [
      makeStatItem(value: "0", unit: "min", title: "总听写时间"),
      makeStatItem(value: "25", unit: "字", title: "听写的单词")
    ])
    topRow.axis = .horizontal
    topRow.distribution = .fillEqually
    topRow.spacing = 8

    let bottomRow = UIStackView(arrangedSubviews: [
      makeStatItem(value: "0", unit: "min", title: "节省的时间"),
      makeStatItem(value: "120", unit: "每分钟字数", title: "平均听写速度")
    ])
    bottomRow.axis = .horizontal
    bottomRow.distribution = .fillEqually
    bottomRow.spacing = 8

    let stack = UIStackView(arrangedSubviews: [topRow, bottomRow])
    stack.axis = .vertical
    stack.spacing = 14
    return stack
  }()

  private lazy var desktopIconView: UIImageView = {
    let view = UIImageView(image: UIImage(systemName: "desktopcomputer"))
    view.translatesAutoresizingMaskIntoConstraints = false
    view.tintColor = .secondaryLabel
    view.contentMode = .scaleAspectFit
    return view
  }()

  private lazy var desktopTitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.text = "在桌面上使用 Nanomouse"
    return label
  }()

  private lazy var desktopButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("复制下载链接", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    button.backgroundColor = .systemBackground
    button.layer.cornerRadius = 12
    button.layer.borderWidth = 1
    button.layer.borderColor = UIColor.systemGray5.cgColor
    return button
  }()

  private lazy var statusTitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 16, weight: .semibold)
    label.text = "Nanomouse 已开启"
    return label
  }()

  private lazy var statusInfoButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "info.circle"), for: .normal)
    button.tintColor = .secondaryLabel
    return button
  }()

  private lazy var statusSwitch: UISwitch = {
    let control = UISwitch(frame: .zero)
    control.isOn = true
    control.onTintColor = .systemBlue
    control.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
    return control
  }()

  private lazy var statusFooterLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    label.text = "在不活动时关闭：12 小时"
    return label
  }()

  private lazy var statusFooterChevron: UIImageView = {
    let view = UIImageView(image: UIImage(systemName: "chevron.down"))
    view.translatesAutoresizingMaskIntoConstraints = false
    view.tintColor = .secondaryLabel
    return view
  }()

  private lazy var startDictationButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("开始口述", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
    button.setTitleColor(.white, for: .normal)
    button.backgroundColor = .label
    button.layer.cornerRadius = 16
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    button.addTarget(self, action: #selector(handleStartDictationTap), for: .touchUpInside)
    return button
  }()

  private lazy var statusSubtitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    label.text = "轻触开关可暂停语音输入"
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  private func setupView() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(scrollView)
    scrollView.addSubview(contentStack)
    contentStack.addArrangedSubview(brandStack)
    contentStack.addArrangedSubview(statsCard)
    contentStack.addArrangedSubview(desktopCard)
    contentStack.addArrangedSubview(statusCard)

    statsCard.addContentView(statsGrid)

    let desktopTextStack = UIStackView(arrangedSubviews: [desktopTitleLabel, desktopButton])
    desktopTextStack.axis = .vertical
    desktopTextStack.spacing = 10

    let desktopStack = UIStackView(arrangedSubviews: [desktopIconView, desktopTextStack])
    desktopStack.axis = .horizontal
    desktopStack.spacing = 14
    desktopStack.alignment = .top
    desktopStack.distribution = .fill
    desktopCard.addContentView(desktopStack)

    let statusTitleStack = UIStackView(arrangedSubviews: [statusTitleLabel, statusInfoButton])
    statusTitleStack.axis = .horizontal
    statusTitleStack.spacing = 6
    statusTitleStack.alignment = .center

    let statusHeader = UIStackView(arrangedSubviews: [statusTitleStack, statusSwitch])
    statusHeader.axis = .horizontal
    statusHeader.alignment = .center
    statusHeader.distribution = .equalSpacing

    let statusFooter = UIStackView(arrangedSubviews: [statusFooterLabel, statusFooterChevron])
    statusFooter.axis = .horizontal
    statusFooter.spacing = 6
    statusFooter.alignment = .center

    let statusStack = UIStackView(arrangedSubviews: [statusHeader, statusSubtitleLabel, statusFooter, startDictationButton])
    statusStack.axis = .vertical
    statusStack.spacing = 10
    statusCard.addContentView(statusStack)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
      contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
      contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
      contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
    ])

    desktopButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
    desktopButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
    desktopIconView.widthAnchor.constraint(equalToConstant: 28).isActive = true
    desktopIconView.heightAnchor.constraint(equalTo: desktopIconView.widthAnchor).isActive = true
  }

  override func setupAppearance() {
    backgroundColor = .systemBackground
  }

  @objc private func handleStartDictationTap() {
    onStartDictation?()
  }

  private func makeStatItem(value: String, unit: String, title: String) -> UIStackView {
    let valueLabel = UILabel()
    valueLabel.font = .systemFont(ofSize: 22, weight: .bold)
    valueLabel.text = value

    let unitLabel = UILabel()
    unitLabel.font = .systemFont(ofSize: 13, weight: .regular)
    unitLabel.textColor = .secondaryLabel
    unitLabel.text = unit

    let topRow = UIStackView(arrangedSubviews: [valueLabel, unitLabel])
    topRow.axis = .horizontal
    topRow.spacing = 4
    topRow.alignment = .firstBaseline

    let titleLabel = UILabel()
    titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
    titleLabel.textColor = .secondaryLabel
    titleLabel.text = title

    let stack = UIStackView(arrangedSubviews: [topRow, titleLabel])
    stack.axis = .vertical
    stack.spacing = 6
    return stack
  }
}

final class VoiceCardView: UIView {
  enum Style {
    case standard
    case accent
  }

  private let style: Style
  private let contentContainer = UIView()

  init(style: Style = .standard) {
    self.style = style
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    layer.cornerRadius = 18
    contentContainer.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentContainer)
    applyStyle()
    NSLayoutConstraint.activate([
      contentContainer.topAnchor.constraint(equalTo: topAnchor, constant: 16),
      contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func addContentView(_ view: UIView) {
    view.translatesAutoresizingMaskIntoConstraints = false
    contentContainer.addSubview(view)
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
      view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
      view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
    ])
  }

  private func applyStyle() {
    switch style {
    case .standard:
      backgroundColor = .secondarySystemBackground
      layer.shadowColor = UIColor.black.cgColor
      layer.shadowOpacity = 0.06
      layer.shadowRadius = 12
      layer.shadowOffset = CGSize(width: 0, height: 6)
    case .accent:
      backgroundColor = UIColor(red: 0.88, green: 0.93, blue: 1.0, alpha: 1.0)
      layer.shadowOpacity = 0
    }
  }
}

// MARK: - History

final class VoiceHistoryViewController: NibLessViewController {
  private let historyView = VoiceHistoryRootView()

  private struct HistoryItem {
    let time: String
    let text: String
    let isError: Bool
    let canRetry: Bool
  }

  private let items: [HistoryItem] = [
    .init(time: "03:49 PM", text: "Audio is silent.", isError: false, canRetry: true),
    .init(time: "03:49 PM", text: "4. Eggs", isError: false, canRetry: false),
    .init(time: "03:48 PM", text: "Add eggs.", isError: false, canRetry: false),
    .init(time: "03:48 PM", text: "Your transcription was interrupted.", isError: true, canRetry: true)
  ]

  override func loadView() {
    title = "历史记录"
    view = historyView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    historyView.tableView.dataSource = self
    historyView.tableView.delegate = self
    historyView.tableView.tableHeaderView = historyView.makeHeaderView()
    historyView.tableView.register(VoiceHistoryCell.self, forCellReuseIdentifier: VoiceHistoryCell.identifier)
  }
}

extension VoiceHistoryViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    items.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: VoiceHistoryCell.identifier, for: indexPath)
    let item = items[indexPath.row]
    if let historyCell = cell as? VoiceHistoryCell {
      historyCell.configure(time: item.time, text: item.text, isError: item.isError, canRetry: item.canRetry)
    }
    return cell
  }

  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    UITableView.automaticDimension
  }
}

final class VoiceHistoryRootView: NibLessView {
  let tableView: UITableView = {
    let view = UITableView(frame: .zero, style: .insetGrouped)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.separatorStyle = .singleLine
    return view
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  private func setupView() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(tableView)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }

  override func setupAppearance() {
    backgroundColor = .systemBackground
    tableView.backgroundColor = .systemBackground
  }

  func makeHeaderView() -> UIView {
    let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 124))
    let card = UIView()
    card.translatesAutoresizingMaskIntoConstraints = false
    card.backgroundColor = .secondarySystemBackground
    card.layer.cornerRadius = 16

    let titleLabel = UILabel()
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    titleLabel.text = "保留历史"

    let trailingLabel = UILabel()
    trailingLabel.translatesAutoresizingMaskIntoConstraints = false
    trailingLabel.font = .systemFont(ofSize: 13, weight: .regular)
    trailingLabel.textColor = .secondaryLabel
    trailingLabel.text = "永久"

    let trailingChevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    trailingChevron.translatesAutoresizingMaskIntoConstraints = false
    trailingChevron.tintColor = .secondaryLabel

    let subtitleLabel = UILabel()
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.numberOfLines = 0
    subtitleLabel.text = "您的数据保持私密，听写记录仅存储在设备上。"

    let headerRow = UIStackView(arrangedSubviews: [titleLabel, UIView(), trailingLabel, trailingChevron])
    headerRow.translatesAutoresizingMaskIntoConstraints = false
    headerRow.axis = .horizontal
    headerRow.alignment = .center
    headerRow.spacing = 6

    container.addSubview(card)
    card.addSubview(headerRow)
    card.addSubview(subtitleLabel)

    NSLayoutConstraint.activate([
      card.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
      card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
      card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
      card.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),

      headerRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
      headerRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
      headerRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

      subtitleLabel.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 8),
      subtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
      subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
      subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
    ])

    return container
  }
}

final class VoiceHistoryCell: UITableViewCell {
  static let identifier = "VoiceHistoryCell"

  private lazy var retryWidthConstraint = retryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 52)
  private lazy var retryHiddenConstraint = retryButton.widthAnchor.constraint(equalToConstant: 0)

  private lazy var timeLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .regular)
    label.textColor = .secondaryLabel
    return label
  }()

  private lazy var messageLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 15, weight: .regular)
    label.textColor = .label
    label.numberOfLines = 0
    return label
  }()

  private lazy var retryButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("重试", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    button.setTitleColor(.systemBlue, for: .normal)
    button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
    button.layer.cornerRadius = 10
    button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
    return button
  }()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    contentView.addSubview(timeLabel)
    contentView.addSubview(messageLabel)
    contentView.addSubview(retryButton)

    NSLayoutConstraint.activate([
      timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
      timeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      timeLabel.trailingAnchor.constraint(lessThanOrEqualTo: retryButton.leadingAnchor, constant: -8),

      messageLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 6),
      messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: retryButton.leadingAnchor, constant: -12),
      messageLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

      retryButton.centerYAnchor.constraint(equalTo: messageLabel.centerYAnchor),
      retryButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
    ])

    retryWidthConstraint.isActive = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(time: String, text: String, isError: Bool, canRetry: Bool) {
    timeLabel.text = time
    messageLabel.text = text
    messageLabel.textColor = isError ? .systemRed : .label
    if canRetry {
      retryHiddenConstraint.isActive = false
      retryWidthConstraint.isActive = true
      retryButton.isHidden = false
    } else {
      retryWidthConstraint.isActive = false
      retryHiddenConstraint.isActive = true
      retryButton.isHidden = true
    }
  }
}

// MARK: - Dictionary

final class VoiceDictionaryViewController: NibLessViewController {
  override func loadView() {
    title = "词典"
    view = VoiceDictionaryRootView()
  }
}

final class VoiceDictionaryRootView: NibLessView {
  private lazy var segmentedControl: UISegmentedControl = {
    let control = UISegmentedControl(items: ["所有", "自动添加", "手动添加"])
    control.translatesAutoresizingMaskIntoConstraints = false
    control.selectedSegmentIndex = 0
    control.selectedSegmentTintColor = .label
    control.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    control.setTitleTextAttributes([.foregroundColor: UIColor.label], for: .normal)
    return control
  }()

  private lazy var emptyTitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 16, weight: .semibold)
    label.text = "尚无单词"
    return label
  }()

  private lazy var emptySubtitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.textAlignment = .center
    label.text = "Nanomouse 会记住您独特的名称与单词，您也可以手动添加。"
    return label
  }()

  private lazy var addButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "plus"), for: .normal)
    button.tintColor = .white
    button.backgroundColor = .label
    button.layer.cornerRadius = 24
    button.layer.shadowColor = UIColor.black.cgColor
    button.layer.shadowOpacity = 0.18
    button.layer.shadowRadius = 8
    button.layer.shadowOffset = CGSize(width: 0, height: 4)
    return button
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  private func setupView() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(segmentedControl)
    addSubview(emptyTitleLabel)
    addSubview(emptySubtitleLabel)
    addSubview(addButton)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      segmentedControl.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      segmentedControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      segmentedControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

      emptyTitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      emptyTitleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -16),

      emptySubtitleLabel.topAnchor.constraint(equalTo: emptyTitleLabel.bottomAnchor, constant: 12),
      emptySubtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
      emptySubtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),

      addButton.widthAnchor.constraint(equalToConstant: 48),
      addButton.heightAnchor.constraint(equalTo: addButton.widthAnchor),
      addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
      addButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),
    ])
  }

  override func setupAppearance() {
    backgroundColor = .systemBackground
  }
}

// MARK: - Voice Model Management

final class VoiceModelManagementViewController: NibLessViewController {
  private let modelView = VoiceModelManagementRootView()
  private let modelStore: VoiceWhisperModelStore = .shared
  private var models: [VoiceWhisperModelStatus] = []
  private var downloadingModelID: String?

  override func loadView() {
    title = "语音模型"
    view = modelView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    modelView.tableView.dataSource = self
    modelView.tableView.delegate = self
    modelView.tableView.register(VoiceModelCell.self, forCellReuseIdentifier: VoiceModelCell.identifier)
    refreshModels()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    refreshModels()
  }

  private func refreshModels() {
    models = modelStore.availableModelStatuses()
    let isAppleOnly = !models.contains(where: { $0.isDownloaded })
    modelView.updateSummary(isAppleOnly: isAppleOnly)
    modelView.tableView.reloadData()
  }

  private func handleAction(at indexPath: IndexPath) {
    let model = models[indexPath.row]
    if model.isDownloaded {
      modelStore.setSelectedModel(model.option.id)
      refreshModels()
      return
    }

    downloadingModelID = model.option.id
    modelView.tableView.reloadRows(at: [indexPath], with: .none)
    Task { [weak self] in
      guard let self else { return }
      do {
        _ = try await self.modelStore.downloadModel(model.option.id)
        await MainActor.run {
          self.downloadingModelID = nil
          self.refreshModels()
        }
      } catch {
        await MainActor.run {
          self.downloadingModelID = nil
          self.refreshModels()
          self.presentErrorAlert(message: error.localizedDescription)
        }
      }
    }
  }

  private func deleteModel(at indexPath: IndexPath, completion: @escaping (Bool) -> Void) {
    let model = models[indexPath.row]
    do {
      try modelStore.deleteModel(model.option.id)
      refreshModels()
      completion(true)
    } catch {
      presentErrorAlert(message: error.localizedDescription)
      completion(false)
    }
  }

  private func presentErrorAlert(message: String) {
    let controller = UIAlertController(title: "操作失败", message: message, preferredStyle: .alert)
    controller.addAction(UIAlertAction(title: "知道了", style: .default))
    present(controller, animated: true)
  }
}

extension VoiceModelManagementViewController: UITableViewDataSource, UITableViewDelegate {
  func numberOfSections(in tableView: UITableView) -> Int {
    1
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    models.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: VoiceModelCell.identifier, for: indexPath)
    guard let modelCell = cell as? VoiceModelCell else { return cell }
    let status = models[indexPath.row]
    let isDownloading = downloadingModelID == status.option.id
    modelCell.configure(status: status, isDownloading: isDownloading)
    modelCell.onActionTap = { [weak self] in
      self?.handleAction(at: indexPath)
    }
    return modelCell
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    "Whisper 离线模型"
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    "点击“下载”后才会拉取模型。左滑可删除模型；当模型全部删除后，系统将仅使用 Apple Speech。"
  }

  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    let status = models[indexPath.row]
    guard status.isDownloaded else { return nil }
    let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
      self?.deleteModel(at: indexPath, completion: completion)
    }
    return UISwipeActionsConfiguration(actions: [deleteAction])
  }
}

final class VoiceModelCell: UITableViewCell {
  static let identifier = "VoiceModelCell"

  var onActionTap: (() -> Void)?

  private lazy var titleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 16, weight: .semibold)
    return label
  }()

  private lazy var subtitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    return label
  }()

  private lazy var stateLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .medium)
    label.textColor = .secondaryLabel
    return label
  }()

  private lazy var actionButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    button.layer.cornerRadius = 10
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
    button.addTarget(self, action: #selector(handleActionTap), for: .touchUpInside)
    return button
  }()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    let infoStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, stateLabel])
    infoStack.translatesAutoresizingMaskIntoConstraints = false
    infoStack.axis = .vertical
    infoStack.spacing = 6
    contentView.addSubview(infoStack)
    contentView.addSubview(actionButton)

    NSLayoutConstraint.activate([
      infoStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
      infoStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      infoStack.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -12),
      infoStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

      actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88)
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(status: VoiceWhisperModelStatus, isDownloading: Bool) {
    titleLabel.text = status.option.displayName
    subtitleLabel.text = "\(status.option.sizeText) · \(status.option.summary)"
    if isDownloading {
      stateLabel.text = "状态：下载中..."
      actionButton.setTitle("下载中", for: .normal)
      actionButton.isEnabled = false
      actionButton.backgroundColor = .systemGray5
      actionButton.setTitleColor(.secondaryLabel, for: .normal)
      return
    }

    if status.isDownloaded {
      if status.isSelected {
        stateLabel.text = "状态：已下载 · 当前使用"
        actionButton.setTitle("使用中", for: .normal)
        actionButton.isEnabled = false
        actionButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
        actionButton.setTitleColor(.systemBlue, for: .normal)
      } else {
        stateLabel.text = "状态：已下载"
        actionButton.setTitle("设为默认", for: .normal)
        actionButton.isEnabled = true
        actionButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.12)
        actionButton.setTitleColor(.systemGreen, for: .normal)
      }
    } else {
      stateLabel.text = "状态：未下载"
      actionButton.setTitle("下载", for: .normal)
      actionButton.isEnabled = true
      actionButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
      actionButton.setTitleColor(.systemBlue, for: .normal)
    }
  }

  @objc private func handleActionTap() {
    onActionTap?()
  }
}

final class VoiceModelManagementRootView: NibLessView {
  let tableView: UITableView = {
    let view = UITableView(frame: .zero, style: .insetGrouped)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
    return view
  }()

  private lazy var summaryLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.textAlignment = .left
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  private func setupView() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(summaryLabel)
    addSubview(tableView)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      summaryLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
      summaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      summaryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

      tableView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 8),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }

  override func setupAppearance() {
    backgroundColor = .systemBackground
    tableView.backgroundColor = .systemBackground
  }

  func updateSummary(isAppleOnly: Bool) {
    if isAppleOnly {
      summaryLabel.text = "当前已无本地 Whisper 模型，系统将只使用 Apple Speech。"
    } else {
      summaryLabel.text = "你可以下载多个 Whisper 模型，并手动切换默认模型。"
    }
  }
}

// MARK: - Account

final class VoiceAccountViewController: NibLessViewController {
  private let accountView = VoiceAccountRootView()
  private lazy var modelManagementController = VoiceModelManagementViewController()

  override func loadView() {
    title = "账户"
    view = accountView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    accountView.tableView.dataSource = self
    accountView.tableView.delegate = self
    accountView.tableView.register(AccountNotificationCell.self, forCellReuseIdentifier: AccountNotificationCell.identifier)
    accountView.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AccountCell")
  }
}

extension VoiceAccountViewController: UITableViewDataSource, UITableViewDelegate {
  func numberOfSections(in tableView: UITableView) -> Int {
    4
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch section {
    case 0: return 1
    case 1: return 1
    case 2: return 3
    default: return 2
    }
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    if indexPath.section == 0 {
      let cell = tableView.dequeueReusableCell(withIdentifier: AccountNotificationCell.identifier, for: indexPath)
      return cell
    }

    let cell = tableView.dequeueReusableCell(withIdentifier: "AccountCell", for: indexPath)
    cell.selectionStyle = .default
    cell.accessoryType = .disclosureIndicator
    cell.textLabel?.font = .systemFont(ofSize: 15, weight: .regular)

    switch (indexPath.section, indexPath.row) {
    case (1, 0):
      cell.textLabel?.text = "choushoukei@gmail.com"
      cell.imageView?.image = UIImage(systemName: "person.crop.circle")
    case (2, 0):
      cell.textLabel?.text = "语音模型"
      cell.imageView?.image = UIImage(systemName: "waveform.badge.mic")
    case (2, 1):
      cell.textLabel?.text = "设置"
      cell.imageView?.image = UIImage(systemName: "gearshape")
    case (2, 2):
      cell.textLabel?.text = "关于"
      cell.imageView?.image = UIImage(systemName: "info.circle")
    case (3, 0):
      cell.textLabel?.text = "帮助中心"
      cell.imageView?.image = UIImage(systemName: "questionmark.circle")
    case (3, 1):
      cell.textLabel?.text = "版本说明"
      cell.imageView?.image = UIImage(systemName: "book")
    default:
      cell.textLabel?.text = nil
    }
    return cell
  }

  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    UITableView.automaticDimension
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    if indexPath.section == 2, indexPath.row == 0 {
      navigationController?.pushViewController(modelManagementController, animated: true)
    }
  }
}

final class VoiceAccountRootView: NibLessView {
  let tableView: UITableView = {
    let view = UITableView(frame: .zero, style: .insetGrouped)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
    return view
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  private func setupView() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(tableView)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }

  override func setupAppearance() {
    backgroundColor = .systemBackground
    tableView.backgroundColor = .systemBackground
  }
}

final class AccountNotificationCell: UITableViewCell {
  static let identifier = "AccountNotificationCell"

  private lazy var cardView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .secondarySystemBackground
    view.layer.cornerRadius = 16
    return view
  }()

  private lazy var dotView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .systemRed
    view.layer.cornerRadius = 4
    return view
  }()

  private lazy var titleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.text = "通知：关闭"
    label.textColor = .systemRed
    return label
  }()

  private lazy var subtitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.text = "开启通知以获取有用提示，并第一时间了解新功能。"
    return label
  }()

  private lazy var actionButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("开启通知", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
    button.backgroundColor = .secondarySystemBackground
    button.layer.cornerRadius = 10
    return button
  }()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    contentView.addSubview(cardView)
    cardView.addSubview(dotView)
    cardView.addSubview(titleLabel)
    cardView.addSubview(subtitleLabel)
    cardView.addSubview(actionButton)

    NSLayoutConstraint.activate([
      cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
      cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

      dotView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
      dotView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
      dotView.widthAnchor.constraint(equalToConstant: 8),
      dotView.heightAnchor.constraint(equalToConstant: 8),

      titleLabel.centerYAnchor.constraint(equalTo: dotView.centerYAnchor),
      titleLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 8),
      titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),

      subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
      subtitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
      subtitleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),

      actionButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
      actionButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
      actionButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
      actionButton.heightAnchor.constraint(equalToConstant: 36)
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
