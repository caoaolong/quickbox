import 'dart:typed_data';

// Web 平台 / 非 Windows 平台的占位实现：win32 包仅支持 Windows，
// 在 Web 等不支持 dart:ffi 的平台不能引入，直接返回 null。
Future<Uint8List?> extractIconBytes(String filePath) async => null;
