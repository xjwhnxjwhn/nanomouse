//
//  VoiceDiaryViewController.swift
//
//
//  Created by OpenAI on 2026/5/14.
//

import FSCalendar
import HamsterKit
import HamsterUIKit
import UIKit

final class VoiceDiaryViewController: NibLessViewController {
  private enum DisplayMode: Int {
    case calendar
    case files
  }

  private let store = KeyboardDiaryStore.shared
  private var selectedDate = Date()
  private var segments: [KeyboardDiarySegment] = []
  private var selectedSegments: [KeyboardDiarySegment] = []
  private var buckets: [(day: Date, segments: [KeyboardDiarySegment])] = []
  private var mode: DisplayMode = .calendar
  private var tableTopConstraint: NSLayoutConstraint?

  private let segmentedControl: UISegmentedControl = {
    let control = UISegmentedControl(items: ["日历", "文件"])
    control.translatesAutoresizingMaskIntoConstraints = false
    control.selectedSegmentIndex = 0
    return control
  }()

  private let calendarView: FSCalendar = {
    let calendar = FSCalendar(frame: .zero)
    calendar.translatesAutoresizingMaskIntoConstraints = false
    calendar.scope = .month
    calendar.appearance.headerTitleFont = .systemFont(ofSize: 17, weight: .semibold)
    calendar.appearance.weekdayFont = .systemFont(ofSize: 12, weight: .medium)
    calendar.appearance.titleTodayColor = .white
    calendar.appearance.todayColor = .systemBlue
    calendar.appearance.selectionColor = .systemRed
    calendar.appearance.eventDefaultColor = .systemRed
    calendar.appearance.eventSelectionColor = .systemRed
    return calendar
  }()

  private let tableView: UITableView = {
    let table = UITableView(frame: .zero, style: .insetGrouped)
    table.translatesAutoresizingMaskIntoConstraints = false
    table.rowHeight = UITableView.automaticDimension
    table.estimatedRowHeight = 76
    return table
  }()

