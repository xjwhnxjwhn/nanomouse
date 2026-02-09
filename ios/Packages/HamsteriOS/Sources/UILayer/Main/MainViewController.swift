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
  private let historyStore: VoiceDictationHistoryStore = .shared
  private let homeSettingsStore: VoiceHomeSettingsStore = .shared
  private let gitHubStarsService: VoiceGitHubStarsService = .shared
  private let statsNumberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    return formatter
  }()

  private struct HomeMetrics {
    let totalDictationMinutes: Double
    let totalCharacters: Int
    let estimatedSavedMinutes: Double
    let averageCharsPerMinute: Int
  }

  override func loadView() {
    homeRootView.onStartDictation = { [weak self] in
      self?.handleStartDictationTap()
    }
    homeRootView.onToggleVoiceEnabled = { [weak self] enabled in
      self?.handleVoiceEnabledChanged(enabled)
    }
    homeRootView.onTapStatusInfo = { [weak self] in
      self?.presentStatusInfoAlert()
    }
    homeRootView.onTapAutoClose = { [weak self] in
      self?.presentAutoCloseOptions()
    }
    homeRootView.onTapDesktopLink = { [weak self] in
      self?.copyDesktopDownloadLink()
    }
    view = homeRootView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    refreshHomeDashboard()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    refreshHomeDashboard()
  }

  func startDictation(requestId: String) {
    guard homeSettingsStore.isVoiceEnabled() else {
      presentSimpleAlert(
        title: "语音输入已暂停",
        message: "你当前关闭了语音输入，请先在首页开启后再继续听写。"
      )
      return
    }
    if let dictationController = presentedViewController as? VoiceDictationViewController {
      dictationController.updateRequestId(requestId)
      return
    }
    let controller = VoiceDictationViewController(requestId: requestId)
    controller.modalPresentationStyle = .fullScreen
    present(controller, animated: true)
  }

  private func handleStartDictationTap() {
    let requestId = voiceInputBridge.makeRequestId()
    startDictation(requestId: requestId)
  }

  private func handleVoiceEnabledChanged(_ enabled: Bool) {
    homeSettingsStore.setVoiceEnabled(enabled)
    refreshHomeDashboard()
  }

  private func presentStatusInfoAlert() {
    presentSimpleAlert(
      title: "语音输入状态",
      message: "你关闭开关后，首页与键盘跳转入口都会阻止新的听写会话。"
    )
  }

  private func presentAutoCloseOptions() {
    let current = homeSettingsStore.inactiveAutoCloseMinutes()
    let alert = UIAlertController(title: "不活动自动关闭", message: "选择超过多久未使用后自动关闭语音输入。", preferredStyle: .actionSheet)
    for option in VoiceHomeSettingsStore.inactiveMinuteOptions {
      let optionText = VoiceHomeSettingsStore.displayText(forInactiveMinutes: option)
      let title = option == current ? "\(optionText)（当前）" : optionText
      alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
        guard let self else { return }
        self.homeSettingsStore.setInactiveAutoCloseMinutes(option)
        self.refreshHomeDashboard()
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = view
      popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 40, width: 1, height: 1)
      popover.permittedArrowDirections = []
    }
    present(alert, animated: true)
  }

  private func copyDesktopDownloadLink() {
    guard let repositoryURL = gitHubStarsService.repositoryWebURL() else {
      presentSimpleAlert(title: "复制失败", message: "桌面版链接暂不可用，请稍后重试。")
      return
    }
    let desktopURL = repositoryURL.appendingPathComponent("releases").absoluteString
    UIPasteboard.general.string = desktopURL
    presentSimpleAlert(title: "已复制", message: "桌面版下载链接已复制到剪贴板。")
  }

  private func refreshHomeDashboard() {
    let entries = historyStore.entries(limit: 300)
    applyAutoPauseIfNeeded(entries: entries)

    let isEnabled = homeSettingsStore.isVoiceEnabled()
    let inactiveMinutes = homeSettingsStore.inactiveAutoCloseMinutes()
    let metrics = computeMetrics(from: entries)

    homeRootView.updateVoiceStatus(isEnabled: isEnabled, inactiveMinutes: inactiveMinutes)
    homeRootView.updateStats(
      totalMinutes: formatMinutes(metrics.totalDictationMinutes),
      totalCharacters: formatCount(metrics.totalCharacters),
      savedMinutes: formatMinutes(metrics.estimatedSavedMinutes),
      averageCharsPerMinute: formatCount(metrics.averageCharsPerMinute)
    )
  }

  private func applyAutoPauseIfNeeded(entries: [VoiceDictationHistoryEntry]) {
    guard homeSettingsStore.isVoiceEnabled() else { return }
    guard let latestActivity = entries.first?.createdAt else { return }
    let threshold = TimeInterval(homeSettingsStore.inactiveAutoCloseMinutes() * 60)
    guard threshold > 0 else { return }
    if Date().timeIntervalSince1970 - latestActivity >= threshold {
      homeSettingsStore.setVoiceEnabled(false)
    }
  }

  private func computeMetrics(from entries: [VoiceDictationHistoryEntry]) -> HomeMetrics {
    let successful = entries.filter { $0.status == .success }
    var totalCharacters = 0
    var totalDictationSeconds: Double = 0

    for entry in successful {
      let text = (entry.outputText ?? entry.rawText).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      let characters = countContentCharacters(in: text)
      guard characters > 0 else { continue }
      totalCharacters += characters

      if let duration = entry.durationSeconds, duration > 0 {
        totalDictationSeconds += duration
      } else {
        // 兼容旧历史记录：旧记录没有时长时，用保守语速估算，避免首页统计长期显示 0。
        totalDictationSeconds += Double(characters) / 110.0 * 60.0
      }
    }

    let totalDictationMinutes = totalDictationSeconds / 60.0
    let averageCharsPerMinute: Int
    if totalDictationSeconds > 0 {
      averageCharsPerMinute = Int((Double(totalCharacters) / totalDictationSeconds * 60.0).rounded())
    } else {
      averageCharsPerMinute = 0
    }

    // 以 60 字/分钟作为手动输入基线，用于估算节省时间。
    let estimatedTypingMinutes = Double(totalCharacters) / 60.0
    let estimatedSavedMinutes = max(0, estimatedTypingMinutes - totalDictationMinutes)
    return HomeMetrics(
      totalDictationMinutes: totalDictationMinutes,
      totalCharacters: totalCharacters,
      estimatedSavedMinutes: estimatedSavedMinutes,
      averageCharsPerMinute: max(0, averageCharsPerMinute)
    )
  }

  private func countContentCharacters(in text: String) -> Int {
    text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
  }

  private func formatCount(_ value: Int) -> String {
    let number = NSNumber(value: max(0, value))
    return statsNumberFormatter.string(from: number) ?? "\(max(0, value))"
  }

  private func formatMinutes(_ value: Double) -> String {
    let safe = max(0, value)
    if safe < 10 {
      return String(format: "%.1f", safe)
    }
    return "\(Int(safe.rounded()))"
  }

  private func presentSimpleAlert(title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .default))
    present(alert, animated: true)
  }
}

final class VoiceHomeRootView: NibLessView {
  var onStartDictation: (() -> Void)?
  var onToggleVoiceEnabled: ((Bool) -> Void)?
  var onTapStatusInfo: (() -> Void)?
  var onTapAutoClose: (() -> Void)?
  var onTapDesktopLink: (() -> Void)?
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

  private lazy var totalTimeValueLabel = makeStatValueLabel(text: "0.0")
  private lazy var totalTimeUnitLabel = makeStatUnitLabel(text: "min")
  private lazy var totalTimeTitleLabel = makeStatTitleLabel(text: "总听写时间")

  private lazy var totalCharactersValueLabel = makeStatValueLabel(text: "0")
  private lazy var totalCharactersUnitLabel = makeStatUnitLabel(text: "字")
  private lazy var totalCharactersTitleLabel = makeStatTitleLabel(text: "听写字数")

  private lazy var savedTimeValueLabel = makeStatValueLabel(text: "0.0")
  private lazy var savedTimeUnitLabel = makeStatUnitLabel(text: "min")
  private lazy var savedTimeTitleLabel = makeStatTitleLabel(text: "节省的时间")

  private lazy var speedValueLabel = makeStatValueLabel(text: "0")
  private lazy var speedUnitLabel = makeStatUnitLabel(text: "每分钟字数")
  private lazy var speedTitleLabel = makeStatTitleLabel(text: "平均听写速度")

  private lazy var statsGrid: UIStackView = {
    let topRow = UIStackView(arrangedSubviews: [
      makeStatItem(
        valueLabel: totalTimeValueLabel,
        unitLabel: totalTimeUnitLabel,
        titleLabel: totalTimeTitleLabel
      ),
      makeStatItem(
        valueLabel: totalCharactersValueLabel,
        unitLabel: totalCharactersUnitLabel,
        titleLabel: totalCharactersTitleLabel
      ),
    ])
    topRow.axis = .horizontal
    topRow.distribution = .fillEqually
    topRow.spacing = 8

    let bottomRow = UIStackView(arrangedSubviews: [
      makeStatItem(
        valueLabel: savedTimeValueLabel,
        unitLabel: savedTimeUnitLabel,
        titleLabel: savedTimeTitleLabel
      ),
      makeStatItem(
        valueLabel: speedValueLabel,
        unitLabel: speedUnitLabel,
        titleLabel: speedTitleLabel
      ),
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
    button.addTarget(self, action: #selector(handleDesktopTap), for: .touchUpInside)
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
    button.addTarget(self, action: #selector(handleStatusInfoTap), for: .touchUpInside)
    return button
  }()

  private lazy var statusSwitch: UISwitch = {
    let control = UISwitch(frame: .zero)
    control.isOn = true
    control.onTintColor = .systemBlue
    control.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
    control.addTarget(self, action: #selector(handleStatusSwitchChanged(_:)), for: .valueChanged)
    return control
  }()

  private lazy var statusFooterButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.contentHorizontalAlignment = .left
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .regular)
    button.setTitleColor(.secondaryLabel, for: .normal)
    button.setTitle("在不活动时关闭：12 小时 ▾", for: .normal)
    button.addTarget(self, action: #selector(handleAutoCloseTap), for: .touchUpInside)
    return button
  }()

  private lazy var startDictationButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("开始口述", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
    button.setTitleColor(.white, for: .normal)
    button.backgroundColor = .systemBlue
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

    let statusStack = UIStackView(arrangedSubviews: [statusHeader, statusSubtitleLabel, statusFooterButton, startDictationButton])
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

  @objc private func handleDesktopTap() {
    onTapDesktopLink?()
  }

  @objc private func handleStatusSwitchChanged(_ sender: UISwitch) {
    onToggleVoiceEnabled?(sender.isOn)
  }

  @objc private func handleStatusInfoTap() {
    onTapStatusInfo?()
  }

  @objc private func handleAutoCloseTap() {
    onTapAutoClose?()
  }

  private func makeStatValueLabel(text: String) -> UILabel {
    let label = UILabel()
    label.font = .systemFont(ofSize: 22, weight: .bold)
    label.text = text
    return label
  }

  private func makeStatUnitLabel(text: String) -> UILabel {
    let label = UILabel()
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    label.text = text
    return label
  }

  private func makeStatTitleLabel(text: String) -> UILabel {
    let label = UILabel()
    label.font = .systemFont(ofSize: 12, weight: .regular)
    label.textColor = .secondaryLabel
    label.text = text
    return label
  }

  private func makeStatItem(valueLabel: UILabel, unitLabel: UILabel, titleLabel: UILabel) -> UIStackView {
    let topRow = UIStackView(arrangedSubviews: [valueLabel, unitLabel])
    topRow.axis = .horizontal
    topRow.spacing = 4
    topRow.alignment = .firstBaseline

    let stack = UIStackView(arrangedSubviews: [topRow, titleLabel])
    stack.axis = .vertical
    stack.spacing = 6
    return stack
  }

  func updateStats(totalMinutes: String, totalCharacters: String, savedMinutes: String, averageCharsPerMinute: String) {
    totalTimeValueLabel.text = totalMinutes
    totalCharactersValueLabel.text = totalCharacters
    savedTimeValueLabel.text = savedMinutes
    speedValueLabel.text = averageCharsPerMinute
  }

  func updateVoiceStatus(isEnabled: Bool, inactiveMinutes: Int) {
    statusSwitch.setOn(isEnabled, animated: false)
    statusTitleLabel.text = isEnabled ? "Nanomouse 已开启" : "Nanomouse 已暂停"
    statusSubtitleLabel.text = isEnabled ? "轻触开关可暂停语音输入" : "语音输入已暂停，请先开启后再继续听写。"
    statusFooterButton.setTitle("在不活动时关闭：\(VoiceHomeSettingsStore.displayText(forInactiveMinutes: inactiveMinutes)) ▾", for: .normal)
    startDictationButton.isEnabled = isEnabled
    startDictationButton.alpha = isEnabled ? 1 : 0.45
    startDictationButton.backgroundColor = isEnabled ? .systemBlue : .systemGray
  }
}

final class VoiceHomeSettingsStore {
  static let shared = VoiceHomeSettingsStore()
  static let inactiveMinuteOptions: [Int] = [5, 60, 180, 360, 720, 1440, 2880]

  private enum Constants {
    static let voiceEnabledKey = "voice.home.enabled.v1"
    static let inactiveAutoCloseMinutesKey = "voice.home.inactive_minutes.v2"
    static let legacyInactiveAutoCloseHoursKey = "voice.home.inactive_hours.v1"
    static let defaultInactiveMinutes = 12 * 60
  }

  private let queue = DispatchQueue(label: "nanomouse.voice.home.settings")
  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .hamster) {
    self.userDefaults = userDefaults
  }

  func isVoiceEnabled() -> Bool {
    queue.sync {
      if userDefaults.object(forKey: Constants.voiceEnabledKey) == nil {
        userDefaults.set(true, forKey: Constants.voiceEnabledKey)
        return true
      }
      return userDefaults.bool(forKey: Constants.voiceEnabledKey)
    }
  }

  func setVoiceEnabled(_ enabled: Bool) {
    queue.sync {
      userDefaults.set(enabled, forKey: Constants.voiceEnabledKey)
    }
  }

  func inactiveAutoCloseMinutes() -> Int {
    queue.sync {
      let value = resolveInactiveAutoCloseMinutes()
      let normalized = normalizeInactiveMinutes(value)
      userDefaults.set(normalized, forKey: Constants.inactiveAutoCloseMinutesKey)
      return normalized
    }
  }

  func setInactiveAutoCloseMinutes(_ minutes: Int) {
    queue.sync {
      userDefaults.set(normalizeInactiveMinutes(minutes), forKey: Constants.inactiveAutoCloseMinutesKey)
    }
  }

  static func displayText(forInactiveMinutes minutes: Int) -> String {
    if minutes < 60 {
      return "\(minutes) 分钟"
    }
    if minutes % 60 == 0 {
      return "\(minutes / 60) 小时"
    }
    return "\(minutes) 分钟"
  }
}

private extension VoiceHomeSettingsStore {
  func resolveInactiveAutoCloseMinutes() -> Int {
    if userDefaults.object(forKey: Constants.inactiveAutoCloseMinutesKey) != nil {
      return userDefaults.integer(forKey: Constants.inactiveAutoCloseMinutesKey)
    }
    // 兼容旧版本配置：首次读取 v2 时自动从 v1 小时单位迁移。
    if userDefaults.object(forKey: Constants.legacyInactiveAutoCloseHoursKey) != nil {
      let legacyHours = userDefaults.integer(forKey: Constants.legacyInactiveAutoCloseHoursKey)
      if legacyHours > 0 {
        let migrated = legacyHours * 60
        userDefaults.set(migrated, forKey: Constants.inactiveAutoCloseMinutesKey)
        return migrated
      }
    }
    return Constants.defaultInactiveMinutes
  }

  func normalizeInactiveMinutes(_ value: Int) -> Int {
    if Self.inactiveMinuteOptions.contains(value) {
      return value
    }
    if value <= 0 {
      return Constants.defaultInactiveMinutes
    }
    if let nearest = Self.inactiveMinuteOptions.min(by: { abs($0 - value) < abs($1 - value) }) {
      return nearest
    }
    return Constants.defaultInactiveMinutes
  }
}

final class VoiceCardView: UIView {
  enum Style {
    case standard
    case accent
  }

  private let style: Style
  private let contentContainer = UIView()
  private static let accentBackgroundColor = UIColor { trait in
    if trait.userInterfaceStyle == .dark {
      return UIColor(red: 0.17, green: 0.24, blue: 0.34, alpha: 1.0)
    }
    return UIColor(red: 0.88, green: 0.93, blue: 1.0, alpha: 1.0)
  }

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
      backgroundColor = Self.accentBackgroundColor
      layer.shadowOpacity = 0
    }
  }
}

// MARK: - History

final class VoiceHistoryViewController: NibLessViewController {
  private let historyView = VoiceHistoryRootView()
  private let historyStore: VoiceDictationHistoryStore = .shared
  private var items: [VoiceDictationHistoryEntry] = []
  private lazy var timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()

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
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "清空",
      style: .plain,
      target: self,
      action: #selector(handleClearTap)
    )
    refreshItems()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    refreshItems()
  }

