import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// 强制允许窗口成为 key window。
  /// 当 alwaysOnTop=true 时 window_manager 会把 level 设为 .floating，
  /// 配合 LSUIElement=true 的菜单栏应用形态，
  /// 部分场景下窗口默认不能成为 key window，从而无法接收键盘事件，
  /// 表现为设置页 HotKeyRecorder 无法录制快捷键。
  override var canBecomeKey: Bool {
    return true
  }

  override var canBecomeMain: Bool {
    return true
  }
}
