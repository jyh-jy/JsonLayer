import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:json_layer/model/DocumentItem.dart';
import 'package:json_layer/services/WorkspaceService.dart';

/// 工作空间状态管理。
///
/// 负责：初始化工作空间、文件树维护、文件夹/文档 CRUD。
class WorkspaceStore extends ChangeNotifier {
  final WorkspaceService _service;

  WorkspaceStore(this._service);

  DocumentItem? _root;
  bool _isLoading = false;
  String? _errorMessage;
  String? _locatePath;
  int _locateTick = 0;

  DocumentItem? get root => _root;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get workspacePath => _service.workspacePath;
  String? get locatePath => _locatePath;
  int get locateTick => _locateTick;

  /// 请求定位文件：展开父级目录并高亮该文件
  void requestLocate(String path) {
    _locatePath = path;
    _locateTick++;
    notifyListeners();
  }

  /// 清除定位
  void clearLocate() {
    _locatePath = null;
    notifyListeners();
  }

  /// 获取某路径的所有父级路径（用于展开文件夹）
  List<String> getParentPaths(String path) {
    final parts = path.split('\\');
    final result = <String>[];
    for (var i = 1; i < parts.length; i++) {
      result.add(parts.sublist(0, i).join('\\'));
    }
    return result;
  }

  /// 初始化：检查是否已配置工作空间路径
  Future<bool> hasConfiguredWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('workspace_path');
    return path != null && path.isNotEmpty;
  }

  /// 初始化工作空间并持久化路径
  Future<void> configureWorkspace(String path) async {
    await _service.initWorkspace(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workspace_path', path);
    await reloadTree();
  }

  /// 从已持久化的路径加载
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('workspace_path');
    if (path != null && path.isNotEmpty) {
      await _service.initWorkspace(path);
      await reloadTree();
    }
  }

  /// 重新加载文件树
  Future<void> reloadTree() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _root = await _service.loadTree();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 创建文件夹
  Future<DocumentItem?> createFolder(String parentPath, String name) async {
    try {
      final item = await _service.createFolder(parentPath, name);
      await reloadTree();
      return item;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// 创建文档
  Future<DocumentItem?> createDocument(
    String parentPath,
    String name,
    DocumentType type,
  ) async {
    try {
      final item = await _service.createDocument(parentPath, name, type);
      await reloadTree();
      return item;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// 读取文档内容
  Future<String> readDocument(String path) async {
    return _service.readDocument(path);
  }

  /// 写入文档内容
  Future<void> writeDocument(String path, String content) async {
    await _service.writeDocument(path, content);
  }

  /// 重命名
  Future<void> renameItem(String path, String newName) async {
    try {
      await _service.rename(path, newName);
      await reloadTree();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// 删除
  Future<void> deleteItem(String path) async {
    try {
      await _service.delete(path);
      await reloadTree();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// 在树中展开/折叠文件夹
  void toggleExpand(String folderPath) {
    if (_root == null) return;
    _root = _toggleExpandInTree(_root!, folderPath);
    notifyListeners();
  }

  DocumentItem _toggleExpandInTree(DocumentItem node, String targetPath) {
    if (node.path == targetPath) {
      return node.copyWith(isExpanded: !node.isExpanded);
    }
    final newChildren = node.children.map((child) {
      if (child.isFolder) {
        return _toggleExpandInTree(child, targetPath);
      }
      return child;
    }).toList();
    return node.copyWith(children: newChildren);
  }

  /// 根据路径查找节点
  DocumentItem? findItem(String path) {
    if (_root == null) return null;
    return _findInTree(_root!, path);
  }

  DocumentItem? _findInTree(DocumentItem node, String path) {
    if (node.path == path) return node;
    for (final child in node.children) {
      final found = _findInTree(child, path);
      if (found != null) return found;
    }
    return null;
  }
}
