import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Setup BH texture channel after plugins registration
    let registrar = flutterViewController.registrar(forPlugin: "BHTexture")
    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.setupBHTextureChannel(registrar)
    }

    super.awakeFromNib()
  }
}