  @objc private func handleClearTap() {
    guard !items.isEmpty else { return }
    let alert = UIAlertController(title: "清空历史记录", message: "该操作仅会删除本机记录，是否继续？", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
      guard let self else { return }
      self.historyStore.clearAll()
      self.refreshItems()
    })
    present(alert, animated: true)
  }

  private func refreshItems() {
    items = historyStore.entries(limit: 300)
    historyView.updateEmptyState(isEmpty: items.isEmpty)
    navigationItem.rightBarButtonItem?.isEnabled = !items.isEmpty
    historyView.tableView.reloadData()
  }

  private func displayText(for item: VoiceDictationHistoryEntry) -> String {
    if item.status == .failed {
      let errorMessage = (item.errorMessage ?? "识别失败").trimmingCharacters(in: .whitespacesAndNewlines)
      let partial = item.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
      if partial.isEmpty {
        return errorMessage
      }
      return "\(errorMessage)\n\(partial)"
    }

    let output = (item.outputText ?? item.rawText).trimmingCharacters(in: .whitespacesAndNewlines)
    let raw = item.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    let routeTag = routeTitle(from: item.routeRawValue)
    if !raw.isEmpty, !output.isEmpty, raw != output {
      if let routeTag {
        return "\(output)\n原文：\(raw)\n来源：\(routeTag)"
      }
      return "\(output)\n原文：\(raw)"
    }
    if let routeTag, !output.isEmpty {
      return "\(output)\n来源：\(routeTag)"
    }
    return output
  }

  private func displayTime(for item: VoiceDictationHistoryEntry) -> String {
    timeFormatter.string(from: Date(timeIntervalSince1970: item.createdAt))
  }

  private func routeTitle(from rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    switch rawValue {
    case VoiceSpeechRecognizerEngine.Route.appleOnDevice.rawValue:
      return "Apple 离线"
    case VoiceSpeechRecognizerEngine.Route.appleNetwork.rawValue:
      return "Apple 在线"
    case VoiceSpeechRecognizerEngine.Route.whisperOnDevice.rawValue:
      return "Whisper 离线"
    case VoiceSpeechRecognizerEngine.Route.cloudNetwork.rawValue:
      return "在线 ASR"
    default:
      return nil
    }
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
      historyCell.configure(
        time: displayTime(for: item),
        text: displayText(for: item),
        isError: item.status == .failed,
        canRetry: false
      )
    }
    return cell
  }

  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    UITableView.automaticDimension
  }

  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
      guard let self else {
        completion(false)
        return
      }
      self.historyStore.removeEntry(id: self.items[indexPath.row].id)
      self.refreshItems()
      completion(true)
    }
    return UISwipeActionsConfiguration(actions: [delete])
  }
}

final class VoiceHistoryRootView: NibLessView {
  let tableView: UITableView = {
    let view = UITableView(frame: .zero, style: .insetGrouped)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.separatorStyle = .singleLine
    return view
  }()

  private lazy var emptyTitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 16, weight: .semibold)
    label.textColor = .label
    label.text = "暂无历史记录"
    label.isHidden = true
    return label
  }()

  private lazy var emptySubtitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.textAlignment = .center
    label.text = "你完成一次语音输入后，历史记录会自动保存在本机。"
    label.isHidden = true
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
    addSubview(tableView)
    addSubview(emptyTitleLabel)
    addSubview(emptySubtitleLabel)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

      emptyTitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      emptyTitleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -24),

      emptySubtitleLabel.topAnchor.constraint(equalTo: emptyTitleLabel.bottomAnchor, constant: 8),
      emptySubtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
      emptySubtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
    ])
  }

  override func setupAppearance() {
    backgroundColor = .systemBackground
    tableView.backgroundColor = .systemBackground
  }

  func updateEmptyState(isEmpty: Bool) {
    emptyTitleLabel.isHidden = !isEmpty
    emptySubtitleLabel.isHidden = !isEmpty
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
  private let dictionaryView = VoiceDictionaryRootView()
  private let personalStore: VoicePersonalDictionaryStore = .shared
  private var words: [VoicePersonalWord] = []

  override func loadView() {
    title = "词典"
    view = dictionaryView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    dictionaryView.tableView.dataSource = self
    dictionaryView.tableView.delegate = self
    dictionaryView.tableView.register(VoiceDictionaryCell.self, forCellReuseIdentifier: VoiceDictionaryCell.identifier)
    dictionaryView.addButton.addTarget(self, action: #selector(handleAddWordTap), for: .touchUpInside)
    refreshWords()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    refreshWords()
  }

  @objc private func handleAddWordTap() {
    let alert = UIAlertController(title: "添加词条", message: "输入你想优先识别的词语。", preferredStyle: .alert)
    alert.addTextField { textField in
      textField.placeholder = "例如：Nanomouse、项目代号"
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
      guard let self else { return }
      let rawWord = alert.textFields?.first?.text ?? ""
      self.personalStore.addManualWord(rawWord)
      self.refreshWords()
    })
    present(alert, animated: true)
  }

  private func refreshWords() {
    words = personalStore.words(filter: .manual)
    dictionaryView.updateEmptyState(isEmpty: words.isEmpty)
    dictionaryView.tableView.reloadData()
  }

  private func deleteWord(at indexPath: IndexPath, completion: @escaping (Bool) -> Void) {
    let word = words[indexPath.row]
    personalStore.removeWord(word.word)
    refreshWords()
    completion(true)
  }
}

extension VoiceDictionaryViewController: UITableViewDataSource, UITableViewDelegate {
  func numberOfSections(in tableView: UITableView) -> Int {
    1
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    words.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: VoiceDictionaryCell.identifier, for: indexPath)
    guard let dictionaryCell = cell as? VoiceDictionaryCell else { return cell }
    dictionaryCell.configure(with: words[indexPath.row])
    return dictionaryCell
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    "词典仅包含手动词条，这些词会注入 Apple Speech、Whisper 与在线 ASR（按引擎能力）以提升专有名词识别稳定性。"
  }

  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
      self?.deleteWord(at: indexPath, completion: completion)
    }
    return UISwipeActionsConfiguration(actions: [deleteAction])
  }
}

final class VoiceDictionaryCell: UITableViewCell {
  static let identifier = "VoiceDictionaryCell"

  private lazy var wordLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 16, weight: .semibold)
    return label
  }()

  private lazy var detailLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    return label
  }()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    contentView.addSubview(wordLabel)
    contentView.addSubview(detailLabel)

    NSLayoutConstraint.activate([
      wordLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
      wordLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      wordLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

      detailLabel.topAnchor.constraint(equalTo: wordLabel.bottomAnchor, constant: 6),
      detailLabel.leadingAnchor.constraint(equalTo: wordLabel.leadingAnchor),
      detailLabel.trailingAnchor.constraint(equalTo: wordLabel.trailingAnchor),
      detailLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(with word: VoicePersonalWord) {
    wordLabel.text = word.word
    detailLabel.text = "手动 · 热度 \(word.score)"
  }
}

final class VoiceDictionaryRootView: NibLessView {
  let tableView: UITableView = {
    let view = UITableView(frame: .zero, style: .insetGrouped)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
    return view
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

  let addButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "plus"), for: .normal)
    button.tintColor = .white
    button.backgroundColor = .systemBlue
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
    addSubview(tableView)
    addSubview(emptyTitleLabel)
    addSubview(emptySubtitleLabel)
    addSubview(addButton)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

      emptyTitleLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
      emptyTitleLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor, constant: -20),

      emptySubtitleLabel.topAnchor.constraint(equalTo: emptyTitleLabel.bottomAnchor, constant: 10),
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
    tableView.backgroundColor = .systemBackground
  }

  func updateEmptyState(isEmpty: Bool) {
    emptyTitleLabel.isHidden = !isEmpty
    emptySubtitleLabel.isHidden = !isEmpty
    if isEmpty {
      emptyTitleLabel.text = "尚无手动词条"
      emptySubtitleLabel.text = "点击右下角 + 添加你想优先识别的专有名词。"
    }
  }
}

// MARK: - Voice Model Management

final class VoiceModelManagementViewController: NibLessViewController {
  private let modelView = VoiceModelManagementRootView()
  private let modelStore: VoiceWhisperModelStore = .shared
  private let asrSettingsStore: VoiceASRSettingsStore = .shared
  private lazy var whisperSettingsController = VoiceWhisperSettingsViewController()
  private lazy var cloudSettingsController = VoiceCloudASRSettingsViewController()
  private let engineOptions: [VoiceASREnginePreference] = VoiceASREnginePreference.allCases
  private var models: [VoiceWhisperModelStatus] = []

