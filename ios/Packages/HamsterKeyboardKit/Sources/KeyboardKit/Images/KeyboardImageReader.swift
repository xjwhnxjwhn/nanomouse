//
//  KeyboardImageReader.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2020-03-11.
//  Copyright © 2020-2023 Daniel Saidi. All rights reserved.
//

import UIKit

/**
 This protocol can be implemented by any type that should be
 able to access keyboard-specific images.

 该协议可以由任何能够访问键盘特定图像的类型来实现。

 This protocol is implemented by `UIImage`. This means that it
 is possible to use e.g. `Image.keyboardSettings` to get the
 standard keyboard settings icon.

 该协议由 `UIImage` 实现。这意味着可以使用 `UIImage.keyboardSettings` 来获取标准键盘设置图标。
 */
public protocol KeyboardImageReader {}

public class HamsterUIImage: KeyboardImageReader {
  public static let shared = HamsterUIImage()
  private init() {}
  public lazy var keyboard: UIImage = requiredImage(UIImage(systemName: "keyboard"), name: "keyboard")
  public lazy var keyboardBackspace: UIImage = requiredImage(UIImage(systemName: "delete.left"), name: "delete.left")
  public lazy var keyboardBackspaceRtl: UIImage = requiredImage(UIImage(systemName: "delete.right"), name: "delete.right")
  public lazy var keyboardCommand: UIImage = requiredImage(UIImage(systemName: "command"), name: "command")
  public lazy var keyboardControl: UIImage = requiredImage(UIImage(systemName: "control"), name: "control")
  public lazy var keyboardDictation: UIImage = requiredImage(UIImage(systemName: "mic"), name: "mic")
  public lazy var keyboardDismiss: UIImage = requiredImage(UIImage(systemName: "keyboard.chevron.compact.down"), name: "keyboard.chevron.compact.down")
  public lazy var keyboardEmail: UIImage = requiredImage(UIImage(systemName: "envelope"), name: "envelope")
  public lazy var keyboardEmoji: UIImage = requiredImage(UIImage.asset("keyboardEmoji"), name: "keyboardEmoji")
  public lazy var keyboardStateChinese: UIImage = requiredImage(UIImage.asset("chineseState"), name: "chineseState")
  public lazy var keyboardStateEnglish: UIImage = requiredImage(UIImage.asset("englishState"), name: "englishState")
  public lazy var keyboardEmojiSymbol: UIImage = requiredImage(UIImage(systemName: "face.smiling"), name: "face.smiling")
  public lazy var keyboardGlobe: UIImage = requiredImage(UIImage(systemName: "globe"), name: "globe")
  public lazy var keyboardImages: UIImage = requiredImage(UIImage(systemName: "photo"), name: "photo")
  public lazy var keyboardLeft: UIImage = requiredImage(UIImage(systemName: "arrow.left"), name: "arrow.left")
  public lazy var keyboardNewline: UIImage = requiredImage(UIImage(systemName: "arrow.turn.down.left"), name: "arrow.turn.down.left")
  public lazy var keyboardNewlineRtl: UIImage = requiredImage(UIImage(systemName: "arrow.turn.down.right"), name: "arrow.turn.down.right")
  public lazy var keyboardOption: UIImage = requiredImage(UIImage(systemName: "option"), name: "option")
  public lazy var keyboardRedo: UIImage = requiredImage(UIImage(systemName: "arrow.uturn.right"), name: "arrow.uturn.right")
  public lazy var keyboardRight: UIImage = requiredImage(UIImage(systemName: "arrow.right"), name: "arrow.right")
  public lazy var keyboardSettings: UIImage = requiredImage(UIImage(systemName: "gearshape"), name: "gearshape")
  public lazy var keyboardShiftCapslocked: UIImage = requiredImage(UIImage(systemName: "capslock.fill"), name: "capslock.fill")
  public lazy var keyboardShiftLowercased: UIImage = requiredImage(UIImage(systemName: "shift"), name: "shift")
  public lazy var keyboardShiftUppercased: UIImage = requiredImage(UIImage(systemName: "shift.fill"), name: "shift.fill")
  public lazy var keyboardTab: UIImage = requiredImage(UIImage(systemName: "arrow.right.to.line"), name: "arrow.right.to.line")
  public lazy var keyboardUndo: UIImage = requiredImage(UIImage(systemName: "arrow.uturn.left"), name: "arrow.uturn.left")
  public lazy var keyboardZeroWidthSpace: UIImage = requiredImage(UIImage(systemName: "circle.dotted"), name: "circle.dotted")

  public func keyboardNewline(for locale: Locale) -> UIImage {
    locale.isLeftToRight ? self.keyboardNewline : self.keyboardNewlineRtl
  }

  private func requiredImage(_ image: UIImage?, name: String) -> UIImage {
    guard let image else {
      assertionFailure("Missing image asset: \(name)")
      return UIImage()
    }
    return image
  }
}

extension UIImage {
  static func asset(_ name: String) -> UIImage? {
    UIImage(named: name, in: .hamsterKeyboard, with: .none)
  }

  static func symbol(_ name: String) -> UIImage? {
    UIImage(systemName: name)
  }
}
