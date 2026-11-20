import Cocoa
import FlutterMacOS
import macos_window_utils

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let windowFrame = self.frame
    let controller = MacOSWindowUtilsViewController()
    self.contentViewController = controller
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 860, height: 560)
    self.isReleasedWhenClosed = false

    MainFlutterWindowManipulator.start(mainFlutterWindow: self)
    RegisterGeneratedPlugins(registry: controller.flutterViewController)
    StatusBarController.shared.attach(
      messenger: controller.flutterViewController.engine.binaryMessenger, window: self)

    super.awakeFromNib()
  }
}