  override func loadView() {
    title = "语音模型"
    view = modelView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    modelView.tableView.dataSource = self
    modelView.tableView.delegate = self
    modelView.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "VoiceModelEntryCell")
    refreshModels()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    refreshModels()
  }

  private func refreshModels() {
    models = modelStore.availableModelStatuses()
    sanitizeSelectedEngines()
    let isAppleOnly = !models.contains(where: { $0.isDownloaded })
    modelView.updateSummary(isAppleOnly: isAppleOnly)
    modelView.tableView.reloadData()
  }

  private func sanitizeSelectedEngines() {
    let hasWhisperModel = models.contains(where: { $0.isDownloaded })
    let whisperAvailable = VoiceWhisperModelStore.isWhisperKitEnabled
    let provider = asrSettingsStore.provider()
    let hasOnlineAPIKey = !(asrSettingsStore.apiKey(for: provider) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty

    var selected = asrSettingsStore.selectedEngines()
    selected.removeAll { engine in
      (engine == .whisper && (!whisperAvailable || !hasWhisperModel)) || (engine == .cloud && !hasOnlineAPIKey)
    }
    if selected.isEmpty {
      selected = [.apple]
    }
    asrSettingsStore.setSelectedEngines(selected)
    asrSettingsStore.setMode(selected.first == .cloud ? .preferred : .disabled)
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
    engineOptions.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "VoiceModelEntryCell", for: indexPath)
    let option = engineOptions[indexPath.row]
    let selectedEngines = asrSettingsStore.selectedEngines()
    let selected = selectedEngines.contains(option)
    var config = cell.defaultContentConfiguration()
    config.text = option.displayName
    config.secondaryText = engineSummary(for: option, selected: selected)
    config.image = engineIcon(for: option)
    config.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
    config.secondaryTextProperties.color = .secondaryLabel
    cell.contentConfiguration = config
    cell.accessoryType = .none
    switch option {
    case .apple:
      cell.accessoryView = makeTrailingAccessory(showCheckmark: selected, showsChevron: false)
    case .whisper, .cloud:
      cell.accessoryView = makeTrailingAccessory(showCheckmark: selected, showsChevron: true)
    }
    cell.selectionStyle = .default
    return cell
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    "识别引擎"
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    "识别引擎是互斥单选：Apple / Whisper / 在线。若选择 Whisper，模型预热期间会临时使用 Apple，不改变你的勾选。点击 Whisper 或 在线可进入独立设置页面。"
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let tapped = engineOptions[indexPath.row]
    if tapped == .whisper {
      navigationController?.pushViewController(whisperSettingsController, animated: true)
      return
    }
    if tapped == .cloud {
      navigationController?.pushViewController(cloudSettingsController, animated: true)
      return
    }
    asrSettingsStore.setSelectedEngines([tapped])
    tableView.reloadSections(IndexSet(integer: 0), with: .none)
  }

  private func engineSummary(for option: VoiceASREnginePreference, selected: Bool) -> String {
    switch option {
    case .apple:
      return selected ? "已启用（仅 Apple）" : "点击启用 Apple 识别"
    case .whisper:
      guard VoiceWhisperModelStore.isWhisperKitEnabled else {
        return "当前构建未启用 WhisperKit"
      }
      return selected ? "已启用（预热中会临时使用 Apple）" : "需要已下载模型，点击进入设置"
    case .cloud:
      return selected ? "已启用（仅在线）" : "需要 API Key，点击进入设置"
    }
  }

  private func engineIcon(for option: VoiceASREnginePreference) -> UIImage? {
    switch option {
    case .apple:
      return UIImage(systemName: "apple.logo")
    case .whisper:
      return UIImage(systemName: "waveform")
    case .cloud:
      return UIImage(systemName: "cloud")
    }
  }

  private func makeTrailingAccessory(showCheckmark: Bool, showsChevron: Bool) -> UIView {
    let width: CGFloat
    switch (showCheckmark, showsChevron) {
    case (true, true):
      width = 42
    case (true, false):
      width = 18
    case (false, true):
      width = 18
    case (false, false):
      width = 1
    }
    let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 22))
    if showCheckmark {
      let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
      check.translatesAutoresizingMaskIntoConstraints = false
      check.tintColor = .systemGreen
      container.addSubview(check)
      NSLayoutConstraint.activate([
        check.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        check.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        check.widthAnchor.constraint(equalToConstant: 18),
        check.heightAnchor.constraint(equalToConstant: 18)
      ])
    }

    if showsChevron {
      let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
      chevron.translatesAutoresizingMaskIntoConstraints = false
      chevron.tintColor = .tertiaryLabel
      container.addSubview(chevron)
      NSLayoutConstraint.activate([
        chevron.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        chevron.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        chevron.widthAnchor.constraint(equalToConstant: 8),
        chevron.heightAnchor.constraint(equalToConstant: 14)
      ])
    }
    return container
  }
}

final class VoiceWhisperSettingsViewController: NibLessViewController {
  private let settingsView = VoiceModelManagementRootView()
  private let modelStore: VoiceWhisperModelStore = .shared
  private let asrSettingsStore: VoiceASRSettingsStore = .shared
  private var models: [VoiceWhisperModelStatus] = []
  private var remoteModelIDs: [String] = []
  private var downloadingModelID: String?
  private var isFetchingRemoteModelList = false
  private var isApplyingWhisperToggle = false
  private var runtimeBannerTimer: Timer?

  private struct RuntimeBannerContent {
    let text: String
    let tintColor: UIColor
    let backgroundColor: UIColor
  }

