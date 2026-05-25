import XCTest
@testable import HamsterKeyboardKit

final class AccentCharacterProviderTests: XCTestCase {
  func testBuildAccentMapLoadsSingleLetterSymbolsVEntries() {
    let yaml = """
    symbols:
      'va': [ā, á, ǎ, à]
      'vh': [ĥ, ȟ, ḣ, ḧ]
      'vs': [Vs., 🆚, ś, ŝ]
      'vv': [ü, ǖ, ǘ, ǚ, ǜ, ṽ]
      'vpy': [ā, á]
    """

    let accents = AccentCharacterProvider.buildAccentMap(symbolsVYaml: yaml)

    XCTAssertEqual(accents["a"], ["ā", "á", "ǎ", "à"])
    XCTAssertEqual(accents["h"], ["ĥ", "ȟ", "ḣ", "ḧ"])
    XCTAssertEqual(accents["s"], ["Vs.", "🆚", "ś", "ŝ"])
    XCTAssertEqual(accents["v"], ["ü", "ǖ", "ǘ", "ǚ", "ǜ", "ṽ"])
    XCTAssertNil(accents["py"])
  }

  func testBuildAccentMapKeepsFallbackPunctuation() {
    let accents = AccentCharacterProvider.buildAccentMap(symbolsVYaml: nil)

    XCTAssertTrue(accents["h"]?.contains("ĥ") == true)
    XCTAssertTrue(accents["h"]?.contains("ħ") == true)
    XCTAssertTrue(accents["v"]?.contains("ṽ") == true)
    XCTAssertTrue((accents["r"]?.count ?? 0) >= 20)
    XCTAssertEqual(accents["?"], ["¿"])
    XCTAssertEqual(accents["/"], ["\\"])
    XCTAssertEqual(accents["%"], ["‰"])
  }

  func testSymbolAccentOptionsMarkAsciiHalfWidthOnly() {
    let hashOptions = AccentCharacterProvider.accentOptions(for: "#") ?? []

    XCTAssertEqual(hashOptions.first(where: { $0.character == "#" })?.widthLabel, "半")
    XCTAssertEqual(hashOptions.first(where: { $0.character == "＃" })?.widthLabel, "全")

    let fullwidthHashOptions = AccentCharacterProvider.accentOptions(for: "＃") ?? []

    XCTAssertEqual(fullwidthHashOptions.first(where: { $0.character == "#" })?.widthLabel, "半")
    XCTAssertEqual(fullwidthHashOptions.first(where: { $0.character == "＃" })?.widthLabel, "全")

    let yenOptions = AccentCharacterProvider.accentOptions(for: "￥") ?? []

    XCTAssertNil(yenOptions.first(where: { $0.character == "¥" })?.widthLabel)
    XCTAssertEqual(yenOptions.first(where: { $0.character == "￥" })?.widthLabel, "全")
  }
}
