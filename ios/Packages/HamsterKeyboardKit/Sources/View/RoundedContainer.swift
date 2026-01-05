import UIKit

class RoundedContainer: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        self.layer.cornerRadius = self.bounds.height * 0.2237
        self.layer.cornerCurve = .continuous
        self.layer.masksToBounds = true
        self.clipsToBounds = true
    }
}