  private lazy var runtimeBannerView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.layer.cornerRadius = 12
    view.layer.masksToBounds = true
    view.isHidden = true
    view.alpha = 0
    view.isUserInteractionEnabled = false
    return view
  }()

  private lazy var runtimeBannerIconView: UIImageView = {
    let view = UIImageView(image: UIImage(systemName: "apple.logo"))
    view.translatesAutoresizingMaskIntoConstraints = false
    view.contentMode = .scaleAspectFit
    return view
  }()

  private lazy var runtimeBannerLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    label.numberOfLines = 2
    label.textAlignment = .left
    return label
  }()

  private lazy var whisperEnabledSwitch: UISwitch = {
    let control = UISwitch(frame: .zero)
    control.addTarget(self, action: #selector(handleWhisperSwitchChanged(_:)), for: .valueChanged)
    return control
  }()

  override func loadView() {
    title = "Whisper 设置"
    view = settingsView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    settingsView.tableView.dataSource = self
    settingsView.tableView.delegate = self
    settingsView.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "VoiceWhisperToggleCell")
    settingsView.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "VoiceWhisperActionCell")
    settingsView.tableView.register(VoiceModelCell.self, forCellReuseIdentifier: VoiceModelCell.identifier)
    setupRuntimeBannerOverlay()
    refreshModels()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    refreshModels()
    startRuntimeBannerPolling()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    stopRuntimeBannerPolling()
  }

  private func refreshModels() {
    models = modelStore.availableModelStatuses()
    remoteModelIDs = modelStore.remoteModelIDs()
    syncWhisperSelectionWithAvailability()
    let isAppleOnly = !models.contains(where: { $0.isDownloaded })
    settingsView.updateSummary(isAppleOnly: isAppleOnly)
    settingsView.tableView.reloadData()
    updateRuntimeBanner(animated: true)
  }

  private func setupRuntimeBannerOverlay() {
    view.addSubview(runtimeBannerView)
    runtimeBannerView.addSubview(runtimeBannerIconView)
    runtimeBannerView.addSubview(runtimeBannerLabel)
    NSLayoutConstraint.activate([
      runtimeBannerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      runtimeBannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      runtimeBannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

      runtimeBannerIconView.leadingAnchor.constraint(equalTo: runtimeBannerView.leadingAnchor, constant: 10),
      runtimeBannerIconView.centerYAnchor.constraint(equalTo: runtimeBannerView.centerYAnchor),
      runtimeBannerIconView.widthAnchor.constraint(equalToConstant: 16),
      runtimeBannerIconView.heightAnchor.constraint(equalToConstant: 16),

      runtimeBannerLabel.topAnchor.constraint(equalTo: runtimeBannerView.topAnchor, constant: 10),
      runtimeBannerLabel.leadingAnchor.constraint(equalTo: runtimeBannerIconView.trailingAnchor, constant: 8),
      runtimeBannerLabel.trailingAnchor.constraint(equalTo: runtimeBannerView.trailingAnchor, constant: -10),
      runtimeBannerLabel.bottomAnchor.constraint(equalTo: runtimeBannerView.bottomAnchor, constant: -10),
      runtimeBannerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
    ])
  }

  private func startRuntimeBannerPolling() {
    stopRuntimeBannerPolling()
    runtimeBannerTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
      self?.updateRuntimeBanner(animated: false)
    }
    updateRuntimeBanner(animated: false)
  }

  private func stopRuntimeBannerPolling() {
    runtimeBannerTimer?.invalidate()
    runtimeBannerTimer = nil
  }

  private func updateRuntimeBanner(animated: Bool) {
    guard let content = runtimeBannerContent() else {
      guard !runtimeBannerView.isHidden else { return }
      let hideBlock = {
        self.runtimeBannerView.alpha = 0
      }
      let completion: (Bool) -> Void = { _ in
        self.runtimeBannerView.isHidden = true
      }
      if animated {
        UIView.animate(withDuration: 0.18, animations: hideBlock, completion: completion)
      } else {
        hideBlock()
        completion(true)
      }
      return
    }

    runtimeBannerLabel.text = content.text
    runtimeBannerLabel.textColor = content.tintColor
    runtimeBannerIconView.tintColor = content.tintColor
    runtimeBannerView.backgroundColor = content.backgroundColor

    if runtimeBannerView.isHidden {
      runtimeBannerView.isHidden = false
      if animated {
        runtimeBannerView.alpha = 0
        UIView.animate(withDuration: 0.2) {
          self.runtimeBannerView.alpha = 1
        }
      } else {
        runtimeBannerView.alpha = 1
      }
    }
  }

  private func runtimeBannerContent() -> RuntimeBannerContent? {
    guard VoiceWhisperModelStore.isWhisperKitEnabled else { return nil }
    guard isWhisperEnabled() else { return nil }
    guard models.contains(where: { $0.isDownloaded }) else { return nil }

    let localeIdentifier = Locale.preferredLanguages.first
    guard let runtimeSelection = modelStore.selectedDownloadedModelForCurrentDevice(localeIdentifier: localeIdentifier) else {
      return RuntimeBannerContent(
        text: "当前听写使用 Apple Speech：该机型暂无可安全运行的 Whisper 模型。",
        tintColor: .systemOrange,
        backgroundColor: UIColor.systemOrange.withAlphaComponent(0.16)
      )
    }

    let loadState = VoiceSpeechRecognizerEngine.shared.whisperLoadState(for: runtimeSelection.modelID)
    switch loadState {
    case .ready:
      return nil
    case .loading, .idle:
      VoiceSpeechRecognizerEngine.shared.prewarmWhisperModelIfNeeded(runtimeSelection.modelID)
      let modelName = VoiceWhisperModelOption.option(for: runtimeSelection.modelID).displayName
      return RuntimeBannerContent(
        text: "当前听写使用 Apple Speech：Whisper \(modelName) 正在预热中。",
        tintColor: .systemBlue,
        backgroundColor: UIColor.systemBlue.withAlphaComponent(0.14)
      )
    case .disabled:
      return nil
    }
  }

  private func syncWhisperSelectionWithAvailability() {
    let hasDownloadedModel = models.contains(where: { $0.isDownloaded })
    let whisperAvailable = VoiceWhisperModelStore.isWhisperKitEnabled
    var selectedEngines = asrSettingsStore.selectedEngines()
    if (!whisperAvailable || !hasDownloadedModel), let index = selectedEngines.firstIndex(of: .whisper) {
      selectedEngines.remove(at: index)
      if selectedEngines.isEmpty {
        selectedEngines = [.apple]
      }
      asrSettingsStore.setSelectedEngines(selectedEngines)
    }
  }

  private func isWhisperEnabled() -> Bool {
    asrSettingsStore.selectedEngines().contains(.whisper)
  }

  private func setWhisperEnabled(_ enabled: Bool) {
    if enabled {
      asrSettingsStore.setSelectedEngines([.whisper])
    } else {
      // Whisper 关闭后，主引擎回到 Apple。
      asrSettingsStore.setSelectedEngines([.apple])
    }
  }

  @objc private func handleWhisperSwitchChanged(_ sender: UISwitch) {
    guard !isApplyingWhisperToggle else { return }
    guard VoiceWhisperModelStore.isWhisperKitEnabled else {
      sender.setOn(false, animated: true)
      presentWhisperUnavailableAlert()
      return
    }
    let hasDownloadedModel = models.contains(where: { $0.isDownloaded })
    if sender.isOn, !hasDownloadedModel {
      sender.setOn(false, animated: true)
      presentErrorAlert(message: "请先下载至少一个 Whisper 模型，然后再启用 Whisper 引擎。")
      return
    }
    let targetEnabled = sender.isOn
    isApplyingWhisperToggle = true
    sender.isEnabled = false
    applyWhisperToggleAsync(targetEnabled: targetEnabled)
  }

  private func applyWhisperToggleAsync(targetEnabled: Bool) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      self.setWhisperEnabled(targetEnabled)
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.isApplyingWhisperToggle = false
        self.refreshModels()
      }
    }
  }

  private func handleAction(at indexPath: IndexPath) {
    guard VoiceWhisperModelStore.isWhisperKitEnabled else {
      presentWhisperUnavailableAlert()
      return
    }
    let model = models[indexPath.row]
    if model.isDownloaded {
      modelStore.setSelectedModel(model.option.id)
      refreshModels()
      return
    }

    startDownload(for: model.option.id, rowIndex: indexPath.row)
  }

  private func startDownload(for modelID: String, rowIndex: Int? = nil) {
    downloadingModelID = modelID
    if let rowIndex {
      settingsView.tableView.reloadRows(at: [IndexPath(row: rowIndex, section: 2)], with: .none)
    } else {
      settingsView.tableView.reloadSections(IndexSet(integer: 2), with: .none)
    }
    Task { [weak self] in
      guard let self else { return }
      do {
        _ = try await self.modelStore.downloadModel(modelID)
        await MainActor.run {
          self.downloadingModelID = nil
          self.refreshModels()
          VoiceSpeechRecognizerEngine.shared.prewarmWhisperModelIfNeeded(modelID)
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

  private func refreshRemoteModelList(presentPickerAfterFetch: Bool) {
    guard VoiceWhisperModelStore.isWhisperKitEnabled else {
      presentWhisperUnavailableAlert()
      return
    }
    guard !isFetchingRemoteModelList else { return }
    isFetchingRemoteModelList = true
    settingsView.tableView.reloadSections(IndexSet(integer: 1), with: .none)
    Task { [weak self] in
      guard let self else { return }
      do {
        let ids = try await self.modelStore.refreshRemoteModelIDs()
        await MainActor.run {
          self.isFetchingRemoteModelList = false
          self.refreshModels()
          let sizedCount = self.modelStore.remoteModelSizeCount()
          if ids.isEmpty {
            self.presentHintAlert(title: "读取完成", message: "本次未发现可下载模型。")
          } else {
            self.presentHintAlert(title: "读取完成", message: "已读取 \(ids.count) 个可下载模型，其中 \(sizedCount) 个包含大小信息。")
            if presentPickerAfterFetch {
              self.presentRemoteModelPicker()
            }
          }
        }
      } catch {
        await MainActor.run {
          self.isFetchingRemoteModelList = false
          self.settingsView.tableView.reloadSections(IndexSet(integer: 1), with: .none)
          self.presentErrorAlert(message: error.localizedDescription)
        }
      }
    }
  }

  private func presentRemoteModelPicker() {
    let ids = remoteModelIDs
    guard !ids.isEmpty else {
      presentHintAlert(title: "暂无列表", message: "请先读取可下载模型列表。")
      return
    }
    let limit = min(ids.count, 60)
    let visibleIDs = Array(ids.prefix(limit))
    let message: String? = ids.count > limit ? "共 \(ids.count) 个模型，当前仅显示前 \(limit) 个。" : nil
    let alert = UIAlertController(title: "从列表选择模型", message: message, preferredStyle: .actionSheet)
    for modelID in visibleIDs {
      alert.addAction(UIAlertAction(title: modelID, style: .default) { [weak self] _ in
        self?.startDownload(for: modelID)
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = settingsView.tableView
      popover.sourceRect = settingsView.tableView.bounds
    }
    present(alert, animated: true)
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
    guard presentedViewController == nil else { return }
    let controller = UIAlertController(title: "操作失败", message: message, preferredStyle: .alert)
    controller.addAction(UIAlertAction(title: "知道了", style: .default))
    present(controller, animated: true)
  }

  private func presentHintAlert(title: String, message: String) {
    guard presentedViewController == nil else { return }
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .default))
    present(alert, animated: true)
  }

  private func presentWhisperUnavailableAlert() {
    let message = "当前构建未启用 WhisperKit。请在 Xcode 执行 Resolve Package Dependencies，并确认 App 目标已链接 WhisperKit 后重新构建。"
    presentErrorAlert(message: message)
  }
}

extension VoiceWhisperSettingsViewController: UITableViewDataSource, UITableViewDelegate {
  func numberOfSections(in tableView: UITableView) -> Int {
    3
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if section == 0 {
      return 1
    }
    if section == 1 {
      return 2
    }
    guard VoiceWhisperModelStore.isWhisperKitEnabled else { return 0 }
    return models.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    if indexPath.section == 0 {
      let cell = tableView.dequeueReusableCell(withIdentifier: "VoiceWhisperToggleCell", for: indexPath)
      var config = cell.defaultContentConfiguration()
      config.text = "启用 Whisper 引擎"
      if models.contains(where: { $0.isDownloaded }) {
        config.secondaryText = isWhisperEnabled() ? "已启用 Whisper（互斥单选）；预热期间会临时回退 Apple。" : "未启用；打开后将切换到 Whisper 作为主引擎。"
      } else {
        config.secondaryText = "当前没有已下载模型，请先在下方下载模型。"
      }
      config.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
      config.secondaryTextProperties.color = .secondaryLabel
      cell.contentConfiguration = config
      whisperEnabledSwitch.isOn = isWhisperEnabled()
      whisperEnabledSwitch.isEnabled = VoiceWhisperModelStore.isWhisperKitEnabled && models.contains(where: { $0.isDownloaded })
      cell.accessoryView = whisperEnabledSwitch
      cell.selectionStyle = .none
      return cell
    }

    if indexPath.section == 1 {
      let cell = tableView.dequeueReusableCell(withIdentifier: "VoiceWhisperActionCell", for: indexPath)
      var config = cell.defaultContentConfiguration()
      if indexPath.row == 0 {
        config.text = "读取可下载模型列表"
        if isFetchingRemoteModelList {
          config.secondaryText = "读取中..."
        } else {
          config.secondaryText = "从 WhisperKit 官方模型仓库拉取可下载列表"
        }
        config.image = UIImage(systemName: "arrow.clockwise")
        cell.accessoryType = .none
        cell.selectionStyle = isFetchingRemoteModelList ? .none : .default
      } else {
        config.text = "从列表选择并下载"
        if remoteModelIDs.isEmpty {
          config.secondaryText = "请先读取模型列表"
        } else {
          config.secondaryText = "已缓存 \(remoteModelIDs.count) 个模型"
        }
        config.image = UIImage(systemName: "list.bullet")
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
      }
      config.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
      config.secondaryTextProperties.color = .secondaryLabel
      cell.contentConfiguration = config
      return cell
    }

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
    if section == 0 {
      return "Whisper 开关"
    }
    if section == 1 {
      return "在线模型列表"
    }
    guard VoiceWhisperModelStore.isWhisperKitEnabled else { return nil }
    return "Whisper 模型管理"
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    if section == 0 {
      guard VoiceWhisperModelStore.isWhisperKitEnabled else {
        return "当前构建未启用 WhisperKit，暂时无法下载或启用 Whisper 离线识别。"
      }
      return "识别引擎为互斥单选。启用后将切换到 Whisper；关闭后主引擎会回到 Apple。Whisper 预热期间会临时使用 Apple。"
    }
    if section == 1 {
      return "你可以先读取可下载模型列表，再像在线模型那样从列表选择并下载。"
    }
    guard VoiceWhisperModelStore.isWhisperKitEnabled else { return nil }
    return "点击“下载”后才会拉取模型；左滑可删除模型。你可以下载多个模型并切换默认模型。适配规则：系统会按设备内存与模型体积自动判定是否可用（例如内存 <6GB 且模型 >320MB、内存 <8GB 且模型 >550MB、内存 <10GB 且模型 >750MB 时会回退）。若没有可回退的小模型，Whisper 会在当前机型临时不可用，并自动回退到 Apple 识别。"
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    if indexPath.section == 0 { return }
    if indexPath.section == 1 {
      if indexPath.row == 0 {
        refreshRemoteModelList(presentPickerAfterFetch: false)
      } else if remoteModelIDs.isEmpty {
        refreshRemoteModelList(presentPickerAfterFetch: true)
      } else {
        presentRemoteModelPicker()
      }
      return
    }
    guard VoiceWhisperModelStore.isWhisperKitEnabled else {
      presentWhisperUnavailableAlert()
      return
    }
    handleAction(at: indexPath)
  }

  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    guard indexPath.section == 2 else { return nil }
    let status = models[indexPath.row]
    guard status.isDownloaded else { return nil }
    let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
      self?.deleteModel(at: indexPath, completion: completion)
    }
    return UISwipeActionsConfiguration(actions: [deleteAction])
  }
}

final class VoiceCloudASRSettingsViewController: NibLessViewController {
  private let settingsStore: VoiceASRSettingsStore = .shared
  private lazy var asrSettingsController = VoiceASRSettingsViewController()

  private let tableView: UITableView = {
    let view = UITableView(frame: .zero, style: .insetGrouped)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  override func loadView() {
    title = "在线设置"
    let rootView = UIView(frame: .zero)
    rootView.backgroundColor = .systemBackground
    rootView.addSubview(tableView)
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
    ])
    view = rootView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.dataSource = self
    tableView.delegate = self
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "VoiceCloudCell")
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    sanitizeCloudSelectionWithConfiguration()
    tableView.reloadData()
  }

  private func isCloudEnabled() -> Bool {
    settingsStore.selectedEngines().contains(.cloud)
  }

  private func hasSavedOnlineConfiguration() -> Bool {
    let provider = settingsStore.provider()
    let apiKey = (settingsStore.apiKey(for: provider) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return !apiKey.isEmpty
  }

  private func sanitizeCloudSelectionWithConfiguration() {
    guard !hasSavedOnlineConfiguration() else { return }
    var selectedEngines = settingsStore.selectedEngines()
    if let index = selectedEngines.firstIndex(of: .cloud) {
      selectedEngines.remove(at: index)
      if selectedEngines.isEmpty {
        selectedEngines = [.apple]
      }
      settingsStore.setSelectedEngines(selectedEngines)
      settingsStore.setMode(.disabled)
    }
  }

  private func setCloudEnabled(_ enabled: Bool) -> Bool {
    if enabled {
      let provider = settingsStore.provider()
      let apiKey = (settingsStore.apiKey(for: provider) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !apiKey.isEmpty else {
        presentMissingAPIKeyAlert()
        return false
      }
      settingsStore.setSelectedEngines([.cloud])
      settingsStore.setMode(.preferred)
    } else {
      settingsStore.setSelectedEngines([.apple])
      settingsStore.setMode(.disabled)
    }
    return true
  }

  @objc private func handleCloudSwitchChanged(_ sender: UISwitch) {
    guard hasSavedOnlineConfiguration() else {
      sender.setOn(false, animated: true)
      presentMissingAPIKeyAlert()
      return
    }
    let success = setCloudEnabled(sender.isOn)
    if !success {
      sender.setOn(false, animated: true)
    }
    DispatchQueue.main.async { [weak self] in
      self?.tableView.reloadSections(IndexSet(integer: 0), with: .none)
    }
  }

  private func presentMissingAPIKeyAlert() {
    let alert = UIAlertController(
      title: "无法启用在线引擎",
      message: "当前 Provider 还没有 API Key。请先进入在线 ASR 配置填写 API Key。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "去配置", style: .default) { [weak self] _ in
      guard let self else { return }
      self.navigationController?.pushViewController(self.asrSettingsController, animated: true)
    })
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    present(alert, animated: true)
  }
}

extension VoiceCloudASRSettingsViewController: UITableViewDataSource, UITableViewDelegate {
  func numberOfSections(in tableView: UITableView) -> Int {
    2
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    1
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "VoiceCloudCell", for: indexPath)
    var config = cell.defaultContentConfiguration()
    if indexPath.section == 0 {
      config.text = "启用在线引擎（仅在线）"
      let savedConfig = hasSavedOnlineConfiguration()
      if !savedConfig {
        config.secondaryText = "未配置可用 API Key，开关已禁用。请先完成在线 ASR 配置并保存。"
      } else {
        config.secondaryText = isCloudEnabled() ? "已启用；当前只使用在线 ASR。" : "未启用；开启后将切换为在线 ASR 主引擎。"
      }
      config.image = UIImage(systemName: "cloud.fill")
      config.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
      config.secondaryTextProperties.color = .secondaryLabel
      cell.contentConfiguration = config
      let switchView = UISwitch(frame: .zero)
      switchView.isOn = isCloudEnabled()
      switchView.isEnabled = savedConfig
      switchView.addTarget(self, action: #selector(handleCloudSwitchChanged(_:)), for: .valueChanged)
      cell.accessoryView = switchView
      cell.accessoryType = .none
      cell.selectionStyle = .default
      return cell
    }

    let provider = settingsStore.provider()
    let model = settingsStore.byokModel(for: provider)
    let modelText = model.isEmpty ? "未设置模型" : model
    config.text = "在线 ASR 配置"
    config.secondaryText = "\(provider.displayName) · \(modelText)"
    config.image = UIImage(systemName: "slider.horizontal.3")
    config.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
    config.secondaryTextProperties.color = .secondaryLabel
    cell.contentConfiguration = config
    cell.accessoryView = nil
    cell.accessoryType = .disclosureIndicator
    cell.selectionStyle = .default
    return cell
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    if section == 0 {
      return "在线开关"
    }
    return "在线 ASR 参数"
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    if section == 0 {
      return "识别引擎是互斥单选。你必须先在“在线 ASR 配置”里保存有效 API Key，才能切换到在线引擎。"
    }
    return "你可以在这里配置 Provider、Base URL、模型和 API Key。"
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    if indexPath.section == 0 {
      guard hasSavedOnlineConfiguration() else {
        presentMissingAPIKeyAlert()
        return
      }
      _ = setCloudEnabled(!isCloudEnabled())
      tableView.reloadSections(IndexSet(integer: 0), with: .none)
      return
    }
    navigationController?.pushViewController(asrSettingsController, animated: true)
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
    let actionBlue = UIColor.systemBlue
    let themeColor = UIColor(named: "AccentColor") ?? actionBlue
    titleLabel.text = status.option.displayName
    subtitleLabel.text = "\(status.sizeText) · \(status.option.summary)"
    stateLabel.textColor = .secondaryLabel
    actionButton.layer.borderWidth = 1
    actionButton.layer.borderColor = UIColor.clear.cgColor
    if isDownloading {
      stateLabel.text = "状态：下载中..."
      stateLabel.textColor = .systemOrange
      actionButton.setTitle("下载中", for: .normal)
      actionButton.isEnabled = false
      actionButton.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.18)
      actionButton.setTitleColor(.systemOrange, for: .normal)
      actionButton.layer.borderColor = UIColor.systemOrange.withAlphaComponent(0.35).cgColor
      return
    }

