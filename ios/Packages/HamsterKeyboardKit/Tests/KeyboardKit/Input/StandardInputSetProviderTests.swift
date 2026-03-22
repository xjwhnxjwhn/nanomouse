import XCTest
@testable import HamsterKeyboardKit

final class StandardInputSetProviderTests: XCTestCase {
  func testJapaneseSchemaHasPriorityOverChineseKeyboardType() {
    let keyboardContext = KeyboardContext()
    keyboardContext.keyboardType = .chinese(.lowercased)

    let rimeContext = RimeContext()
    rimeContext.setCurrentSchema(.init(schemaId: "japanese", schemaName: "japanese"))
    rimeContext.applyAsciiMode(false)

    let provider = StandardInputSetProvider(
      keyboardContext: keyboardContext,
      rimeContext: rimeContext
    )

    XCTAssertEqual(provider.alphabeticInputSet.rows[1].chars, "asdfghjklー")
  }
}
