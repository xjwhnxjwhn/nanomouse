import Foundation
import Combine

@MainActor
final class UpdaterViewModel: ObservableObject {
    let canCheckForUpdates = false

    func checkForUpdates() {
        // Mac App Store 版本由 App Store 负责更新，这里保留空实现以避免额外删除文件。
    }
}