    if status.isDownloaded {
      if status.isSelected {
        stateLabel.text = "状态：已下载 · 当前使用"
        stateLabel.textColor = .systemGreen
        actionButton.setTitle("使用中", for: .normal)
        actionButton.isEnabled = false
        actionButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.18)
        actionButton.setTitleColor(.systemGreen, for: .normal)
        actionButton.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.35).cgColor
      } else {
        stateLabel.text = "状态：已下载"
        stateLabel.textColor = actionBlue
        actionButton.setTitle("使用", for: .normal)
        actionButton.isEnabled = true
        actionButton.backgroundColor = actionBlue.withAlphaComponent(0.18)
        actionButton.setTitleColor(actionBlue, for: .normal)
        actionButton.layer.borderColor = actionBlue.withAlphaComponent(0.35).cgColor
      }
    } else {
      stateLabel.text = "状态：未下载"
      actionButton.setTitle("下载", for: .normal)
      actionButton.isEnabled = true
      actionButton.backgroundColor = themeColor.withAlphaComponent(0.12)
      actionButton.setTitleColor(themeColor, for: .normal)
      actionButton.layer.borderColor = themeColor.withAlphaComponent(0.28).cgColor
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
  private lazy var llmSettingsController = VoiceLLMSettingsViewController()
  private lazy var accountProfileController: VoiceAccountProfileViewController = {
    let controller = VoiceAccountProfileViewController()
    controller.onAccountUpdated = { [weak self] in
      self?.accountView.tableView.reloadData()
    }
    return controller
  }()

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

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    accountView.tableView.reloadData()
  }
}

extension VoiceAccountViewController: UITableViewDataSource, UITableViewDelegate {
  func numberOfSections(in tableView: UITableView) -> Int {
    3
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch section {
    case 0: return 1
    case 1: return 1
    case 2: return 2
    default: return 0
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
      cell.textLabel?.text = "账号与订阅（开发中）"
      cell.imageView?.image = UIImage(systemName: "person.crop.circle")
    case (2, 0):
      cell.textLabel?.text = "语音模型"
      cell.imageView?.image = UIImage(systemName: "waveform.badge.mic")
    case (2, 1):
      cell.textLabel?.text = "AI 处理配置"
      cell.imageView?.image = UIImage(systemName: "brain.head.profile")
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
    if indexPath.section == 1, indexPath.row == 0 {
      navigationController?.pushViewController(accountProfileController, animated: true)
      return
    }
    if indexPath.section == 2, indexPath.row == 0 {
      navigationController?.pushViewController(modelManagementController, animated: true)
      return
    }
    if indexPath.section == 2, indexPath.row == 1 {
      navigationController?.pushViewController(llmSettingsController, animated: true)
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

final class VoiceAccountProfileViewController: NibLessViewController {
  var onAccountUpdated: (() -> Void)?
  private let rootView = VoiceAccountProfileRootView()
  private let gitHubStarsService = VoiceGitHubStarsService.shared
  private var isLoadingGitHubStars = false
  private var gitHubStarsCount: Int?
  private var gitHubStarsErrorMessage: String?

  override func loadView() {
    title = "账号与订阅"
    view = rootView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    rootView.tableView.dataSource = self
    rootView.tableView.delegate = self
    rootView.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ProfileCell")
    refreshGitHubStars(force: false)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    rootView.tableView.reloadData()
  }

  private func openSubscriptionManagement() {
    guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else {
      return
    }
    UIApplication.shared.open(url)
  }

  private func openGitHubRepository() {
    guard let url = gitHubStarsService.repositoryWebURL() else {
      presentSimpleAlert(title: "打开失败", message: "GitHub 仓库地址无效。")
      return
    }
    UIApplication.shared.open(url)
  }

  private func presentAccountComingSoonAlert() {
    presentSimpleAlert(
      title: "功能开发中",
      message: "账号登录与订阅绑定正在开发中，请暂时不要输入任何账号信息。"
    )
  }

  private func presentSimpleAlert(title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .default))
    present(alert, animated: true)
  }

  private func reloadCommunitySection() {
    guard rootView.tableView.numberOfSections > 2 else {
      rootView.tableView.reloadData()
      return
    }
    rootView.tableView.reloadSections(IndexSet(integer: 2), with: .none)
  }

  private func refreshGitHubStars(force: Bool) {
    if isLoadingGitHubStars {
      return
    }
    if !force, let cachedCount = gitHubStarsService.cachedStarsCount(maxAge: 3600) {
      gitHubStarsCount = cachedCount
      gitHubStarsErrorMessage = nil
      reloadCommunitySection()
      return
    }

    isLoadingGitHubStars = true
    reloadCommunitySection()
    Task { [weak self] in
      guard let self else { return }
      do {
        let stars = try await gitHubStarsService.fetchStars(force: force)
        await MainActor.run {
          self.isLoadingGitHubStars = false
          self.gitHubStarsCount = stars
          self.gitHubStarsErrorMessage = nil
          self.reloadCommunitySection()
        }
      } catch let error as VoiceGitHubStarsError {
        await MainActor.run {
          self.isLoadingGitHubStars = false
          self.gitHubStarsErrorMessage = error.localizedDescription
          self.reloadCommunitySection()
        }
      } catch {
        await MainActor.run {
          self.isLoadingGitHubStars = false
          self.gitHubStarsErrorMessage = error.localizedDescription
          self.reloadCommunitySection()
        }
      }
    }
  }
}

extension VoiceAccountProfileViewController: UITableViewDataSource, UITableViewDelegate {
  func numberOfSections(in tableView: UITableView) -> Int {
    3
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    1
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    switch section {
    case 0:
      return "账号"
    case 1:
      return "订阅"
    default:
      return "社区支持"
    }
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    guard section == 2 else {
      return nil
    }
    return "如果你希望我加速推出订阅服务来使用在线大模型，请务必点赞让我看到；因为当前仅支持用户自带各厂商 API Key。"
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "ProfileCell", for: indexPath)
    cell.textLabel?.font = .systemFont(ofSize: 15, weight: .regular)
    cell.textLabel?.textColor = .label
    cell.selectionStyle = .default
    cell.accessoryType = .none

    switch indexPath.section {
    case 0:
      cell.textLabel?.text = "账号系统开发中（暂不开放登录）"
      cell.imageView?.image = UIImage(systemName: "hourglass")
    case 1:
      cell.textLabel?.text = "管理订阅"
      cell.imageView?.image = UIImage(systemName: "creditcard")
      cell.accessoryType = .disclosureIndicator
    default:
      if isLoadingGitHubStars {
        cell.textLabel?.text = "GitHub Stars 读取中..."
        cell.textLabel?.textColor = .secondaryLabel
      } else if let stars = gitHubStarsCount {
        cell.textLabel?.text = "GitHub Star 支持我们 ⭐（\(stars)）"
        cell.textLabel?.textColor = .systemGreen
      } else {
        cell.textLabel?.text = "GitHub Star 支持我们 ⭐（点击查看）"
        cell.textLabel?.textColor = gitHubStarsErrorMessage == nil ? .label : .systemOrange
      }
      cell.imageView?.image = UIImage(systemName: "star.fill")
      cell.accessoryType = .disclosureIndicator
    }
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    switch indexPath.section {
    case 0:
      presentAccountComingSoonAlert()
    case 1:
      openSubscriptionManagement()
    default:
      openGitHubRepository()
      refreshGitHubStars(force: true)
    }
  }
}

enum VoiceGitHubStarsError: LocalizedError {
  case invalidURL
  case invalidResponse
  case requestFailed(statusCode: Int)
  case transport(message: String)
  case decoding(message: String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "GitHub 地址无效。"
    case .invalidResponse:
      return "GitHub 响应格式无效。"
    case .requestFailed(let statusCode):
      return "GitHub 请求失败（\(statusCode)）。"
    case .transport(let message):
      return "网络请求失败：\(message)"
    case .decoding(let message):
      return "数据解析失败：\(message)"
    }
  }
}

final class VoiceGitHubStarsService {
  static let shared = VoiceGitHubStarsService()

  private let session: URLSession
  private let userDefaults: UserDefaults

  private enum Constants {
    static let repositoryOwner = "xjwhnxjwhn"
    static let repositoryName = "nanomouse"
    static let cachedStarsCountKey = "voice.github.stars.count.v1"
    static let cachedStarsUpdatedAtKey = "voice.github.stars.updated_at.v1"
  }

  init(
    session: URLSession = .shared,
    userDefaults: UserDefaults = .standard
  ) {
    self.session = session
    self.userDefaults = userDefaults
  }

  func repositoryWebURL() -> URL? {
    URL(string: "https://github.com/\(Constants.repositoryOwner)/\(Constants.repositoryName)")
  }

  func cachedStarsCount(maxAge: TimeInterval) -> Int? {
    let count = userDefaults.object(forKey: Constants.cachedStarsCountKey) as? Int
    let updatedAt = userDefaults.double(forKey: Constants.cachedStarsUpdatedAtKey)
    guard let count, updatedAt > 0 else {
      return nil
    }
    guard Date().timeIntervalSince1970 - updatedAt <= maxAge else {
      return nil
    }
    return count
  }

  func fetchStars(force: Bool) async throws -> Int {
    if !force, let cached = cachedStarsCount(maxAge: 3600) {
      return cached
    }
    let apiURLString = "https://api.github.com/repos/\(Constants.repositoryOwner)/\(Constants.repositoryName)"
    guard let apiURL = URL(string: apiURLString) else {
      throw VoiceGitHubStarsError.invalidURL
    }

    var request = URLRequest(url: apiURL)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.setValue("nanomouse-ios-app", forHTTPHeaderField: "User-Agent")

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw VoiceGitHubStarsError.transport(message: error.localizedDescription)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw VoiceGitHubStarsError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw VoiceGitHubStarsError.requestFailed(statusCode: httpResponse.statusCode)
    }

    let payload: VoiceGitHubRepositoryPayload
    do {
      payload = try JSONDecoder().decode(VoiceGitHubRepositoryPayload.self, from: data)
    } catch {
      throw VoiceGitHubStarsError.decoding(message: error.localizedDescription)
    }

    userDefaults.set(payload.stargazersCount, forKey: Constants.cachedStarsCountKey)
    userDefaults.set(Date().timeIntervalSince1970, forKey: Constants.cachedStarsUpdatedAtKey)
    return payload.stargazersCount
  }
}

private struct VoiceGitHubRepositoryPayload: Decodable {
  let stargazersCount: Int

  private enum CodingKeys: String, CodingKey {
    case stargazersCount = "stargazers_count"
  }
}

