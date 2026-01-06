//
//  AccentCharacterProvider.swift
//
//
//  Created by Codex on 2026/01/07.
//

import Foundation

public struct AccentCharacterProvider {
  /// 获取按键对应的变音符号列表
  public static func accents(for key: String) -> [String]? {
    switch key.lowercased() {
    case "a":
      return ["ā", "á", "ǎ", "à", "a", "â", "ä", "à", "å", "ã", "æ"]
    case "o":
      return ["ō", "ó", "ǒ", "ò", "o", "ô", "ö", "ò", "õ", "œ"]
    case "e":
      return ["ē", "é", "ě", "è", "e", "ê", "ë", "è"]
    case "i":
      return ["ī", "í", "ǐ", "ì", "i", "î", "ï", "ì"]
    case "u":
      return ["ū", "ú", "ǔ", "ù", "u", "û", "ü", "ù"]
    case "v":
      // v 在拼音输入中通常映射为 ü
      return ["ü", "ǖ", "ǘ", "ǚ", "ǜ"]
    case "n":
      return ["ñ", "ń", "ň"]
    case "c":
      return ["ç", "ć", "č"]
    case "s":
      return ["ß", "ś", "š"]
    case "z":
      return ["ź", "ž", "ż"]
    case "y":
      return ["ý", "ÿ"]
    case "$":
      return ["¥", "€", "£", "¢", "₽", "₩"]
    case "\"":
      return ["“", "”", "„", "«", "»"]
    case "'":
      return ["‘", "’", "`"]
    case ".":
      return ["…"]
    case "?":
      return ["¿"]
    case "!":
      return ["¡"]
    case "-":
      return ["–", "—", "•"]
    case "/":
      return ["\\"]
    case "%":
      return ["‰"]
    default:
      return nil
    }
  }
}
