import 'package:flutter/foundation.dart';

import 'package:json_layer/model/DocumentItem.dart';

/// 简易 ID 生成器（避免引入 uuid 依赖）。
String _genId() =>
    '${DateTime.now().millisecondsSinceEpoch}_${identical(0, 1) ? 0 : DateTime.now().microsecondsSinceEpoch}';

/// 标签页状态管理。
class TabStore extends ChangeNotifier {
  final List<DocumentTab> _tabs = [];
  String? _activeTabId;

  List<DocumentTab> get tabs => List.unmodifiable(_tabs);
  String? get activeTabId => _activeTabId;
  DocumentTab? get activeTab {
    if (_activeTabId == null) return null;
    try {
      return _tabs.firstWhere((t) => t.id == _activeTabId);
    } catch (e) {
      return null;
    }
  }

  /// 打开文档（若已存在则切换，否则新增）
  DocumentTab openDocument(DocumentItem item, {String? initialContent}) {
    final existing = _tabs.where((t) => t.itemId == item.id).toList();
    if (existing.isNotEmpty) {
      _activeTabId = existing.first.id;
      notifyListeners();
      return existing.first;
    }

    final tab = DocumentTab(
      id: _genId(),
      itemId: item.id,
      path: item.path,
      title: item.name,
      documentType: item.documentType ?? DocumentType.json,
      requestBody: initialContent ?? '',
    );
    _tabs.add(tab);
    _activeTabId = tab.id;
    notifyListeners();
    return tab;
  }

  /// 切换激活标签
  void activateTab(String tabId) {
    _activeTabId = tabId;
    notifyListeners();
  }

  /// 关闭标签
  void closeTab(String tabId) {
    final index = _tabs.indexWhere((t) => t.id == tabId);
    if (index == -1) return;

    _tabs.removeAt(index);

    if (_activeTabId == tabId) {
      if (_tabs.isNotEmpty) {
        final newIndex = index >= _tabs.length ? _tabs.length - 1 : index;
        _activeTabId = _tabs[newIndex].id;
      } else {
        _activeTabId = null;
      }
    }
    notifyListeners();
  }

  /// 关闭所有标签
  void closeAll() {
    _tabs.clear();
    _activeTabId = null;
    notifyListeners();
  }

  /// 关闭除指定标签外的所有标签
  void closeOthers(String tabId) {
    _tabs.removeWhere((t) => t.id != tabId);
    _activeTabId = tabId;
    notifyListeners();
  }

  /// 更新标签内容
  void updateTab(
    String tabId, {
    String? title,
    String? requestBody,
    String? responseBody,
    EditorMode? editorMode,
    bool? isDirty,
  }) {
    final index = _tabs.indexWhere((t) => t.id == tabId);
    if (index == -1) return;
    _tabs[index] = _tabs[index].copyWith(
      title: title,
      requestBody: requestBody,
      responseBody: responseBody,
      editorMode: editorMode,
      isDirty: isDirty,
    );
    notifyListeners();
  }

  /// 根据 itemId 查找标签
  DocumentTab? findByItemId(String itemId) {
    try {
      return _tabs.firstWhere((t) => t.itemId == itemId);
    } catch (e) {
      return null;
    }
  }

  /// 文件/文件夹重命名后更新相关标签页的路径。
  ///
  /// 支持两种情况：
  /// - 文件重命名：oldPath 完全匹配标签的 path
  /// - 文件夹重命名：标签的 path 以 oldPath\ 开头（子文件/子文件夹）
  void updateTabPath(String oldPath, String newPath, String newTitle) {
    bool changed = false;
    for (var i = 0; i < _tabs.length; i++) {
      final tab = _tabs[i];
      if (tab.path == oldPath) {
        _tabs[i] = tab.copyWith(
          path: newPath,
          itemId: newPath,
          title: newTitle,
        );
        changed = true;
      } else if (tab.path.startsWith('$oldPath\\')) {
        final relativePath = tab.path.substring(oldPath.length);
        final newChildPath = '$newPath$relativePath';
        final newChildTitle = newChildPath.split('\\').last;
        _tabs[i] = tab.copyWith(
          path: newChildPath,
          itemId: newChildPath,
          title: newChildTitle,
        );
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }
}