final class VoiceAccountProfileRootView: NibLessView {
  let tableView: UITableView = {
    let view = UITableView(frame: .zero, style: .insetGrouped)
    view.translatesAutoresizingMaskIntoConstraints = false
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

// MARK: - ASR Settings

final class VoiceASRSettingsViewController: NibLessViewController {
  private let settingsStore: VoiceASRSettingsStore = .shared
  private let settingsView = VoiceASRSettingsRootView()
  private var currentProviderSelection: VoiceASRProvider = .openAI

  override func loadView() {
    title = "在线 ASR 配置"
    view = settingsView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    settingsView.providerButton.addTarget(self, action: #selector(handleProviderTap), for: .touchUpInside)
    settingsView.chooseModelButton.addTarget(self, action: #selector(handleChooseModelTap), for: .touchUpInside)
    settingsView.saveButton.addTarget(self, action: #selector(handleSaveTap), for: .touchUpInside)
    settingsView.apiKeyField.addTarget(self, action: #selector(handleAPIKeyEditingChanged), for: .editingChanged)
    loadSettings()
  }

  private func loadSettings() {
    let cloudEnabled = settingsStore.selectedEngines().contains(.cloud)
    let provider = settingsStore.provider()
    currentProviderSelection = provider
    settingsView.updateProviderSelection(provider: provider)
    settingsView.updateProviderPlaceholders(provider: provider)
    settingsView.updateProviderHint(provider: provider)
    settingsView.proxyEndpointField.text = settingsStore.proxyEndpoint()
    settingsView.byokBaseURLField.text = settingsStore.byokBaseURL(for: provider)
    settingsView.modelField.text = settingsStore.byokModel(for: provider)
    settingsView.apiKeyField.text = settingsStore.apiKey(for: provider)
    settingsView.updateVisibleSections(cloudEnabled: cloudEnabled)
    refreshSaveButtonState()
  }

  @objc private func handleAPIKeyEditingChanged() {
    refreshSaveButtonState()
  }

  @objc private func handleProviderTap() {
    let alert = UIAlertController(title: "选择 ASR Provider", message: nil, preferredStyle: .actionSheet)
    for provider in VoiceASRProvider.allCases {
      let title = provider == currentProviderSelection ? "✓ \(provider.displayName)" : provider.displayName
      alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
        self?.applyProvider(provider)
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = settingsView.providerButton
      popover.sourceRect = settingsView.providerButton.bounds
    }
    present(alert, animated: true)
  }

  @objc private func handleChooseModelTap() {
    let models = currentProviderSelection.staticModelCandidates
    if models.isEmpty {
      presentHintAlert(title: "暂无候选模型", message: "该 Provider 目前没有内置候选模型，请手动输入。")
      return
    }
    let alert = UIAlertController(title: "选择 ASR 模型", message: nil, preferredStyle: .actionSheet)
    for model in models {
      alert.addAction(UIAlertAction(title: model, style: .default) { [weak self] _ in
        self?.settingsView.modelField.text = model
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = settingsView.chooseModelButton
      popover.sourceRect = settingsView.chooseModelButton.bounds
    }
    present(alert, animated: true)
  }

  @objc private func handleSaveTap() {
    let apiKeyInput = (settingsView.apiKeyField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKeyInput.isEmpty else {
      presentHintAlert(title: "无法保存", message: "请先填写 API Key，然后再保存在线 ASR 配置。")
      return
    }
    persistSettings()
    let cloudEnabled = settingsStore.selectedEngines().contains(.cloud)
    settingsView.updateVisibleSections(cloudEnabled: cloudEnabled)
    let message: String
    if !cloudEnabled {
      message = "当前未勾选在线引擎，在线配置已保存（暂不生效）。"
    } else {
      message = "已保存在线 ASR 配置。当前主引擎为在线 ASR。"
    }
    presentHintAlert(title: "保存成功", message: message)
  }

  private func applyProvider(_ provider: VoiceASRProvider) {
    let previousProvider = currentProviderSelection
    if provider != previousProvider {
      // 切换供应商前先保存当前草稿，避免跨供应商切换时丢失输入。
      settingsStore.setByokBaseURL(settingsView.byokBaseURLField.text ?? "", for: previousProvider)
      settingsStore.setByokModel(settingsView.modelField.text ?? "", for: previousProvider)
      settingsStore.setAPIKey(settingsView.apiKeyField.text, for: previousProvider)
      currentProviderSelection = provider
    }
    settingsView.updateProviderSelection(provider: provider)
    settingsView.updateProviderPlaceholders(provider: provider)
    settingsView.updateProviderHint(provider: provider)
    settingsView.byokBaseURLField.text = settingsStore.byokBaseURL(for: provider)
    settingsView.modelField.text = settingsStore.byokModel(for: provider)
    settingsView.apiKeyField.text = settingsStore.apiKey(for: provider)
    refreshSaveButtonState()
  }

  private func persistSettings() {
    let cloudEnabled = settingsStore.selectedEngines().contains(.cloud)
    let provider = currentProviderSelection
    let proxyEndpoint = settingsView.proxyEndpointField.text ?? ""
    let baseURLInput = (settingsView.byokBaseURLField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let modelInput = (settingsView.modelField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let apiKeyInput = settingsView.apiKeyField.text

    let baseURL = baseURLInput.isEmpty ? provider.defaultBaseURL : baseURLInput
    let model = modelInput.isEmpty ? provider.defaultModel : modelInput

    settingsStore.setMode(cloudEnabled ? .preferred : .disabled)
    settingsStore.setProvider(provider)
    settingsStore.setProxyEndpoint(proxyEndpoint)
    settingsStore.setByokBaseURL(baseURL, for: provider)
    settingsStore.setByokModel(model, for: provider)
    settingsStore.setAPIKey(apiKeyInput, for: provider)

    settingsView.byokBaseURLField.text = baseURL
    settingsView.modelField.text = model
  }

  private func presentHintAlert(title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .default))
    present(alert, animated: true)
  }

  private func refreshSaveButtonState() {
    let apiKeyInput = (settingsView.apiKeyField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    settingsView.setSaveButtonEnabled(!apiKeyInput.isEmpty)
  }
}

final class VoiceASRSettingsRootView: NibLessView {
  let providerButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("OpenAI", for: .normal)
    button.contentHorizontalAlignment = .left
    button.backgroundColor = .secondarySystemBackground
    button.layer.cornerRadius = 10
    button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    return button
  }()

  let proxyEndpointField = VoiceASRSettingsRootView.makeTextField(
    placeholder: "https://your-server.example.com/api/asr/transcribe（可选）"
  )

  let byokBaseURLField = VoiceASRSettingsRootView.makeTextField(
    placeholder: "https://api.openai.com/v1"
  )

  let modelField = VoiceASRSettingsRootView.makeTextField(
    placeholder: "gpt-4o-mini-transcribe"
  )

  let chooseModelButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("从列表选择模型", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
    button.layer.cornerRadius = 10
    return button
  }()

  let apiKeyField: UITextField = {
    let field = VoiceASRSettingsRootView.makeTextField(placeholder: "输入 ASR API Key")
    field.isSecureTextEntry = true
    field.textContentType = .oneTimeCode
    field.autocorrectionType = .no
    field.autocapitalizationType = .none
    field.spellCheckingType = .no
    return field
  }()

  let saveButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("保存配置", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    button.setTitleColor(.white, for: .normal)
    button.backgroundColor = .systemBlue
    button.layer.cornerRadius = 12
    return button
  }()

  private let providerHintLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    return label
  }()

  private let modeHintLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    return label
  }()

  private let scrollView: UIScrollView = {
    let view = UIScrollView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let contentStack: UIStackView = {
    let stack = UIStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 14
    return stack
  }()

  private lazy var providerSection = makeControlSection(title: "Provider", control: providerButton)

  private lazy var proxySection = makeSection(
    title: "代理转写地址",
    description: "用于不支持应用内直连的厂商；如果留空，系统会尝试直连。",
    field: proxyEndpointField
  )

  private lazy var byokBaseURLSection = makeSection(
    title: "BYOK Base URL",
    description: "仅在 BYOK 直连时使用。",
    field: byokBaseURLField
  )

  private lazy var modelSection: UIView = {
    let stack = UIStackView(arrangedSubviews: [modelField, chooseModelButton])
    stack.axis = .vertical
    stack.spacing = 8
    return makeSection(
      title: "模型",
      description: "优先建议先选模型再保存；你也可以手动输入模型名。",
      content: stack
    )
  }()

  private lazy var apiKeySection = makeSection(
    title: "BYOK API Key",
    description: "每个 Provider 使用独立 Key，不会互相覆盖。",
    field: apiKeyField
  )

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

    contentStack.addArrangedSubview(modeHintLabel)
    contentStack.addArrangedSubview(providerSection)
    contentStack.addArrangedSubview(providerHintLabel)
    contentStack.addArrangedSubview(proxySection)
    contentStack.addArrangedSubview(byokBaseURLSection)
    contentStack.addArrangedSubview(modelSection)
    contentStack.addArrangedSubview(apiKeySection)
    contentStack.addArrangedSubview(saveButton)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
      contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
      contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
      contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
      contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),

      saveButton.heightAnchor.constraint(equalToConstant: 48),
      chooseModelButton.heightAnchor.constraint(equalToConstant: 40),
    ])
  }

  override func setupAppearance() {
    backgroundColor = .systemBackground
    updateProviderSelection(provider: .openAI)
    updateProviderPlaceholders(provider: .openAI)
    updateProviderHint(provider: .openAI)
    updateVisibleSections(cloudEnabled: false)
    setSaveButtonEnabled(false)
  }

  func updateVisibleSections(cloudEnabled: Bool) {
    if !cloudEnabled {
      modeHintLabel.text = "当前在线引擎未启用。你可以先填写配置，返回“在线设置”后再开启。"
      return
    }

    modeHintLabel.text = "在线引擎已启用；当前听写只使用在线 ASR（互斥单选）。"
  }

  func updateProviderSelection(provider: VoiceASRProvider) {
    providerButton.setTitle(provider.displayName, for: .normal)
  }

  func updateProviderPlaceholders(provider: VoiceASRProvider) {
    byokBaseURLField.placeholder = provider.defaultBaseURL.isEmpty ? "输入 ASR Base URL" : provider.defaultBaseURL
    modelField.placeholder = provider.defaultModel.isEmpty ? "输入模型名" : provider.defaultModel
  }

  func updateProviderHint(provider: VoiceASRProvider) {
    let baseURL = provider.defaultBaseURL.isEmpty ? "未预置（请手动填写）" : provider.defaultBaseURL
    providerHintLabel.text = "当前 Provider：\(provider.displayName)。默认 Base URL：\(baseURL)。\(provider.integrationHint)"
  }

  func setSaveButtonEnabled(_ enabled: Bool) {
    saveButton.isEnabled = enabled
    saveButton.backgroundColor = enabled ? .systemBlue : .systemGray3
    saveButton.setTitleColor(enabled ? .white : .secondaryLabel, for: .normal)
  }
}

private extension VoiceASRSettingsRootView {
  static func makeTextField(placeholder: String) -> UITextField {
    let field = UITextField(frame: .zero)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.borderStyle = .roundedRect
    field.placeholder = placeholder
    field.clearButtonMode = .whileEditing
    field.autocapitalizationType = .none
    field.autocorrectionType = .no
    field.spellCheckingType = .no
    field.returnKeyType = .done
    return field
  }

  func makeControlSection(title: String, control: UIView) -> UIView {
    let titleLabel = UILabel(frame: .zero)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
    titleLabel.textColor = .secondaryLabel
    titleLabel.text = title

    let stack = UIStackView(arrangedSubviews: [titleLabel, control])
    stack.axis = .vertical
    stack.spacing = 8
    return stack
  }

  func makeSection(
    title: String,
    description: String,
    field: UIView
  ) -> UIView {
    makeSection(
      title: title,
      description: description,
      content: field
    )
  }

  func makeSection(
    title: String,
    description: String,
    content: UIView
  ) -> UIView {
    let titleLabel = UILabel(frame: .zero)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
    titleLabel.textColor = .secondaryLabel
    titleLabel.text = title

    let descriptionLabel = UILabel(frame: .zero)
    descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
    descriptionLabel.font = .systemFont(ofSize: 12, weight: .regular)
    descriptionLabel.textColor = .tertiaryLabel
    descriptionLabel.numberOfLines = 0
    descriptionLabel.text = description

    let stack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, content])
    stack.axis = .vertical
    stack.spacing = 6
    return stack
  }
}

// MARK: - LLM Lazy Picker

final class VoiceLazyModelPickerViewController: NibLessViewController {
  private let allItems: [String]
  private let subtitleText: String
  private let pageSize: Int
  private let onSelect: (String) -> Void
  private var visibleItems: [String] = []
  private var isLoadingMore = false

  private let tableView: UITableView = {
    let view = UITableView(frame: .zero, style: .insetGrouped)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.keyboardDismissMode = .onDrag
    return view
  }()

  private let summaryLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 2
    return label
  }()

  init(
    title: String,
    subtitle: String,
    items: [String],
    pageSize: Int = 40,
    onSelect: @escaping (String) -> Void
  ) {
    self.allItems = items
    self.subtitleText = subtitle
    self.pageSize = max(20, pageSize)
    self.onSelect = onSelect
    super.init()
    self.title = title
  }

  override func loadView() {
    let root = UIView(frame: .zero)
    root.backgroundColor = .systemBackground
    root.addSubview(summaryLabel)
    root.addSubview(tableView)
    NSLayoutConstraint.activate([
      summaryLabel.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 8),
      summaryLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
      summaryLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

      tableView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 8),
      tableView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
    ])
    view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.dataSource = self
    tableView.delegate = self
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "VoiceLazyModelPickerCell")
    summaryLabel.text = subtitleText
    loadNextPageIfNeeded(force: true)
  }

  private func loadNextPageIfNeeded(force: Bool = false) {
    guard force || !isLoadingMore else { return }
    guard visibleItems.count < allItems.count else { return }
    isLoadingMore = true
    // 分页懒加载：只在滚动接近底部时追加下一批，避免一次性渲染大量 actionSheet 项目。
    let start = visibleItems.count
    let end = min(start + pageSize, allItems.count)
    visibleItems.append(contentsOf: allItems[start..<end])
    isLoadingMore = false
    tableView.reloadData()
  }
}

