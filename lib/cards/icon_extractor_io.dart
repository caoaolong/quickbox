import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

final _iconCache = <String, Uint8List?>{};

Future<Uint8List?> extractIconBytes(String filePath) async {
  // win32 API 仅在 Windows 平台可用，其他原生平台（macOS/Linux/Android/iOS）
  // 直接返回 null，避免运行时 FFI 调用失败。
  if (!Platform.isWindows) return null;

  final cached = _iconCache[filePath];
  if (cached != null) return cached;
  if (_iconCache.containsKey(filePath)) return null;

  final raw = _extractIconSync(filePath);
  if (raw == null) {
    _iconCache[filePath] = null;
    return null;
  }

  final png = await _rawToPng(raw, 32, 32);
  _iconCache[filePath] = png;
  return png;
}

Future<Uint8List?> _rawToPng(Uint8List rgba, int width, int height) async {
  final completer = Completer<Uint8List?>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    (image) async {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      completer.complete(byteData?.buffer.asUint8List());
    },
  );
  return completer.future;
}

Uint8List? _extractIconSync(String filePath) {
  final psfi = calloc<SHFILEINFO>();
  try {
    final result = SHGetFileInfo(
      filePath.toNativeUtf16(),
      0,
      psfi,
      sizeOf<SHFILEINFO>(),
      SHGFI_ICON | SHGFI_LARGEICON,
    );
    if (result == 0) return null;

    final hIcon = psfi.ref.hIcon;
    if (hIcon == 0) return null;

    final pixels = _iconToPixels(hIcon);
    DestroyIcon(hIcon);
    return pixels;
  } finally {
    free(psfi);
  }
}

Uint8List? _iconToPixels(int hIcon) {
  const size = 32;
  final hdcScreen = GetDC(0);
  if (hdcScreen == 0) return null;

  final hdcMem = CreateCompatibleDC(hdcScreen);
  final hBitmap = CreateCompatibleBitmap(hdcScreen, size, size);
  if (hBitmap == 0) {
    DeleteDC(hdcMem);
    ReleaseDC(0, hdcScreen);
    return null;
  }

  final oldBitmap = SelectObject(hdcMem, hBitmap);

  final rect = calloc<RECT>();
  rect.ref.left = 0;
  rect.ref.top = 0;
  rect.ref.right = size;
  rect.ref.bottom = size;
  FillRect(hdcMem, rect, GetStockObject(BLACK_BRUSH));
  free(rect);

  DrawIcon(hdcMem, 0, 0, hIcon);

  final bmi = calloc<BITMAPINFO>();
  bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
  bmi.ref.bmiHeader.biWidth = size;
  bmi.ref.bmiHeader.biHeight = -size;
  bmi.ref.bmiHeader.biPlanes = 1;
  bmi.ref.bmiHeader.biBitCount = 32;
  bmi.ref.bmiHeader.biCompression = BI_RGB;

  final pixelData = calloc<Uint32>(size * size);
  final bits = GetDIBits(
    hdcMem,
    hBitmap,
    0,
    size,
    pixelData,
    bmi,
    DIB_RGB_COLORS,
  );

  Uint8List? result;
  if (bits != 0) {
    final temp = Uint8List(size * size * 4);
    for (int i = 0; i < size * size; i++) {
      final bgra = pixelData[i];
      temp[i * 4] = (bgra >> 16) & 0xFF;
      temp[i * 4 + 1] = (bgra >> 8) & 0xFF;
      temp[i * 4 + 2] = bgra & 0xFF;
      temp[i * 4 + 3] = (bgra >> 24) & 0xFF;
    }
    result = temp;
  }

  free(pixelData);
  free(bmi);
  SelectObject(hdcMem, oldBitmap);
  DeleteObject(hBitmap);
  DeleteDC(hdcMem);
  ReleaseDC(0, hdcScreen);

  return result;
}
