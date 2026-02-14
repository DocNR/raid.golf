// Gambit Golf — QR Code Generator
// Uses iOS native CoreImage to generate QR codes. No third-party dependencies.

import CoreImage
import UIKit

enum QRCodeGenerator {

    /// Generate a QR code UIImage from a string.
    /// Returns nil if the input is empty or generation fails.
    static func generate(from string: String, size: CGFloat = 200) -> UIImage? {
        guard !string.isEmpty else { return nil }

        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        // Scale up from the tiny default QR output to the requested size
        let scaleX = size / ciImage.extent.size.width
        let scaleY = size / ciImage.extent.size.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        return UIImage(ciImage: scaledImage)
    }
}