extension VoiceLazyModelPickerViewController: UITableViewDataSource, UITableViewDelegate {
  func numberOfSections(in tableView: UITableView) -> Int {
    1
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    visibleItems.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "VoiceLazyModelPickerCell", for: indexPath)
    var config = cell.defaultContentConfiguration()
    config.text = visibleItems[indexPath.row]
    config.textProperties.font = .systemFont(ofSize: 14, weight: .regular)
    cell.contentConfiguration = config
    cell.accessoryType = .none
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let selected = visibleItems[indexPath.row]
    onSelect(selected)
    if let nav = navigationController {
      if nav.viewControllers.first != self {
        nav.popViewController(animated: true)
        return
      }
      if nav.presentingViewController != nil {
        nav.dismiss(animated: true)
        return
      }
    }
    if presentingViewController != nil {
      dismiss(animated: true)
    }
  }

  func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    let preloadThreshold = max(5, pageSize / 3)
    if indexPath.row >= visibleItems.count - preloadThreshold {
      loadNextPageIfNeeded()
    }
  }
}

// MARK: - LLM Settings

final class VoiceLLMSettingsViewController: NibLessViewController {
  private let settingsStore: VoiceLLMSettingsStore = .shared
  private let llmService: VoiceLLMService = .shared
  private let settingsView = VoiceLLMSettingsRootView()
  private var cachedModelIDs: [String] = []
  private var promptPresets: [VoiceLLMPromptPreset] = []
  private var selectedPromptPresetID: String = ""
  private var currentProviderSelection: VoiceLLMProvider = .openAI

