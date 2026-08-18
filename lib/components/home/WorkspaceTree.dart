import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:provider/provider.dart';

import 'package:json_layer/contants/CommonConstant.dart';
import 'package:json_layer/model/DocumentItem.dart';
import 'package:json_layer/stores/TabStore.dart';
import 'package:json_layer/stores/WorkspaceStore.dart';

/// 拖动数据（内部拖拽使用）
class _DragData {
  final String path;
  final bool isFolder;
  const _DragData({required this.path, required this.isFolder});
}

/// 左侧工作空间文件树组件。
class WorkspaceTree extends StatefulWidget {
  const WorkspaceTree({super.key});

  @override
  State<WorkspaceTree> createState() => _WorkspaceTreeState();
}

class _WorkspaceTreeState extends State<WorkspaceTree> {
  final Set<String> _expandedFolderPaths = {};
  String? _highlightPath;
  String? _dropTargetPath;
  bool _isExternalDragging = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLocateRequest());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 检查并处理定位请求
  void _checkLocateRequest() {
    if (!mounted) return;
    final store = context.read<WorkspaceStore>();
    if (store.locatePath != null) {
      _expandAndHighlight(store.locatePath!);
      store.clearLocate();
    }
  }

  /// 展开路径的所有父级文件夹并高亮目标文件
  void _expandAndHighlight(String path) {
    final store = context.read<WorkspaceStore>();
    final parentPaths = store.getParentPaths(path);
    setState(() {
      _expandedFolderPaths.addAll(parentPaths);
      _highlightPath = path;
    });
    // 3秒后取消高亮
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _highlightPath == path) {
        setState(() {
          _highlightPath = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        _buildSearchBar(),
        const Divider(height: 1),
        Expanded(child: _buildTree()),
      ],
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.folder_open, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '工作空间',
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _buildHeaderButton(
            icon: Icons.add,
            tooltip: '新建',
            onTap: () => _showCreateMenu(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CommonConstants.buttonRadius),
        splashColor: CommonConstants.primaryOverlay(0.08),
        highlightColor: CommonConstants.primaryOverlay(0.05),
        child: Padding(
          padding: const EdgeInsets.all(CommonConstants.buttonPadding),
          child: Icon(
            icon,
            size: 16,
            color: Color(CommonConstants.textSecondaryColorValue),
          ),
        ),
      ),
    );
  }

  void _showCreateMenu() {
    final renderBox = context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        renderBox.localToGlobal(Offset.zero),
        renderBox.localToGlobal(renderBox.size.bottomRight(Offset.zero)),
      ),
      Offset.zero & MediaQuery.of(context).size,
    );
    showMenu<String>(
      context: context,
      position: position,
      color: Color(CommonConstants.surfaceColorValue),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CommonConstants.menuBorderRadius),
        side: BorderSide(color: Color(CommonConstants.borderColorValue)),
      ),
      items: [
        _buildMenuItem(
          '新建文件夹', Icons.create_new_folder, 'folder',
          iconColor: Color(CommonConstants.primaryColorValue),
        ),
        _buildMenuItem(
          '新建 JSON 文档', Icons.insert_drive_file, 'json',
          iconColor: Color(CommonConstants.primaryColorValue),
        ),
      ],
    ).then((value) {
      if (value != null) _onCreateItem(value);
    });
  }

  PopupMenuItem<String> _buildMenuItem(
    String label,
    IconData icon,
    String value, {
    Color? iconColor,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Container(
        height: CommonConstants.menuItemHeight,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: iconColor ?? Color(CommonConstants.textSecondaryColorValue),
            ),
            const SizedBox(width: CommonConstants.menuItemPadding),
            Text(
              label,
              style: TextStyle(
                fontSize: CommonConstants.menuFontSize,
                color: Color(CommonConstants.textPrimaryColorValue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Color(CommonConstants.borderColorValue)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            const Icon(Icons.search, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '搜索文档',
                  hintStyle: TextStyle(fontSize: 11, color: Colors.grey),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTree() {
    return Consumer<WorkspaceStore>(
      builder: (context, store, _) {
        // 检查定位请求
        if (store.locatePath != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _expandAndHighlight(store.locatePath!);
            store.clearLocate();
          });
        }
        if (store.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final root = store.root;
        if (root == null) {
          return const Center(child: Text('暂无数据'));
        }
        final filtered = _filterTree(root, _searchQuery);
        return DropTarget(
          onDragEntered: (_) => setState(() => _isExternalDragging = true),
          onDragExited: (_) => setState(() => _isExternalDragging = false),
          onDragDone: (details) async {
            setState(() => _isExternalDragging = false);
            await _handleExternalFilesDropped(details.files, root.path);
          },
          child: Stack(
            children: [
              _buildTreeNode(filtered, 0),
              if (_isExternalDragging)
                Positioned.fill(
                  child: Container(
                    color: Colors.blue.withValues(alpha: 0.1),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.upload_file,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              '释放以导入 JSON 文件',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 处理外部文件拖放
  Future<void> _handleExternalFilesDropped(
      List<DropItem> files, String destDirPath) async {
    final store = context.read<WorkspaceStore>();
    int successCount = 0;
    for (final file in files) {
      final fileName = file.path.split('\\').last;
      final isJson = fileName.toLowerCase().endsWith('.json');
      if (!isJson) continue;
      try {
        await store.copyExternalFile(file.path, destDirPath);
        successCount++;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入 $fileName 失败: $e')),
          );
        }
      }
    }
    if (mounted && successCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 $successCount 个文件')),
      );
    }
  }

  DocumentItem _filterTree(DocumentItem node, String query) {
    if (query.isEmpty) return node;
    if (node.isDocument && node.name.toLowerCase().contains(query.toLowerCase())) {
      return node;
    }
    final filteredChildren = node.children
        .map((child) => _filterTree(child, query))
        .where((child) {
          if (child.isDocument) return child.name.toLowerCase().contains(query.toLowerCase());
          return child.children.isNotEmpty;
        })
        .toList();
    if (node.isFolder && filteredChildren.isNotEmpty) {
      return node.copyWith(children: filteredChildren, isExpanded: true);
    }
    return node;
  }

  Widget _buildTreeNode(DocumentItem node, int depth) {
    if (node.isDocument) {
      return _buildDocumentTile(node, depth);
    }
    final isExpanded =
        _expandedFolderPaths.contains(node.path) || node.isExpanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFolderTile(node, depth, isExpanded),
        if (isExpanded)
          ...node.children.map((child) => _buildTreeNode(child, depth + 1)),
      ],
    );
  }

  Widget _buildFolderTile(DocumentItem node, int depth, bool isExpanded) {
    final theme = Theme.of(context);
    final isDropTarget = _dropTargetPath == node.path;
    return DragTarget<_DragData>(
      onWillAcceptWithDetails: (details) {
        // 不允许拖入自身或自身的子级
        final data = details.data;
        if (data.path == node.path) return false;
        if (data.path.startsWith('${node.path}\\')) return false;
        setState(() => _dropTargetPath = node.path);
        return true;
      },
      onLeave: (data) {
        if (_dropTargetPath == node.path) {
          setState(() => _dropTargetPath = null);
        }
      },
      onAcceptWithDetails: (details) {
        setState(() => _dropTargetPath = null);
        final data = details.data;
        _handleInternalDrop(data, node.path);
      },
      builder: (context, candidateData, rejectedData) {
        return Draggable<_DragData>(
          feedback: _buildDragFeedback(node),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _buildFolderTileContent(node, depth, isExpanded, theme),
          ),
          data: _DragData(path: node.path, isFolder: true),
          child: _buildFolderTileContent(
              node, depth, isExpanded, theme,
              isDropTarget: isDropTarget),
        );
      },
    );
  }

  Widget _buildFolderTileContent(DocumentItem node, int depth, bool isExpanded,
      ThemeData theme, {bool isDropTarget = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.08),
        highlightColor: theme.colorScheme.primary.withValues(alpha: 0.05),
        onTap: () {
          setState(() {
            if (_expandedFolderPaths.contains(node.path)) {
              _expandedFolderPaths.remove(node.path);
            } else {
              _expandedFolderPaths.add(node.path);
            }
          });
          context.read<WorkspaceStore>().toggleExpand(node.path);
        },
        onSecondaryTapDown: (details) =>
            _showFolderMenu(node, details.globalPosition),
        child: Container(
          height: 26,
          padding: EdgeInsets.only(left: 8 + depth * 14),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: isDropTarget
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            border: isDropTarget
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    width: 1,
                  )
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                isExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                size: 14,
                color: Color(CommonConstants.textSecondaryColorValue),
              ),
              const SizedBox(width: 2),
              Icon(
                isExpanded ? Icons.folder_open : Icons.folder,
                size: 14,
                color: isExpanded
                    ? theme.colorScheme.primary
                    : Color(CommonConstants.textSecondaryColorValue),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentTile(DocumentItem node, int depth) {
    final theme = Theme.of(context);
    final tabStore = context.read<TabStore>();
    final isOpen = tabStore.findByItemId(node.id) != null;
    final isHighlighted = _highlightPath == node.path;
    return Draggable<_DragData>(
      feedback: _buildDragFeedback(node),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildDocumentTileContent(node, depth, isOpen, isHighlighted, theme),
      ),
      data: _DragData(path: node.path, isFolder: false),
      child: _buildDocumentTileContent(node, depth, isOpen, isHighlighted, theme),
    );
  }

  Widget _buildDocumentTileContent(DocumentItem node, int depth, bool isOpen,
      bool isHighlighted, ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.08),
        highlightColor: theme.colorScheme.primary.withValues(alpha: 0.05),
        onTap: () => _openDocument(node),
        onSecondaryTapDown: (details) =>
            _showDocumentMenu(node, details.globalPosition),
        child: Container(
          height: 26,
          padding: EdgeInsets.only(left: 8 + depth * 14 + 18),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: isHighlighted
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            border: isHighlighted
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    width: 1,
                  )
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              _buildFileIcon(node.documentType),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isOpen ? theme.colorScheme.primary : null,
                    fontWeight: isHighlighted ? FontWeight.w600 : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建拖动反馈 Widget
  Widget _buildDragFeedback(DocumentItem node) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              node.isFolder ? Icons.folder : Icons.insert_drive_file,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              node.name,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// 处理内部拖放（移动文件/文件夹）
  Future<void> _handleInternalDrop(_DragData data, String destFolderPath) async {
    if (data.path == destFolderPath) return;
    if (data.path.startsWith('$destFolderPath\\')) return;

    final store = context.read<WorkspaceStore>();
    final name = data.path.split('\\').last;
    final newPath = '$destFolderPath\\$name';

    // 检查目标是否已存在同名文件
    final exists = await store.exists(newPath);
    if (exists && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('目标位置已存在 $name')),
      );
      return;
    }

    try {
      await store.moveItem(data.path, destFolderPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已移动到 ${destFolderPath.split('\\').last}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移动失败: $e')),
        );
      }
    }
  }

  Widget _buildFileIcon(DocumentType? type) {
    final color = type == DocumentType.log
        ? Colors.orange
        : Theme.of(context).colorScheme.primary;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Center(
        child: Text(
          type?.label.substring(0, 1) ?? 'J',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  Future<void> _openDocument(DocumentItem node) async {
    if (!node.isDocument) return;
    final store = context.read<WorkspaceStore>();
    final content = await store.readDocument(node.path);
    if (!mounted) return;
    context.read<TabStore>().openDocument(node, initialContent: content);
  }

  /// 新建文档并自动打开标签（落盘 + 绑定磁盘路径）。
  Future<void> _createDocumentAndOpen(String parentPath, String name) async {
    final workspaceStore = context.read<WorkspaceStore>();
    try {
      final item = await workspaceStore.createDocument(
        parentPath,
        name,
        DocumentType.json,
      );
      if (item == null || !mounted) return;
      context.read<TabStore>().openDocument(item, initialContent: '');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('新建文档失败: $e')),
        );
      }
    }
  }

  void _onCreateItem(String type) {
    final store = context.read<WorkspaceStore>();
    final root = store.root;
    if (root == null) return;

    if (type == 'folder') {
      _showCreateDialog(
        title: '新建文件夹',
        hintText: '文件夹名称',
        onSubmit: (name) => store.createFolder(root.path, name),
      );
    } else {
      _showCreateDialog(
        title: '新建 JSON 文档',
        hintText: '文件名称',
        onSubmit: (name) => _createDocumentAndOpen(root.path, name),
      );
    }
  }

  void _showCreateDialog({
    required String title,
    required String hintText,
    required Future<void> Function(String name) onSubmit,
  }) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _confirmCreate(controller, onSubmit, ctx),
          decoration: InputDecoration(
            hintText: hintText,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Color(CommonConstants.borderColorValue)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Color(CommonConstants.borderColorValue)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 1.5),
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  Color(CommonConstants.textPrimaryColorValue),
              side: BorderSide(
                  color: Color(CommonConstants.borderColorValue)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _confirmCreate(controller, onSubmit, ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _confirmCreate(
    TextEditingController controller,
    Future<void> Function(String name) onSubmit,
    BuildContext ctx,
  ) {
    final name = controller.text.trim();
    if (name.isNotEmpty) {
      onSubmit(name);
      Navigator.pop(ctx);
    }
  }

  /// 根据指针全局坐标计算右键菜单位置（跟随光标）。
  RelativeRect _menuPosition(Offset globalPosition) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );
  }

  void _showFolderMenu(DocumentItem node, Offset globalPosition) {
    showMenu<String>(
      context: context,
      position: _menuPosition(globalPosition),
      color: Color(CommonConstants.surfaceColorValue),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CommonConstants.menuBorderRadius),
        side: BorderSide(color: Color(CommonConstants.borderColorValue)),
      ),
      items: [
        _buildMenuItem('在资源管理器中打开', Icons.folder_open, 'explorer'),
        const PopupMenuDivider(height: 8),
        _buildMenuItem('重命名', Icons.edit, 'rename'),
        _buildMenuItem(
          '删除', Icons.delete_outline, 'delete',
          iconColor: const Color(0xFFDC2626),
        ),
        const PopupMenuDivider(height: 8),
        _buildMenuItem(
          '新建子文件夹', Icons.create_new_folder, 'new_sub_folder',
          iconColor: Color(CommonConstants.primaryColorValue),
        ),
        _buildMenuItem(
          '新建文档', Icons.insert_drive_file, 'new_doc',
          iconColor: Color(CommonConstants.primaryColorValue),
        ),
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      final store = context.read<WorkspaceStore>();
      if (value == 'explorer') {
        _openInExplorer(node.path);
      } else if (value == 'rename') {
        _showRenameDialog(node, store);
      } else if (value == 'delete') {
        _showDeleteConfirm(node, store);
      } else if (value == 'new_sub_folder') {
        _showCreateDialog(
          title: '新建子文件夹',
          hintText: '文件夹名称',
          onSubmit: (name) => store.createFolder(node.path, name),
        );
      } else if (value == 'new_doc') {
        _showCreateDialog(
          title: '新建文档',
          hintText: '文件名称',
          onSubmit: (name) => _createDocumentAndOpen(node.path, name),
        );
      }
    });
  }

  void _showDocumentMenu(DocumentItem node, Offset globalPosition) {
    showMenu<String>(
      context: context,
      position: _menuPosition(globalPosition),
      color: Color(CommonConstants.surfaceColorValue),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CommonConstants.menuBorderRadius),
        side: BorderSide(color: Color(CommonConstants.borderColorValue)),
      ),
      items: [
        _buildMenuItem('打开', Icons.open_in_new, 'open'),
        _buildMenuItem('在资源管理器中打开', Icons.folder_open, 'explorer'),
        const PopupMenuDivider(height: 8),
        _buildMenuItem('重命名', Icons.edit, 'rename'),
        _buildMenuItem(
          '删除', Icons.delete_outline, 'delete',
          iconColor: const Color(0xFFDC2626),
        ),
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      final store = context.read<WorkspaceStore>();
      if (value == 'open') {
        _openDocument(node);
      } else if (value == 'explorer') {
        _openInExplorer(node.path);
      } else if (value == 'rename') {
        _showRenameDialog(node, store);
      } else if (value == 'delete') {
        _showDeleteConfirm(node, store);
      }
    });
  }

  void _openInExplorer(String path) {
    // Windows: 在资源管理器中定位并选中该文件
    Process.run('explorer', ['/select,', path]);
  }

  void _showRenameDialog(DocumentItem node, WorkspaceStore store) {
    final controller = TextEditingController(text: node.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: const Text(
          '重命名',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _confirmRename(controller, node, store, ctx),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Color(CommonConstants.borderColorValue)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Color(CommonConstants.borderColorValue)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 1.5),
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  Color(CommonConstants.textPrimaryColorValue),
              side: BorderSide(
                  color: Color(CommonConstants.borderColorValue)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _confirmRename(controller, node, store, ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _confirmRename(
    TextEditingController controller,
    DocumentItem node,
    WorkspaceStore store,
    BuildContext ctx,
  ) {
    final name = controller.text.trim();
    if (name.isNotEmpty && name != node.name) {
      store.renameItem(node.path, name);
      Navigator.pop(ctx);
    }
  }

  void _showDeleteConfirm(DocumentItem node, WorkspaceStore store) {
    showDialog(
      context: context,
      builder: (ctx) {
        final focusNode = FocusNode();
        return RawKeyboardListener(
          focusNode: focusNode,
          autofocus: true,
          onKey: (event) {
            if (event is RawKeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.enter) {
              store.deleteItem(node.path);
              Navigator.pop(ctx);
            }
          },
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text(
              '确认删除',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            content: Text(
              '确定删除 "${node.name}" 吗？此操作不可恢复。',
              style: TextStyle(
                fontSize: 14,
                color: Color(CommonConstants.textSecondaryColorValue),
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      Color(CommonConstants.textPrimaryColorValue),
                  side: BorderSide(
                      color: Color(CommonConstants.borderColorValue)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  store.deleteItem(node.path);
                  Navigator.pop(ctx);
                },
                child: const Text('删除'),
              ),
            ],
          ),
        );
      },
    );
  }
}
