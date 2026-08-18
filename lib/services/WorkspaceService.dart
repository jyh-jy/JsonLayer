import 'dart:async';

import 'package:json_layer/model/DocumentItem.dart';

/// 工作空间服务抽象（扩展点：外部可替换实现，如云端存储）。
///
/// UI 层严禁直接调用 dart:io，统一通过此接口操作。
abstract class WorkspaceService {
  /// 当前工作空间根路径
  String get workspacePath;

  /// 初始化工作空间（创建目录结构）
  Future<void> initWorkspace(String path);

  /// 读取文件树（从根路径扫描）
  Future<DocumentItem> loadTree();

  /// 在指定父目录下创建文件夹
  Future<DocumentItem> createFolder(String parentPath, String name);

  /// 在指定父目录下创建文档
  Future<DocumentItem> createDocument(
    String parentPath,
    String name,
    DocumentType type,
  );

  /// 读取文档内容
  Future<String> readDocument(String path);

  /// 写入文档内容
  Future<void> writeDocument(String path, String content);

  /// 重命名
  Future<void> rename(String path, String newName);

  /// 删除
  Future<void> delete(String path);

  /// 将外部文件复制到工作空间指定目录
  Future<DocumentItem> copyFileToWorkspace(
    String sourcePath,
    String destDirPath,
  );

  /// 移动文件/文件夹到目标目录（支持排序）
  Future<void> moveItem(String sourcePath, String destDirPath, {int? index});

  /// 判断路径是否存在
  Future<bool> exists(String path);
}