  override func loadView() {
    title = "AI 处理配置"
    view = settingsView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    settingsView.llmEnabledControl.addTarget(self, action: #selector(handleLLMEnabledChanged), for: .valueChanged)
    settingsView.authModeControl.addTarget(self, action: #selector(handleAuthModeChanged), for: .valueChanged)
    settingsView.providerButton.addTarget(self, action: #selector(handleProviderTap), for: .touchUpInside)
    settingsView.refreshModelsButton.addTarget(self, action: #selector(handleRefreshModelsTap), for: .touchUpInside)
    settingsView.chooseModelButton.addTarget(self, action: #selector(handleChooseModelTap), for: .touchUpInside)
    settingsView.choosePresetButton.addTarget(self, action: #selector(handleChoosePresetTap), for: .touchUpInside)
    settingsView.savePresetButton.addTarget(self, action: #selector(handleSavePresetTap), for: .touchUpInside)
    settingsView.resetPresetsButton.addTarget(self, action: #selector(handleResetPresetsTap), for: .touchUpInside)
    settingsView.saveButton.addTarget(self, action: #selector(handleSaveTap), for: .touchUpInside)
    loadSettings()
  }

  private func loadSettings() {
    let llmEnabled = settingsStore.isLLMEnabled()
    let mode = settingsStore.authMode()
    let provider = settingsStore.provider()
    settingsView.llmEnabledControl.selectedSegmentIndex = llmEnabled ? 1 : 0
    settingsView.authModeControl.selectedSegmentIndex = (mode == .proxy) ? 0 : 1
    currentProviderSelection = provider
    settingsView.updateProviderSelection(provider: provider)
    settingsView.updateProviderPlaceholders(provider: provider)
    settingsView.proxyEndpointField.text = settingsStore.proxyEndpoint()
    settingsView.proxyModelsEndpointField.text = settingsStore.proxyModelsEndpoint()
    settingsView.byokBaseURLField.text = settingsStore.byokBaseURL(for: provider)
    settingsView.modelField.text = settingsStore.byokModel(for: provider)
    settingsView.apiKeyField.text = settingsStore.apiKey(for: provider)
    cachedModelIDs = settingsStore.cachedModelIDs()
    promptPresets = settingsStore.promptPresets()
    let selectedPreset = settingsStore.selectedPromptPreset()
    selectedPromptPresetID = selectedPreset.id
    settingsView.updatePresetEditor(preset: selectedPreset, totalCount: promptPresets.count)
    settingsView.updateVisibleSections(authMode: mode, isLLMEnabled: llmEnabled)
    settingsView.updateProviderHint(provider: provider)
    settingsView.updateCachedModelHint(modelCount: cachedModelIDs.count, updatedAt: settingsStore.cachedModelsUpdatedAt())
  }

  private func authModeForSelectedIndex() -> VoiceLLMAuthMode {
    settingsView.authModeControl.selectedSegmentIndex == 1 ? .byok : .proxy
  }

  private func llmEnabledForSelectedIndex() -> Bool {
    settingsView.llmEnabledControl.selectedSegmentIndex == 1
  }

  @objc private func handleLLMEnabledChanged() {
    let mode = authModeForSelectedIndex()
    settingsView.updateVisibleSections(authMode: mode, isLLMEnabled: llmEnabledForSelectedIndex())
  }

  @objc private func handleAuthModeChanged() {
    let mode = authModeForSelectedIndex()
    settingsView.updateVisibleSections(authMode: mode, isLLMEnabled: llmEnabledForSelectedIndex())
  }

  @objc private func handleProviderTap() {
    let alert = UIAlertController(title: "选择 Provider", message: nil, preferredStyle: .actionSheet)
    for provider in VoiceLLMProvider.allCases {
      let title = provider == currentProviderSelection ? "✓ \(provider.displayName)" : provider.displayName
      alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
        self?.applyProvider(provider)
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = settingsView.providerButton
      popover.sourceRect = settingsView.providerButton.bounds
    }
    present(alert, animated: true)
  }

  private func applyProvider(_ provider: VoiceLLMProvider) {
    let previousProvider = currentProviderSelection
    if provider != previousProvider {
      // 用户切换 Provider 时先保存当前供应商草稿，避免跨供应商切换时丢失。
      settingsStore.setByokBaseURL(settingsView.byokBaseURLField.text ?? "", for: previousProvider)
      settingsStore.setByokModel(settingsView.modelField.text ?? "", for: previousProvider)
      settingsStore.setAPIKey(settingsView.apiKeyField.text, for: previousProvider)
      currentProviderSelection = provider
    }
    settingsView.updateProviderSelection(provider: provider)
    settingsView.updateProviderPlaceholders(provider: provider)
    settingsView.updateProviderHint(provider: provider)
    settingsView.byokBaseURLField.text = settingsStore.byokBaseURL(for: provider)
    settingsView.modelField.text = settingsStore.byokModel(for: provider)
    settingsView.apiKeyField.text = settingsStore.apiKey(for: provider)
  }

  @objc private func handleRefreshModelsTap() {
    persistFormSettings()
    settingsView.refreshModelsButton.isEnabled = false
    settingsView.refreshModelsButton.setTitle("读取中...", for: .normal)

    let config = settingsStore.runtimeConfig()
    if config.authMode == .byok {
      let apiKey = (config.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if apiKey.isEmpty {
        Task { [weak self] in
          guard let self else { return }
          do {
            let officialModels = try await llmService.fetchOfficialCatalogModels(provider: config.provider)
            await MainActor.run {
              self.cachedModelIDs = officialModels
              self.settingsStore.setCachedModelIDs(officialModels)
              self.settingsView.updateCachedModelHint(
                modelCount: officialModels.count,
                updatedAt: self.settingsStore.cachedModelsUpdatedAt()
              )
              self.settingsView.refreshModelsButton.isEnabled = true
              self.settingsView.refreshModelsButton.setTitle("读取模型列表", for: .normal)
              self.presentModelPicker(officialModels)
              self.presentHintAlert(
                title: "已使用官网模型列表",
                message: "你当前未填写 API Key，系统已从官方公开文档抓取候选模型。填写 API Key 后再次读取可获取实时可用列表。"
              )
            }
          } catch {
            let fallbackModels = config.provider.staticModelCandidates
            await MainActor.run {
              self.settingsView.refreshModelsButton.isEnabled = true
              self.settingsView.refreshModelsButton.setTitle("读取模型列表", for: .normal)
              if fallbackModels.isEmpty {
                self.presentErrorAlert(
                  title: "读取失败",
                  message: error.localizedDescription
                )
                return
              }
              self.cachedModelIDs = fallbackModels
              self.settingsStore.setCachedModelIDs(fallbackModels)
              self.settingsView.updateCachedModelHint(
                modelCount: fallbackModels.count,
                updatedAt: self.settingsStore.cachedModelsUpdatedAt()
              )
              self.presentModelPicker(fallbackModels)
              self.presentHintAlert(
                title: "官网抓取失败，已回退",
                message: "官方页面暂时不可用，系统已回退到本地候选模型。你可以稍后再试，或先填写 API Key。"
              )
            }
          }
        }
        return
      }
    }

    Task { [weak self] in
      guard let self else { return }
      do {
        let modelIDs = try await llmService.fetchAvailableModels()
        await MainActor.run {
          self.cachedModelIDs = modelIDs
          self.settingsStore.setCachedModelIDs(modelIDs)
          self.settingsView.updateCachedModelHint(
            modelCount: modelIDs.count,
            updatedAt: self.settingsStore.cachedModelsUpdatedAt()
          )
          self.settingsView.refreshModelsButton.isEnabled = true
          self.settingsView.refreshModelsButton.setTitle("读取模型列表", for: .normal)
          self.presentModelPicker(modelIDs)
        }
      } catch {
        await MainActor.run {
          self.settingsView.refreshModelsButton.isEnabled = true
          self.settingsView.refreshModelsButton.setTitle("读取模型列表", for: .normal)
          self.presentErrorAlert(
            title: "读取失败",
            message: error.localizedDescription
          )
        }
      }
    }
  }

  @objc private func handleChooseModelTap() {
    if cachedModelIDs.isEmpty {
      presentErrorAlert(
        title: "暂无模型列表",
        message: "请先点击“读取模型列表”，或者手动输入模型名。"
      )
      return
    }
    presentModelPicker(cachedModelIDs)
  }

  @objc private func handleChoosePresetTap() {
    // 切换预设前先保存当前草稿，避免用户来回切换时丢失手动修改。
    persistCurrentPresetDraft()
    let options = settingsStore.promptPresets()
    if options.isEmpty {
      presentErrorAlert(title: "暂无预设", message: "当前没有可用预设，请稍后重试。")
      return
    }
    promptPresets = options

    let alert = UIAlertController(
      title: "选择处理预设",
      message: "每次 AI 处理只会使用一个预设。",
      preferredStyle: .actionSheet
    )
    for preset in options {
      let title = preset.id == selectedPromptPresetID ? "✓ \(preset.name)" : preset.name
      alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
        guard let self else { return }
        _ = self.settingsStore.setSelectedPromptPresetID(preset.id)
        self.selectedPromptPresetID = preset.id
        self.settingsView.updatePresetEditor(preset: preset, totalCount: options.count)
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = settingsView.choosePresetButton
      popover.sourceRect = settingsView.choosePresetButton.bounds
    }
    present(alert, animated: true)
  }

  @objc private func handleSavePresetTap() {
    guard !selectedPromptPresetID.isEmpty else {
      presentErrorAlert(title: "保存失败", message: "当前没有选中的预设。")
      return
    }
    let name = settingsView.presetNameField.text ?? ""
    let instruction = settingsView.presetInstructionView.text ?? ""
    guard let updated = settingsStore.updatePromptPreset(
      id: selectedPromptPresetID,
      name: name,
      instruction: instruction
    ) else {
      presentErrorAlert(title: "保存失败", message: "预设保存失败，请稍后重试。")
      return
    }

    promptPresets = settingsStore.promptPresets()
    settingsView.updatePresetEditor(preset: updated, totalCount: promptPresets.count)
    presentHintAlert(title: "预设已保存", message: "当前预设已更新，后续 AI 处理会按此预设执行。")
  }

  @objc private func handleResetPresetsTap() {
    settingsStore.resetPromptPresetsToDefault()
    promptPresets = settingsStore.promptPresets()
    let preset = settingsStore.selectedPromptPreset()
    selectedPromptPresetID = preset.id
    settingsView.updatePresetEditor(preset: preset, totalCount: promptPresets.count)
    presentHintAlert(title: "已恢复默认", message: "6 个预设已恢复为系统默认内容。")
  }

  @objc private func handleSaveTap() {
    persistCurrentPresetDraft()
    persistFormSettings()
    let authMode = authModeForSelectedIndex()
    let llmEnabled = llmEnabledForSelectedIndex()
    settingsView.updateVisibleSections(authMode: authMode, isLLMEnabled: llmEnabled)

    let message: String
    if !llmEnabled {
      message = "已关闭 AI 编辑。编辑模式将只使用本地规则，不会请求 LLM。"
    } else if authMode == .proxy {
      message = "已保存代理模式配置。编辑/翻译模式会优先调用服务端代理。"
    } else {
      message = "已保存 BYOK 配置。编辑/翻译模式会直接调用你填写的模型接口。"
    }
    let alert = UIAlertController(title: "保存成功", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .default))
    present(alert, animated: true)
  }

  private func persistCurrentPresetDraft() {
    guard !selectedPromptPresetID.isEmpty else { return }
    let name = settingsView.presetNameField.text ?? ""
    let instruction = settingsView.presetInstructionView.text ?? ""
    _ = settingsStore.updatePromptPreset(
      id: selectedPromptPresetID,
      name: name,
      instruction: instruction
    )
    promptPresets = settingsStore.promptPresets()
  }

  private func persistFormSettings() {
    let llmEnabled = llmEnabledForSelectedIndex()
    let provider = currentProviderSelection
    let authMode = authModeForSelectedIndex()
    let proxyEndpoint = settingsView.proxyEndpointField.text ?? ""
    let baseURLInput = (settingsView.byokBaseURLField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let modelInput = (settingsView.modelField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let apiKeyInput = settingsView.apiKeyField.text

    let baseURL = baseURLInput.isEmpty ? provider.defaultBaseURL : baseURLInput
    let model = modelInput.isEmpty ? provider.defaultModel : modelInput

    settingsStore.setLLMEnabled(llmEnabled)
    settingsStore.setAuthMode(authMode)
    settingsStore.setProvider(provider)
    settingsStore.setProxyEndpoint(proxyEndpoint)
    settingsStore.setProxyModelsEndpoint(settingsView.proxyModelsEndpointField.text ?? "")
    settingsStore.setByokBaseURL(baseURL, for: provider)
    settingsStore.setByokModel(model, for: provider)
    settingsStore.setAPIKey(apiKeyInput, for: provider)

    settingsView.byokBaseURLField.text = baseURL
    settingsView.modelField.text = model
    currentProviderSelection = provider
    settingsView.updateProviderSelection(provider: provider)
    settingsView.updateProviderPlaceholders(provider: provider)
  }

  private func presentModelPicker(_ modelIDs: [String]) {
    let picker = VoiceLazyModelPickerViewController(
      title: "选择模型",
      subtitle: "已读取 \(modelIDs.count) 个可用模型。下滑到底会自动加载更多。",
      items: modelIDs
    ) { [weak self] modelID in
      self?.settingsView.modelField.text = modelID
    }
    if let nav = navigationController {
      nav.pushViewController(picker, animated: true)
    } else {
      let nav = UINavigationController(rootViewController: picker)
      present(nav, animated: true)
    }
  }

  private func presentErrorAlert(title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .default))
    present(alert, animated: true)
  }

  private func presentHintAlert(title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .default))
    present(alert, animated: true)
  }
}

final class VoiceLLMSettingsRootView: NibLessView {
  let llmEnabledControl: UISegmentedControl = {
    let control = UISegmentedControl(items: ["关闭", "开启"])
    control.translatesAutoresizingMaskIntoConstraints = false
    control.selectedSegmentIndex = 1
    return control
  }()

  let authModeControl: UISegmentedControl = {
    let control = UISegmentedControl(items: ["服务端代理", "BYOK"])
    control.translatesAutoresizingMaskIntoConstraints = false
    control.selectedSegmentIndex = 0
    return control
  }()

  let providerButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("OpenAI", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
    button.contentHorizontalAlignment = .left
    button.backgroundColor = .secondarySystemBackground
    button.layer.cornerRadius = 10
    button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    return button
  }()

  let proxyEndpointField = VoiceLLMSettingsRootView.makeTextField(
    placeholder: "https://your-server.example.com/api/voice/transform"
  )

  let proxyModelsEndpointField = VoiceLLMSettingsRootView.makeTextField(
    placeholder: "https://your-server.example.com/api/voice/models（可选）"
  )

  let byokBaseURLField = VoiceLLMSettingsRootView.makeTextField(
    placeholder: "https://api.openai.com/v1"
  )

  let modelField: UITextField = {
    let field = VoiceLLMSettingsRootView.makeTextField(placeholder: "gpt-5-nano")
    // 使用一次性验证码语义规避登录表单误判，但保持默认键盘类型。
    field.textContentType = .oneTimeCode
    field.keyboardType = .default
    return field
  }()

  let refreshModelsButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("读取模型列表", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
    button.layer.cornerRadius = 10
    return button
  }()

  let chooseModelButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("从列表选择模型", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    button.backgroundColor = UIColor.systemGray5
    button.layer.cornerRadius = 10
    return button
  }()

  let choosePresetButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("选择预设", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    button.backgroundColor = UIColor.systemGray5
    button.layer.cornerRadius = 10
    return button
  }()

  let presetNameField = VoiceLLMSettingsRootView.makeTextField(
    placeholder: "预设名称"
  )

  let presetInstructionView: UITextView = {
    let view = UITextView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.font = .systemFont(ofSize: 14, weight: .regular)
    view.textColor = .label
    view.backgroundColor = .secondarySystemBackground
    view.layer.cornerRadius = 10
    view.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    return view
  }()

  let savePresetButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("保存当前预设", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
    button.layer.cornerRadius = 10
    return button
  }()

  let resetPresetsButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("恢复默认预设", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    button.backgroundColor = UIColor.systemGray5
    button.layer.cornerRadius = 10
    return button
  }()

  let apiKeyField: UITextField = {
    let field = VoiceLLMSettingsRootView.makeTextField(placeholder: "输入 API Key")
    field.isSecureTextEntry = true
    // 避免被系统当作“密码登录表单”，减少对第三方键盘可用性的干扰。
    field.textContentType = .oneTimeCode
    field.autocorrectionType = .no
    field.autocapitalizationType = .none
    field.spellCheckingType = .no
    return field
  }()

  let saveButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("保存配置", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    button.setTitleColor(.white, for: .normal)
    button.backgroundColor = .systemBlue
    button.layer.cornerRadius = 12
    return button
  }()

  private let descriptionLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.text = "此页面用于配置编辑/翻译模式的 LLM 链路。听写模式仍优先使用 Apple Speech / Whisper。"
    return label
  }()

  private let providerHintLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    return label
  }()

  private let cachedModelHintLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    return label
  }()

  private let presetHintLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    return label
  }()

  private let scrollView: UIScrollView = {
    let view = UIScrollView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let contentStack: UIStackView = {
    let stack = UIStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 14
    return stack
  }()

  private lazy var proxySection = makeSection(
    title: "代理地址",
    description: "代理模式下，客户端只请求你自己的服务端。",
    field: proxyEndpointField
  )

  private lazy var proxyModelsSection = makeSection(
    title: "代理模型列表地址",
    description: "可选。未填写时，默认从代理地址自动推断 /models。",
    field: proxyModelsEndpointField
  )

  private lazy var byokBaseSection = makeSection(
    title: "BYOK Base URL",
    description: "通常填写 OpenAI 兼容接口根路径。",
    field: byokBaseURLField
  )

  private lazy var modelSection: UIView = {
    let modelStack = UIStackView(
      arrangedSubviews: [
        self.modelField,
        self.refreshModelsButton,
        self.chooseModelButton,
        self.cachedModelHintLabel
      ]
    )
    modelStack.axis = .vertical
    modelStack.spacing = 8
    return self.makeSection(
      title: "模型",
      description: "优先建议先读取模型列表再选择；你仍然可以手动输入模型名。",
      content: modelStack
    )
  }()

  private lazy var apiKeySection = makeSection(
    title: "BYOK API Key",
    description: "密钥会保存在本机 Keychain 中。",
    field: apiKeyField
  )

  private lazy var presetSection: UIView = {
    let presetStack = UIStackView(
      arrangedSubviews: [
        self.choosePresetButton,
        self.presetNameField,
        self.presetInstructionView,
        self.savePresetButton,
        self.resetPresetsButton,
        self.presetHintLabel
      ]
    )
    presetStack.axis = .vertical
    presetStack.spacing = 8
    return self.makeSection(
      title: "处理预设",
      description: "每次 AI 处理只使用一个预设。你可以选择并修改系统提供的 6 个预设。",
      content: presetStack
    )
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  private func setupView() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
    updateVisibleSections(authMode: .proxy, isLLMEnabled: true)
    updateProviderSelection(provider: .openAI)
    updateProviderPlaceholders(provider: .openAI)
    updateProviderHint(provider: .openAI)
    updatePresetEditor(preset: VoiceLLMPromptPreset.defaultPresets[0], totalCount: VoiceLLMPromptPreset.defaultPresets.count)
  }

  override func constructViewHierarchy() {
    addSubview(scrollView)
    scrollView.addSubview(contentStack)
    contentStack.addArrangedSubview(descriptionLabel)
    contentStack.addArrangedSubview(makeControlSection(title: "AI 编辑", control: llmEnabledControl))
    contentStack.addArrangedSubview(makeControlSection(title: "认证模式", control: authModeControl))
    contentStack.addArrangedSubview(makeControlSection(title: "Provider", control: providerButton))
    contentStack.addArrangedSubview(providerHintLabel)
    contentStack.addArrangedSubview(proxySection)
    contentStack.addArrangedSubview(proxyModelsSection)
    contentStack.addArrangedSubview(byokBaseSection)
    contentStack.addArrangedSubview(modelSection)
    contentStack.addArrangedSubview(apiKeySection)
    contentStack.addArrangedSubview(presetSection)
    contentStack.addArrangedSubview(saveButton)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
      contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
      contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
      contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),

      presetInstructionView.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
      saveButton.heightAnchor.constraint(equalToConstant: 46)
    ])
  }

  override func setupAppearance() {
    backgroundColor = .systemBackground
  }

  func updateVisibleSections(authMode: VoiceLLMAuthMode, isLLMEnabled: Bool) {
    let isProxy = authMode == .proxy
    proxySection.isHidden = !isLLMEnabled || !isProxy
    proxyModelsSection.isHidden = !isLLMEnabled || !isProxy
    byokBaseSection.isHidden = !isLLMEnabled || isProxy
    modelSection.isHidden = !isLLMEnabled
    apiKeySection.isHidden = !isLLMEnabled || isProxy
    presetSection.isHidden = !isLLMEnabled
  }

  func updateProviderHint(provider: VoiceLLMProvider) {
    let baseURL = provider.defaultBaseURL.isEmpty ? "未预置（请手动填写）" : provider.defaultBaseURL
    providerHintLabel.text = "当前 Provider：\(provider.displayName)。默认 Base URL：\(baseURL)。\(provider.byokCompatibilityHint)"
  }

  func updateProviderSelection(provider: VoiceLLMProvider) {
    providerButton.setTitle("\(provider.displayName)  ▾", for: .normal)
  }

  func updateProviderPlaceholders(provider: VoiceLLMProvider) {
    byokBaseURLField.placeholder = provider.defaultBaseURL.isEmpty ? "https://api.example.com/v1" : provider.defaultBaseURL
    modelField.placeholder = provider.defaultModel.isEmpty ? "输入模型名" : provider.defaultModel
  }

  func updateCachedModelHint(modelCount: Int, updatedAt: TimeInterval?) {
    if modelCount == 0 {
      cachedModelHintLabel.text = "当前尚未缓存模型列表。"
      return
    }
    if let updatedAt {
      let formatter = DateFormatter()
      formatter.dateFormat = "MM-dd HH:mm"
      let timeText = formatter.string(from: Date(timeIntervalSince1970: updatedAt))
      cachedModelHintLabel.text = "已缓存 \(modelCount) 个模型，最近更新：\(timeText)"
    } else {
      cachedModelHintLabel.text = "已缓存 \(modelCount) 个模型。"
    }
  }

  func updatePresetEditor(preset: VoiceLLMPromptPreset, totalCount: Int) {
    choosePresetButton.setTitle("选择预设：\(preset.name)", for: .normal)
    presetNameField.text = preset.name
    presetInstructionView.text = preset.instruction
    presetHintLabel.text = "当前预设 ID：\(preset.id) · 共 \(totalCount) 个预设。"
  }

  private func makeControlSection(title: String, control: UIView) -> UIView {
    let titleLabel = UILabel(frame: .zero)
    titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
    titleLabel.textColor = .secondaryLabel
    titleLabel.text = title
    let stack = UIStackView(arrangedSubviews: [titleLabel, control])
    stack.axis = .vertical
    stack.spacing = 8
    return stack
  }

  private func makeSection(title: String, description: String, field: UITextField) -> UIView {
    makeSection(title: title, description: description, content: field)
  }

  private func makeSection(title: String, description: String, content: UIView) -> UIView {
    let titleLabel = UILabel(frame: .zero)
    titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
    titleLabel.textColor = .secondaryLabel
    titleLabel.text = title

    let descriptionLabel = UILabel(frame: .zero)
    descriptionLabel.font = .systemFont(ofSize: 12, weight: .regular)
    descriptionLabel.textColor = .tertiaryLabel
    descriptionLabel.numberOfLines = 0
    descriptionLabel.text = description

    let stack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, content])
    stack.axis = .vertical
    stack.spacing = 6
    return stack
  }

  private static func makeTextField(placeholder: String) -> UITextField {
    let field = UITextField(frame: .zero)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.placeholder = placeholder
    field.borderStyle = .roundedRect
    field.clearButtonMode = .whileEditing
    // 显式声明普通文本输入，避免系统根据上下文自动套用受限输入策略。
    field.textContentType = .none
    field.keyboardType = .default
    field.autocorrectionType = .no
    field.autocapitalizationType = .none
    field.spellCheckingType = .no
    return field
  }
}
