// // 一次性工具脚本：为 JsonLayer.png 添加圆角透明遮罩
// //
// // 运行：dart run tool/apply_rounded_mask.dart
// // 脚本运行完毕后可手动删除本文件和 image 依赖。

// import 'dart:io';
// import 'package:image/image.dart' as img;

// void main() {
//   final pngFile = File('images/JsonLayer.png');
//   if (!pngFile.existsSync()) {
//     stderr.writeln('找不到 ${pngFile.path}');
//     exit(1);
//   }

//   final bytes = pngFile.readAsBytesSync();
//   final image = img.decodePng(bytes);
//   if (image == null) {
//     stderr.writeln('PNG 解码失败');
//     exit(1);
//   }

//   final width = image.width;
//   final height = image.height;
//   print('原图尺寸: ${width}x$height');

//   // 圆角半径（约 22% 宽度，匹配图标蓝色边框的圆角弧度）
//   final radius = (width * 0.22).round();
//   print('圆角半径: $radius');

//   var transparentCount = 0;

//   for (int y = 0; y < height; y++) {
//     for (int x = 0; x < width; x++) {
//       if (_isOutsideRoundedRect(x, y, width, height, radius)) {
//         // 角区域设为完全透明
//         image.setPixelRgba(x, y, 0, 0, 0, 0);
//         transparentCount++;
//       }
//     }
//   }

//   print('已将 $transparentCount 个像素设为透明');

//   // 保存 PNG
//   final encodedPng = img.encodePng(image);
//   pngFile.writeAsBytesSync(encodedPng);
//   print('已更新 ${pngFile.path}');

//   // 重新生成 ICO
//   _regenerateIco(encodedPng, width, height);
// }

// /// 判断像素是否在圆角矩形外部（需要设为透明）
// bool _isOutsideRoundedRect(int x, int y, int w, int h, int r) {
//   // 左上圆角
//   if (x < r && y < r) {
//     final dx = r - x;
//     final dy = r - y;
//     return (dx * dx + dy * dy) > r * r;
//   }
//   // 右上圆角
//   if (x >= w - r && y < r) {
//     final dx = x - (w - r - 1);
//     final dy = r - y;
//     return (dx * dx + dy * dy) > r * r;
//   }
//   // 左下圆角
//   if (x < r && y >= h - r) {
//     final dx = r - x;
//     final dy = y - (h - r - 1);
//     return (dx * dx + dy * dy) > r * r;
//   }
//   // 右下圆角
//   if (x >= w - r && y >= h - r) {
//     final dx = x - (w - r - 1);
//     final dy = y - (h - r - 1);
//     return (dx * dx + dy * dy) > r * r;
//   }
//   return false;
// }

// /// 基于处理后的 PNG 重新生成 ICO 文件
// void _regenerateIco(List<int> pngBytes, int width, int height) {
//   int w = width;
//   int h = height;
//   if (w >= 256) w = 0;
//   if (h >= 256) h = 0;

//   final out = BytesBuilder();

//   // ICONDIR (6B)
//   out.add(_uint16LE(0)); // reserved
//   out.add(_uint16LE(1)); // type = icon
//   out.add(_uint16LE(1)); // count = 1

//   // ICONDIRENTRY (16B)
//   out.add([w & 0xFF]);
//   out.add([h & 0xFF]);
//   out.add([0]); // color count (0 = truecolor)
//   out.add([0]); // reserved
//   out.add(_uint16LE(1)); // planes
//   out.add(_uint16LE(32)); // bit count
//   out.add(_uint32LE(pngBytes.length)); // bytes in res
//   out.add(_uint32LE(22)); // offset = 6 + 16

//   // PNG data
//   out.add(pngBytes);

//   final outFile = File('windows/runner/resources/app_icon.ico');
//   outFile.parent.createSync(recursive: true);
//   outFile.writeAsBytesSync(out.toBytes());
//   print('已生成 ${outFile.path}');
// }

// List<int> _uint16LE(int v) => [v & 0xFF, (v >> 8) & 0xFF];
// List<int> _uint32LE(int v) =>
//     [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];