  override func loadView() {
    let root = UIView(frame: .zero)
    root.backgroundColor = .systemBackground
    root.addSubview(segmentedControl)
    root.addSubview(calendarView)
    root.addSubview(tableView)
    let tableTopConstraint = tableView.topAnchor.constraint(equalTo: calendarView.bottomAnchor, constant: 8)
    self.tableTopConstraint = tableTopConstraint
    NSLayoutConstraint.activate([
      segmentedControl.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 12),
      segmentedControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
      segmentedControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

      calendarView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
      calendarView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
      calendarView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
      calendarView.heightAnchor.constraint(equalToConstant: 310),

      tableTopConstraint,
      tableView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
    ])
    view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "日记"
    navigationItem.title = "日记"
    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareToday)),
      UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(confirmClearAll))
    ]
    segmentedControl.addTarget(self, action: #selector(handleModeChanged), for: .valueChanged)
    calendarView.dataSource = self
    calendarView.delegate = self
    tableView.dataSource = self
    tableView.delegate = self
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DiarySegmentCell")
    reloadData()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    reloadData()
  }

  private func reloadData() {
    segments = store.loadSegments()
    selectedSegments = segments.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: selectedDate) }
    buckets = store.dayBuckets()
    calendarView.reloadData()
    tableView.reloadData()
    updateEmptyBackground()
  }

  private func updateEmptyBackground() {
    let isEmpty: Bool
    switch mode {
    case .calendar:
      isEmpty = selectedSegments.isEmpty
    case .files:
      isEmpty = buckets.isEmpty
    }
    guard isEmpty else {
      tableView.backgroundView = nil
      return
    }
    let label = UILabel()
    label.text = mode == .calendar ? "这一天还没有日记素材" : "还没有记录的日记素材"
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.font = .systemFont(ofSize: 15)
    tableView.backgroundView = label
  }

  @objc private func handleModeChanged() {
    mode = DisplayMode(rawValue: segmentedControl.selectedSegmentIndex) ?? .calendar
    calendarView.isHidden = mode == .files
    if mode == .files {
      tableViewTopToSegmented()
    } else {
      tableViewTopToCalendar()
    }
    tableView.reloadData()
    updateEmptyBackground()
  }

  private func tableViewTopToSegmented() {
    tableTopConstraint?.isActive = false
    let constraint = tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12)
    constraint.isActive = true
    tableTopConstraint = constraint
    view.layoutIfNeeded()
  }

  private func tableViewTopToCalendar() {
    tableTopConstraint?.isActive = false
    let constraint = tableView.topAnchor.constraint(equalTo: calendarView.bottomAnchor, constant: 8)
    constraint.isActive = true
    tableTopConstraint = constraint
    view.layoutIfNeeded()
  }

  private func editDay(_ bucket: (day: Date, segments: [KeyboardDiarySegment])) {
    let editor = DiaryDayEditorViewController(
      title: Self.dayFormatter.string(from: bucket.day),
      text: makeDailyFileText(segments: bucket.segments)
    ) { [weak self] text in
      self?.replaceDay(bucket, with: text)
    }
    let navigationController = UINavigationController(rootViewController: editor)
    navigationController.modalPresentationStyle = .pageSheet
    if let sheet = navigationController.sheetPresentationController {
      sheet.detents = [.large()]
      sheet.prefersGrabberVisible = true
    }
    present(navigationController, animated: true)
  }

  private func deleteDay(_ bucket: (day: Date, segments: [KeyboardDiarySegment])) {
    bucket.segments.forEach { segment in
      try? store.markDeleted(id: segment.id)
    }
    reloadData()
  }

  private func replaceDay(_ bucket: (day: Date, segments: [KeyboardDiarySegment]), with text: String) {
    bucket.segments.forEach { segment in
      try? store.markDeleted(id: segment.id)
    }
    let normalizedText = normalizeDiaryFileText(text)
    guard !normalizedText.isEmpty else {
      reloadData()
      return
    }
    let createdAt = bucket.segments.map(\.createdAt).max() ?? bucket.day
    let segment = KeyboardDiarySegment(
      createdAt: createdAt,
      text: normalizedText,
      redactedText: normalizedText,
      trigger: .manualSave,
      confidence: .high,
      sensitiveLevel: .none,
      source: "mainApp",
      metadata: ["diaryFileDay": Self.dayFormatter.string(from: bucket.day)]
    )
    try? store.append(segment)
    reloadData()
  }

  private func normalizeDiaryFileText(_ text: String) -> String {
    let normalizedLines = text
      .replacingOccurrences(of: "\u{00A0}", with: " ")
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedLines.count > 10000 else { return normalizedLines }
    return String(normalizedLines.suffix(10000)).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func share(_ text: String, sourceView: UIView?) {
    let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    if let popover = controller.popoverPresentationController {
      popover.sourceView = sourceView ?? view
      popover.sourceRect = sourceView?.bounds ?? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
    }
    present(controller, animated: true)
  }

  @objc private func shareToday() {
    let todaySegments = selectedSegments
    guard !todaySegments.isEmpty else { return }
    let body = makeMarkdown(day: selectedDate, segments: todaySegments)
    share(body, sourceView: view)
  }

  @objc private func confirmClearAll() {
    let alert = UIAlertController(title: "清空所有日记素材？", message: "该操作会删除本机 App Group 中保存的日记素材。", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
      try? self?.store.clearAll()
      self?.reloadData()
    })
    present(alert, animated: true)
  }

  private func makeMarkdown(day: Date, segments: [KeyboardDiarySegment]) -> String {
    let title = Self.dayFormatter.string(from: day)
    let lines = segments.sorted { $0.createdAt < $1.createdAt }.map { segment in
      "- \(Self.timeFormatter.string(from: segment.createdAt)) \(segment.displayText)"
    }
    return "# \(title)\n\n" + lines.joined(separator: "\n")
  }

  private func makeDailyFileText(segments: [KeyboardDiarySegment]) -> String {
    segments
      .sorted { $0.createdAt < $1.createdAt }
      .map { segment in
        "\(Self.timeFormatter.string(from: segment.createdAt))  \(segment.displayText)"
      }
      .joined(separator: "\n\n")
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()
}

private final class DiaryDayEditorViewController: UIViewController {
  private let initialText: String
  private let onSave: (String) -> Void
  private let textView = UITextView(frame: .zero)

