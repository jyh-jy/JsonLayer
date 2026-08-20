import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:json_layer/model/DocumentItem.dart';
import 'package:json_layer/services/WorkspaceService.dart';
import 'package:json_layer/stores/WorkspaceStore.dart';

/// 内存版工作空间：用「路径 → 是否文件夹」的扁平表建模，[loadTree] 时再拼成
/// 嵌套结构。改名/删除/移动都真实改这张表，这样 `reloadTree` 之后的树才会
/// 反映变更 —— store 的展开键清理逻辑依赖这一点。
class _FakeWorkspaceService implements WorkspaceService {
  final Map<String, bool> _entries = {}; // path -> isFolder
  String _workspacePath = '';

  @override
  String get workspacePath => _workspacePath;

  @override
  Future<void> initWorkspace(String path) async {
    _workspacePath = path;
    _entries[path] = true;
  }

  /// 测试辅助：直接铺一批条目
  void seed(Map<String, bool> entries) => _entries.addAll(entries);

  @override
  Future<DocumentItem> loadTree() async => _build(_workspacePath);

  DocumentItem _build(String path) {
    final isFolder = _entries[path] ?? false;
    if (!isFolder) {
      return DocumentItem(
        id: path,
        name: p.basename(path),
        path: path,
        itemType: DocumentItemType.document,
        documentType: DocumentType.fromExtension(path),
      );
    }
    final childPaths = _entries.keys
        .where((key) => key != path && p.dirname(key) == path)
        .toList()
      ..sort();
    return DocumentItem(
      id: path,
      name: p.basename(path),
      path: path,
      itemType: DocumentItemType.folder,
      children: childPaths.map(_build).toList(),
    );
  }

  /// 把 [oldPath] 及其所有子孙的键迁移到 [newPath] 下
  void _remap(String oldPath, String newPath) {
    final affected = _entries.keys
        .where((key) => key == oldPath || p.isWithin(oldPath, key))
        .toList();
    for (final key in affected) {
      final isFolder = _entries.remove(key)!;
      final moved = key == oldPath
          ? newPath
          : p.join(newPath, p.relative(key, from: oldPath));
      _entries[moved] = isFolder;
    }
  }

  @override
  Future<void> rename(String path, String newName) async =>
      _remap(path, p.join(p.dirname(path), newName));

  @override
  Future<void> moveItem(String sourcePath, String destDirPath, {int? index}) async =>
      _remap(sourcePath, p.join(destDirPath, p.basename(sourcePath)));

  @override
  Future<void> delete(String path) async {
    _entries.removeWhere((key, _) => key == path || p.isWithin(path, key));
  }

  @override
  Future<DocumentItem> createFolder(String parentPath, String name) async {
    final path = p.join(parentPath, name);
    _entries[path] = true;
    return _build(path);
  }

  @override
  Future<DocumentItem> createDocument(
    String parentPath,
    String name,
    DocumentType type,
  ) async {
    final path = p.join(parentPath, '$name${type.extension}');
    _entries[path] = false;
    return _build(path);
  }

  @override
  Future<bool> exists(String path) async => _entries.containsKey(path);

  @override
  Future<String> readDocument(String path) async => '';

  @override
  Future<void> writeDocument(String path, String content) async {}

  @override
  Future<DocumentItem> copyFileToWorkspace(
    String sourcePath,
    String destDirPath,
  ) async {
    final path = p.join(destDirPath, p.basename(sourcePath));
    _entries[path] = false;
    return _build(path);
  }
}

const _root = 'ws';
final _api = p.join(_root, 'api');
final _nested = p.join(_api, 'nested');

/// 建一个 ws/{api/{nested/, user.json}, demo.json} 的工作空间
Future<(WorkspaceStore, _FakeWorkspaceService)> _buildStore() async {
  final service = _FakeWorkspaceService();
  await service.initWorkspace(_root);
  service.seed({
    _api: true,
    _nested: true,
    p.join(_api, 'user.json'): false,
    p.join(_root, 'demo.json'): false,
  });
  final store = WorkspaceStore(service);
  await store.loadFromPrefs();
  return (store, service);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'workspace_path': _root});
  });

  test('回归：连点两次后文件夹回到折叠态', () async {
    // 曾经的 BUG：DocumentItem.isExpanded 与 WorkspaceTree 的局部集合被 OR 在
    // 一起且永远反相，导致点多少次都是展开。
    final (store, _) = await _buildStore();

    expect(store.isPathExpanded(_api), isFalse, reason: '子文件夹默认应折叠');

    await store.toggleExpanded(_api);
    expect(store.isPathExpanded(_api), isTrue);

    await store.toggleExpanded(_api);
    expect(store.isPathExpanded(_api), isFalse, reason: '第二次点击必须收起');
  });

  test('首次运行默认展开根目录', () async {
    final (store, _) = await _buildStore();
    expect(store.isPathExpanded(_root), isTrue);
    expect(store.isPathExpanded(_api), isFalse);
  });

  test('展开状态持久化，重建 store 后恢复', () async {
    final (store, _) = await _buildStore();
    await store.toggleExpanded(_api);

    // 新建一个 store 模拟重启，读的是同一份 mock prefs
    final (restored, _) = await _buildStore();
    expect(restored.isPathExpanded(_api), isTrue);
  });

  test('reloadTree 后展开状态不丢', () async {
    final (store, _) = await _buildStore();
    await store.toggleExpanded(_api);

    await store.reloadTree();
    expect(store.isPathExpanded(_api), isTrue);
  });

  test('重命名文件夹时同步重写自身与子孙的展开键', () async {
    final (store, _) = await _buildStore();
    await store.toggleExpanded(_api);
    await store.toggleExpanded(_nested);

    await store.renameItem(_api, 'renamed');

    final renamed = p.join(_root, 'renamed');
    expect(store.isPathExpanded(renamed), isTrue, reason: '自身键要迁移');
    expect(
      store.isPathExpanded(p.join(renamed, 'nested')),
      isTrue,
      reason: '子孙键也要迁移',
    );
    expect(store.isPathExpanded(_api), isFalse, reason: '旧键要清掉');
  });

  test('移动文件夹时同步重写展开键', () async {
    final (store, service) = await _buildStore();
    final target = p.join(_root, 'target');
    service.seed({target: true});
    await store.reloadTree();
    await store.toggleExpanded(_nested);

    await store.moveItem(_nested, target);

    expect(store.isPathExpanded(p.join(target, 'nested')), isTrue);
    expect(store.isPathExpanded(_nested), isFalse);
  });

  test('删除文件夹时丢弃自身与子孙的展开键', () async {
    final (store, _) = await _buildStore();
    await store.toggleExpanded(_api);
    await store.toggleExpanded(_nested);

    await store.deleteItem(_api);

    expect(store.isPathExpanded(_api), isFalse);
    expect(store.isPathExpanded(_nested), isFalse);
  });

  test('reloadTree 清理树里已不存在的陈旧展开键', () async {
    // 模拟用户绕过应用、直接在资源管理器里删了目录
    SharedPreferences.setMockInitialValues({
      'workspace_path': _root,
      'expanded_folder_paths': <String>[
        _root,
        _api,
        p.join(_root, 'ghost'), // 磁盘上并不存在
      ],
    });
    final (store, _) = await _buildStore();

    expect(store.isPathExpanded(_api), isTrue, reason: '真实存在的键要保留');
    expect(
      store.isPathExpanded(p.join(_root, 'ghost')),
      isFalse,
      reason: '陈旧键要被清掉，否则本地存储会无限增长',
    );
  });
}
