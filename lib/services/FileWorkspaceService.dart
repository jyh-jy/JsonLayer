import 'dart:async';
import 'dart:io';

import 'package:json_layer/model/DocumentItem.dart';
import 'package:json_layer/services/WorkspaceService.dart';

/// 基于 dart:io 的本地文件系统实现。
class FileWorkspaceService implements WorkspaceService {
  String _workspacePath = '';

  @override
  String get workspacePath => _workspacePath;

  @override
  Future<void> initWorkspace(String path) async {
    _workspacePath = path;
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  @override
  Future<DocumentItem> loadTree() async {
    if (_workspacePath.isEmpty) {
      throw StateError('工作空间未初始化');
    }
    final rootDir = Directory(_workspacePath);
    return _scanDirectory(rootDir);
  }

  DocumentItem _scanDirectory(Directory dir) {
    final children = <DocumentItem>[];
    try {
      final entities = dir.listSync();
      // 排序：文件夹在前，文件在后，按名称排序
      final sorted = entities.toList()
        ..sort((a, b) {
          final aIsDir = a is Directory;
          final bIsDir = b is Directory;
          if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
          return a.path.split('\\').last.compareTo(b.path.split('\\').last);
        });

      for (final entity in sorted) {
        final name = entity.path.split('\\').last;
        // 跳过隐藏文件
        if (name.startsWith('.')) continue;

        if (entity is Directory) {
          children.add(_scanDirectory(entity));
        } else if (entity is File) {
          final docType = DocumentType.fromExtension(entity.path);
          children.add(DocumentItem(
            id: entity.path,
            name: name,
            path: entity.path,
            itemType: DocumentItemType.document,
            documentType: docType,
          ));
        }
      }
    } on FileSystemException {
      // 权限不足等情况，返回空节点
    }

    return DocumentItem(
      id: dir.path,
      name: dir.path.split('\\').last.isEmpty ? dir.path : dir.path.split('\\').last,
      path: dir.path,
      itemType: DocumentItemType.folder,
      children: children,
      isExpanded: true,
    );
  }

  @override
  Future<DocumentItem> createFolder(String parentPath, String name) async {
    final folderPath = '$parentPath\\$name';
    final dir = Directory(folderPath);
    await dir.create(recursive: true);
    return DocumentItem(
      id: folderPath,
      name: name,
      path: folderPath,
      itemType: DocumentItemType.folder,
      children: const [],
      isExpanded: false,
    );
  }

  @override
  Future<DocumentItem> createDocument(
    String parentPath,
    String name,
    DocumentType type,
  ) async {
    final fileName = _uniqueFileName(parentPath, name, type.extension);
    final docPath = '$parentPath\\$fileName';
    final file = File(docPath);
    await file.create();
    return DocumentItem(
      id: docPath,
      name: fileName,
      path: docPath,
      itemType: DocumentItemType.document,
      documentType: type,
    );
  }

  /// 生成不重名的文件名（`foo.json` → `foo2.json` → `foo3.json` …）。
  String _uniqueFileName(String parentPath, String name, String extension) {
    // 归一化输入：去掉可能重复的后缀，得到基础名
    String base;
    if (name.endsWith(extension)) {
      base = name.substring(0, name.length - extension.length);
    } else {
      base = name;
    }

    var candidate = '$base$extension';
    var index = 2;
    while (File('$parentPath\\$candidate').existsSync()) {
      candidate = '$base$index$extension';
      index++;
    }
    return candidate;
  }

  @override
  Future<String> readDocument(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  @override
  Future<void> writeDocument(String path, String content) async {
    final file = File(path);
    await file.writeAsString(content);
  }

  @override
  Future<void> rename(String path, String newName) async {
    final file = File(path);
    final dir = Directory(path);
    final parentDir = path.substring(0, path.lastIndexOf('\\'));
    final newPath = '$parentDir\\$newName';
    if (await file.exists()) {
      await file.rename(newPath);
    } else if (await dir.exists()) {
      await dir.rename(newPath);
    }
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    final dir = Directory(path);
    if (await file.exists()) {
      await file.delete();
    } else if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  @override
  Future<bool> exists(String path) async {
    final fileExists = await File(path).exists();
    final dirExists = await Directory(path).exists();
    return fileExists || dirExists;
  }

  @override
  Future<DocumentItem> copyFileToWorkspace(
    String sourcePath,
    String destDirPath,
  ) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('源文件不存在: $sourcePath');
    }
    final fileName = sourcePath.split('\\').last;
    final destName = _uniqueFileName(destDirPath, fileName.replaceAll('.json', ''), '.json');
    final destPath = '$destDirPath\\$destName';
    await sourceFile.copy(destPath);
    return DocumentItem(
      id: destPath,
      name: destName,
      path: destPath,
      itemType: DocumentItemType.document,
      documentType: DocumentType.json,
    );
  }

  @override
  Future<void> moveItem(
    String sourcePath,
    String destDirPath, {
    int? index,
  }) async {
    final sourceFile = File(sourcePath);
    final sourceDir = Directory(sourcePath);
    final name = sourcePath.split('\\').last;
    final newPath = '$destDirPath\\$name';

    if (await sourceFile.exists()) {
      if (sourcePath == newPath) return;
      await sourceFile.rename(newPath);
    } else if (await sourceDir.exists()) {
      if (sourcePath == newPath) return;
      await sourceDir.rename(newPath);
    }
  }
}
