import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // 与 Dart 端通信的 method channel，名称需与 lib/services/macos_helper.dart 保持一致
  private let helperChannelName = "quickbox/macos_helper"

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 纯菜单栏应用：主窗口可隐藏，不应在「最后一个窗口关闭」时退出进程。
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    registerMacosHelperChannel()
  }

  /// 注册 macOS 原生 helper method channel：
  /// LSUIElement=true 的菜单栏应用，配合 alwaysOnTop（.floating level）窗口，
  /// 默认无法稳定成为 key window，导致设置页里的 HotKeyRecorder
  /// （依赖 HardwareKeyboard）收不到按键事件。
  /// 我们提供一个 `activateApp` 方法供 Dart 端在需要键盘焦点时调用，
  /// 强制激活进程并把主窗口设为 key window。
  private func registerMacosHelperChannel() {
    guard let controller = NSApp.windows
      .compactMap({ $0.contentViewController as? FlutterViewController })
      .first
    else {
      return
    }

    let channel = FlutterMethodChannel(
      name: helperChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "activateApp":
        AppDelegate.forceActivate()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 强制激活应用并把主窗口设为 key window，确保 HardwareKeyboard 能收到按键事件。
  static func forceActivate() {
    // ignoringOtherApps: true ＝ 即使其它应用是 frontmost，也强制激活本进程。
    // 对 LSUIElement = true 的菜单栏应用来说，这是让窗口成为 key window 的关键。
    NSApp.activate(ignoringOtherApps: true)

    if let window = NSApp.windows.first(where: { $0.contentViewController is FlutterViewController }) {
      window.makeKeyAndOrderFront(nil)
    }
  }
}
