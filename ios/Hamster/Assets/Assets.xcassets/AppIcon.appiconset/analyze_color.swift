import AppKit

func getAverageColor(imagePath: String) {
    guard let image = NSImage(contentsOfFile: imagePath) else {
        print("Failed to load image")
        return
    }
    
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        print("Failed to get bitmap representation")
        return
    }
    
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    
    // Sample the center pixel
    let x = Int(bitmap.size.width / 2)
    let y = Int(bitmap.size.height / 2)
    
    guard let color = bitmap.colorAt(x: x, y: y) else {
        print("Failed to get color at center")
        return
    }
    
    // Check component values
    color.getRed(&r, green: &g, blue: &b, alpha: nil)
    
    print("Center Pixel Color (RGB): \(r), \(g), \(b)")
    
    if abs(r - g) < 0.1 && abs(g - b) < 0.1 {
         print("Result: It looks GRAY (R, G, B values are very close).")
    } else {
         print("Result: It does NOT look purely gray.")
    }
}

let path = "Icon-App-iTunes.png"
getAverageColor(imagePath: path)