  init(title: String, text: String, onSave: @escaping (String) -> Void) {
    self.initialText = text
    self.onSave = onSave
    super.init(nibName: nil, bundle: nil)
    self.title = title
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
    navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))

    textView.translatesAutoresizingMaskIntoConstraints = false
    textView.text = initialText
    textView.font = .preferredFont(forTextStyle: .body)
    textView.adjustsFontForContentSizeCategory = true
    textView.backgroundColor = .secondarySystemBackground
    textView.layer.cornerRadius = 14
    textView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
    view.addSubview(textView)

    NSLayoutConstraint.activate([
      textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16)
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    textView.becomeFirstResponder()
  }

  @objc private func cancel() {
    dismiss(animated: true)
  }

  @objc private func save() {
    onSave(textView.text)
    dismiss(animated: true)
  }
}

extension VoiceDiaryViewController: FSCalendarDataSource, FSCalendarDelegate {
  func calendar(_ calendar: FSCalendar, numberOfEventsFor date: Date) -> Int {
    min(store.segments(on: date).count, 3)
  }

  func calendar(_ calendar: FSCalendar, didSelect date: Date, at monthPosition: FSCalendarMonthPosition) {
    selectedDate = date
    selectedSegments = segments.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: date) }
    tableView.reloadData()
    updateEmptyBackground()
  }
}

extension VoiceDiaryViewController: UITableViewDataSource, UITableViewDelegate {
  func numberOfSections(in tableView: UITableView) -> Int {
    switch mode {
    case .calendar:
      return 1
    case .files:
      return 1
    }
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch mode {
    case .calendar:
      return selectedSegments.isEmpty ? 0 : 1
    case .files:
      return buckets.count
    }
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    switch mode {
    case .calendar:
      return Self.dayFormatter.string(from: selectedDate)
    case .files:
      return "日记文件"
    }
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "DiarySegmentCell", for: indexPath)
    var configuration = cell.defaultContentConfiguration()
    switch mode {
    case .calendar:
      configuration.text = makeDailyFileText(segments: selectedSegments)
      configuration.image = UIImage(systemName: "doc.text")
      configuration.textProperties.numberOfLines = 0
      configuration.textProperties.font = .systemFont(ofSize: 15, weight: .regular)
      cell.contentConfiguration = configuration
      cell.accessoryType = .none
    case .files:
      let bucket = buckets[indexPath.row]
      configuration.text = "\(Self.dayFormatter.string(from: bucket.day)) · \(bucket.segments.count) 条"
      configuration.secondaryText = makeDailyFileText(segments: bucket.segments)
      configuration.image = UIImage(systemName: "doc.text")
      configuration.textProperties.numberOfLines = 1
      configuration.secondaryTextProperties.numberOfLines = 3
      configuration.secondaryTextProperties.color = .secondaryLabel
      cell.contentConfiguration = configuration
      cell.accessoryType = .disclosureIndicator
    }
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard mode == .files else { return }
    editDay(buckets[indexPath.row])
  }

  func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
    if mode == .calendar {
      let text = makeDailyFileText(segments: selectedSegments)
      return UIContextMenuConfiguration(identifier: "selected-day" as NSString, previewProvider: nil) { [weak self] _ in
        guard let self else { return UIMenu() }
        let copy = UIAction(title: "复制整天", image: UIImage(systemName: "doc.on.doc")) { _ in
          UIPasteboard.general.string = text
        }
        let share = UIAction(title: "分享整天", image: UIImage(systemName: "square.and.arrow.up")) { _ in
          self.share(text, sourceView: tableView.cellForRow(at: indexPath))
        }
        return UIMenu(children: [copy, share])
      }
    }
    let bucket = buckets[indexPath.row]
    let text = makeDailyFileText(segments: bucket.segments)
    return UIContextMenuConfiguration(identifier: Self.dayFormatter.string(from: bucket.day) as NSString, previewProvider: nil) { [weak self] _ in
      guard let self else { return UIMenu() }
      let copy = UIAction(title: "复制整天", image: UIImage(systemName: "doc.on.doc")) { _ in
        UIPasteboard.general.string = text
      }
      let edit = UIAction(title: "编辑文件", image: UIImage(systemName: "pencil")) { _ in
        self.editDay(bucket)
      }
      let share = UIAction(title: "分享整天", image: UIImage(systemName: "square.and.arrow.up")) { _ in
        self.share(text, sourceView: tableView.cellForRow(at: indexPath))
      }
      let delete = UIAction(title: "删除文件", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
        self.deleteDay(bucket)
      }
      return UIMenu(children: [copy, edit, share, delete])
    }
  }
}
