import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Open at a comfortable desktop size, centred, and never smaller than
    // the layout with the side navigation needs.
    self.title = "BuildPro"
    self.setContentSize(NSSize(width: 1360, height: 860))
    self.contentMinSize = NSSize(width: 960, height: 640)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
