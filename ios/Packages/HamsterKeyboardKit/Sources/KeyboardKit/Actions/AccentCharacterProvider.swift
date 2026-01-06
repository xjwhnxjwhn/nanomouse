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
      // Pinyin: ā á ǎ à
      // European: â ä å ã æ (removed duplicate à, a)
      return ["ā", "á", "ǎ", "à", "â", "ä", "å", "ã", "æ"]
    case "o":
      // Pinyin: ō ó ǒ ò
      // European: ô ö õ œ (removed duplicate ò, o)
      return ["ō", "ó", "ǒ", "ò", "ô", "ö", "õ", "œ"]
    case "e":
      // Pinyin: ē é ě è
      // European: ê ë (removed duplicate è, e)
      return ["ē", "é", "ě", "è", "ê", "ë"]
    case "i":
      // Pinyin: ī í ǐ ì
      // European: î ï (removed duplicate ì, i)
      return ["ī", "í", "ǐ", "ì", "î", "ï"]
    case "u":
      // Pinyin: ū ú ǔ ù
      // European: û ü (removed duplicate ù, u)
      // Note: ü is also used in Pinyin as v, but kept here for European support on u key
      return ["ū", "ú", "ǔ", "ù", "û", "ü"]
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
