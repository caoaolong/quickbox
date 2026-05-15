// 根据当前平台条件导出 extractIconBytes：
//   - 默认（Web 平台，dart.library.io 不可用）：导出 stub，不引入 package:win32。
//   - 原生平台（dart.library.io 可用，包含 Windows/macOS/Linux/Android/iOS）：
//     导出 io 实现，内部会在运行时根据 Platform.isWindows 决定是否真正调用 win32 API。
//
// 这样可以避免 Web 构建时 win32 包里的 FFI `external` 关键字
// 报 "Only JS interop members may be 'external'" 的错误。
export 'icon_extractor_stub.dart'
    if (dart.library.io) 'icon_extractor_io.dart';
