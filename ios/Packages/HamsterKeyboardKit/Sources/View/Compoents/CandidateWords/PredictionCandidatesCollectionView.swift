//
//  PredictionCandidatesCollectionView.swift
//
//
//  Created by Codex on 2026/05/25.
//

import Combine
import UIKit

final class PredictionCandidatesCollectionView: UICollectionView {
  private var style: CandidateBarStyle
  private let keyboardContext: KeyboardContext
  private let actionHandler: KeyboardActionHandler
  private let rimeContext: RimeContext
  private var subscriptions = Set<AnyCancellable>()
  private var renderedSuggestionSignature: [String] = []

  init(
    style: CandidateBarStyle,
    keyboardContext: KeyboardContext,
    actionHandler: KeyboardActionHandler,
    rimeContext: RimeContext
  ) {
    self.style = style
    self.keyboardContext = keyboardContext
    self.actionHandler = actionHandler
    self.rimeContext = rimeContext

    let layout = AlignedCollectionViewFlowLayout(horizontalAlignment: .justified, verticalAlignment: .center)
    layout.scrollDirection = .horizontal

    super.init(frame: .zero, collectionViewLayout: layout)

    delegate = self
    dataSource = self
    register(CandidateWordCell.self, forCellWithReuseIdentifier: CandidateWordCell.identifier)
    backgroundColor = .clear
    showsHorizontalScrollIndicator = false
    alwaysBounceHorizontal = true
    alwaysBounceVertical = false
    translatesAutoresizingMaskIntoConstraints = false

    combine()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setupStyle(_ style: CandidateBarStyle) {
    self.style = style
    reloadData()
  }

  private func combine() {
    rimeContext.$predictiveSuggestions
      .receive(on: DispatchQueue.main)
      .sink { [weak self] suggestions in
        guard let self else { return }
        let signature = suggestionSignature(suggestions)
        guard signature != renderedSuggestionSignature else { return }

        let shouldResetOffset = signature.count != renderedSuggestionSignature.count
        renderedSuggestionSignature = signature
        UIView.performWithoutAnimation {
          self.collectionViewLayout.invalidateLayout()
          if shouldResetOffset {
            self.setContentOffset(.zero, animated: false)
          }
          self.reloadData()
          self.layoutIfNeeded()
        }
      }
      .store(in: &subscriptions)
  }

  private func displayCandidate(_ candidate: CandidateSuggestion) -> CandidateSuggestion {
    candidate.normalizedForPredictionDisplay()
  }

  private func suggestionSignature(_ suggestions: [CandidateSuggestion]) -> [String] {
    suggestions.map {
      [
        $0.firstRenderableText,
        $0.text,
        $0.subtitle ?? "",
        $0.additionalInfo["predictionSource"] as? String ?? ""
      ].joined(separator: "\u{1F}")
    }
  }
}

extension PredictionCandidatesCollectionView: UICollectionViewDataSource {
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    rimeContext.predictiveSuggestions.count
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CandidateWordCell.identifier, for: indexPath)
    if let cell = cell as? CandidateWordCell, indexPath.item < rimeContext.predictiveSuggestions.count {
      let candidate = displayCandidate(rimeContext.predictiveSuggestions[indexPath.item])
      cell.updateWithCandidateSuggestion(candidate, style: style, showIndex: false, showComment: false)
    }
    return cell
  }
}

extension PredictionCandidatesCollectionView: UICollectionViewDelegate {
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard indexPath.item < rimeContext.predictiveSuggestions.count else { return }
    actionHandler.handle(.press, on: .character(""))
    if let handler = actionHandler as? StandardKeyboardActionHandler,
       let controller = handler.keyboardController as? KeyboardInputViewController
    {
      controller.selectPredictiveSuggestion(index: indexPath.item)
    }
  }
}

extension PredictionCandidatesCollectionView: UICollectionViewDelegateFlowLayout {
  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
    UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
  }

  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
    5
  }

  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
    5
  }

  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    guard indexPath.item < rimeContext.predictiveSuggestions.count else { return .zero }
    let candidate = displayCandidate(rimeContext.predictiveSuggestions[indexPath.item])
    let attributeString = candidate.attributeString(showIndex: false, showComment: false, style: style)
    let maxWidth = max(collectionView.bounds.width - 24, 120)
    let titleSize = UILabel.estimatedAttributeSize(attributeString, targetSize: CGSize(width: maxWidth, height: 0))
    return CGSize(
      width: min(max(titleSize.width + 18, 36), maxWidth),
      height: max(keyboardContext.heightOfPredictionCandidateRow - 8, 24)
    )
  }
}
