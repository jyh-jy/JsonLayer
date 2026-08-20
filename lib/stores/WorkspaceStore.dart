import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:json_layer/contants/CommonConstant.dart';
import 'package:json_layer/model/DocumentItem.dart';
import 'package:json_layer/services/WorkspaceService.dart';

/// 工作空间状态管理。
///
/// 负责：初始化工作空间、文件树维护、文件夹/文档 CRUD、文件夹展开状态。
class WorkspaceStore extends ChangeNotifier {
  final WorkspaceService _service;

  WorkspaceStore(this._service);

  DocumentItem? _root;
  bool _isLoading = false;
  String? _errorMessage;
  String? _locatePath;
  int _locateTick = 0;

  /// 已展开的文件夹路径集合 —— 展开状态的**唯一权威**。
  ///
  /// 放在 store 而不是 WorkspaceTree 的局部 state，是因为它要跨三件事存活：
  /// 每次 CRUD 后的 [reloadTree]、重命名导致的路径变更、以及应用重启。
  final Set<String> _expandedPaths = {};

  /// 展开状态是否已经从本地读过。首次运行（读到 null）时要给根目录兜个底。
  bool _expandedLoaded = false;

  DocumentItem? get root => _root;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get workspacePath => _service.workspacePath;
  String? get locatePath => _locatePath;
  int get locateTick => _locateTick;

  // --------------------------- 文件夹展开状态 ---------------------------

  bool isPathExpanded(String path) => _expandedPaths.contains(path);

  /// 切换展开/折叠并持久化。
  Future<void> toggleExpanded(String path) async {
    if (!_expandedPaths.remove(path)) {
      _expandedPaths.add(path);
    }
    notifyListeners();
    await _persistExpanded();
  }

  /// 批量展开（定位文件时展开其所有父级）。不写盘 —— 定位是临时行为，
  /// 用户真正手动切换时才值得持久化。
  void expandPaths(Iterable<String> paths) {
    final before = _expandedPaths.length;
    _expandedPaths.addAll(paths);
    if (_expandedPaths.length != before) notifyListeners();
  }

  Future<void> _persistExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      CommonConstants.expandedFolderPathsKey,
      _expandedPaths.toList(),
    );
  }

  /// 从本地恢复展开状态。必须在 [reloadTree] **之前** await，
  /// 否则第一帧会先渲染全折叠再跳成展开。
  Future<void> _loadExpandedPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(CommonConstants.expandedFolderPathsKey);
    _expandedPaths
      ..clear()
      ..addAll(saved ?? const []);
    // saved 为 null = 从没存过 = 首次运行，交给 reloadTree 展开根目录
    _expandedLoaded = saved != null;
  }

  /// 文件夹重命名/移动后重写展开键（键是路径，不重写就会失效）。
  /// 与 [TabStore.updateTabPath] 同样用 `p.isWithin` 一并迁移子孙路径。
  void _rewriteExpandedPaths(String oldPath, String newPath) {
    final affected = _expandedPaths
        .where((path) => path == oldPath || p.isWithin(oldPath, path))
        .toList();
    if (affected.isEmpty) return;
    for (final old in affected) {
      _expandedPaths.remove(old);
      _expandedPaths.add(
        old == oldPath
            ? newPath
            : p.join(newPath, p.relative(old, from: oldPath)),
      );
    }
  }

  /// 删除文件夹时丢弃它及其子孙的展开键。
  void _dropExpandedPathsUnder(String path) {
    _expandedPaths.removeWhere(
      (key) => key == path || p.isWithin(path, key),
    );
  }

  /// 清理树里已不存在的展开键。
  ///
  /// 覆盖「用户直接在资源管理器里删了目录」这类应用感知不到的变更，
  /// 顺便防止本地存储里的路径列表无限增长。
  void _pruneExpandedPaths() {
    if (_root == null || _expandedPaths.isEmpty) return;
    final alive = <String>{};
    void collect(DocumentItem node) {
      if (!node.isFolder) return;
      alive.add(node.path);
      for (final child in node.children) {
        collect(child);
      }
    }

    collect(_root!);
    final removed = _expandedPaths.length;
    _expandedPaths.removeWhere((key) => !alive.contains(key));
    if (_expandedPaths.length != removed) {
      _persistExpanded();
    }
  }

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
    final result = <String>[];
    var parent = p.dirname(path);
    while (parent != '.' && parent != path) {
      result.add(parent);
      final nextParent = p.dirname(parent);
      if (nextParent == parent) break;
      parent = nextParent;
    }
    return result.reversed.toList();
  }

  /// 初始化：检查是否已配置工作空间路径
  Future<bool> hasConfiguredWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(CommonConstants.workspacePathKey);
    return path != null && path.isNotEmpty;
  }

  /// 初始化工作空间并持久化路径
  Future<void> configureWorkspace(String path) async {
    await _service.initWorkspace(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(CommonConstants.workspacePathKey, path);
    await _loadExpandedPaths();
    await reloadTree();
  }

  /// 从已持久化的路径加载
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(CommonConstants.workspacePathKey);
    if (path != null && path.isNotEmpty) {
      await _service.initWorkspace(path);
      await _loadExpandedPaths();
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
      // 首次运行没有任何存档：默认只展开根目录
      if (!_expandedLoaded && _root != null) {
        _expandedPaths.add(_root!.path);
        _expandedLoaded = true;
        await _persistExpanded();
      }
      _pruneExpandedPaths();
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
      // 展开键以路径为键，改名后必须跟着迁移，否则该文件夹会「忘记」自己是展开的
      _rewriteExpandedPaths(path, p.join(p.dirname(path), newName));
      await _persistExpanded();
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
      _dropExpandedPathsUnder(path);
      await _persistExpanded();
      await reloadTree();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// 从外部复制文件到工作空间
  Future<DocumentItem?> copyExternalFile(String sourcePath, String destDirPath) async {
    try {
      final item = await _service.copyFileToWorkspace(sourcePath, destDirPath);
      await reloadTree();
      return item;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// 移动文件/文件夹
  Future<void> moveItem(String sourcePath, String destDirPath) async {
    try {
      await _service.moveItem(sourcePath, destDirPath);
      _rewriteExpandedPaths(
        sourcePath,
        p.join(destDirPath, p.basename(sourcePath)),
      );
      await _persistExpanded();
      await reloadTree();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// 检查路径是否存在
  Future<bool> exists(String path) => _service.exists(path);

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
