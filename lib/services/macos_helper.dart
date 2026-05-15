import 'dart:io';

import 'package:flutter/services.dart';

/// macOS 平台原生 helper。
///
/// 该项目的 macOS 端使用 LSUIElement=true（菜单栏应用），主窗口配合
/// alwaysOnTop（.floating level）默认无法稳定成为 key window，导致
/// 设置页里的 HotKeyRecorder 等依赖 HardwareKeyboard 的组件
/// 收不到按键事件。
///
/// 通过原生 method channel 调用 `NSApp.activate(ignoringOtherApps: true)`
/// 强制激活进程并把主窗口设为 key window。
class MacosHelper {
  MacosHelper._();

  static const MethodChannel _channel =
      MethodChannel('quickbox/macos_helper');

  /// 仅在 macOS 平台执行；其他平台直接返回，调用方无需自己加平台判断。
  static Future<void> activateApp() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>('activateApp');
    } on PlatformException {
      // 忽略：原生侧未注册成功时不影响主流程。
    } on MissingPluginException {
      // 忽略：旧版本 host 未注册 channel。
    }
  }
}
