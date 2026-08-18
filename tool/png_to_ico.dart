// 一次性工具脚本：将 images/JsonLayer.png 封装为 windows/runner/resources/app_icon.ico
//
// ICO 格式自 Windows Vista 起支持直接内嵌 PNG，结构如下：
//   6B 头 (reserved=0, type=1, count=1)
//   16B 目录项 (尺寸/格式/偏移/长度)
//   N  B PNG 数据
// 字段均为小端序。
//
// 运行：dart tool/png_to_ico.dart
// 脚本运行完毕后可手动删除本文件。

import 'dart:io';
import 'dart:typed_data';

Future<void> main() async {
  final pngFile = File('images/JsonLayer.png');
  if (!await pngFile.exists()) {
    stderr.writeln('找不到 ${pngFile.path}');
    exit(1);
  }

  final pngBytes = await pngFile.readAsBytes();

  // 解析 PNG 宽高（IHDR 在 PNG 第 16~24 字节，大端序）
  int width = 256;
  int height = 256;
  if (pngBytes.length >= 24 &&
      pngBytes[1] == 0x50 && pngBytes[2] == 0x4E && pngBytes[3] == 0x47) {
    final byteData = ByteData.sublistView(pngBytes, 16);
    width = byteData.getUint32(0, Endian.big);
    height = byteData.getUint32(4, Endian.big);
    // ICO 字段只支持到 256，超出用 0 表示 256
    if (width >= 256) width = 0;
    if (height >= 256) height = 0;
  }

  final out = BytesBuilder();

  // ICONDIR (6B)
  out.add(_uint16LE(0)); // reserved
  out.add(_uint16LE(1)); // type = icon
  out.add(_uint16LE(1)); // count = 1

  // ICONDIRENTRY (16B)
  out.add([width & 0xFF]);
  out.add([height & 0xFF]);
  out.add([0]); // color count (0 = >256)
  out.add([0]); // reserved
  out.add(_uint16LE(1)); // planes
  out.add(_uint16LE(32)); // bit count
  out.add(_uint32LE(pngBytes.length)); // bytes in res
  out.add(_uint32LE(22)); // offset = 6 + 16

  // PNG data
  out.add(pngBytes);

  final outFile = File('windows/runner/resources/app_icon.ico');
  await outFile.parent.create(recursive: true);
  await outFile.writeAsBytes(out.toBytes());
  stdout.writeln('已生成 ${outFile.path}');
}

List<int> _uint16LE(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _uint32LE(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
