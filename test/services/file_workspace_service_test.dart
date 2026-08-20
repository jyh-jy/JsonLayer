import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:json_layer/model/DocumentItem.dart';
import 'package:json_layer/services/FileWorkspaceService.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDirectory;
  late FileWorkspaceService service;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('json_layer_test_');
    service = FileWorkspaceService();
    await service.initWorkspace(tempDirectory.path);
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test('文件操作使用当前平台的路径分隔符', () async {
    final folder = await service.createFolder(tempDirectory.path, 'nested');
    expect(folder.path, p.join(tempDirectory.path, 'nested'));

    final document = await service.createDocument(
      folder.path,
      'entry',
      DocumentType.json,
    );
    expect(document.path, p.join(folder.path, 'entry.json'));

    await service.rename(document.path, 'renamed.json');
    final renamedPath = p.join(folder.path, 'renamed.json');
    expect(await service.exists(renamedPath), isTrue);

    await service.moveItem(renamedPath, tempDirectory.path);
    expect(await service.exists(p.join(tempDirectory.path, 'renamed.json')), isTrue);
  });
}
