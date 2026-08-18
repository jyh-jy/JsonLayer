import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:json_layer/contants/CommonConstant.dart';
import 'package:json_layer/model/DocumentItem.dart';
import 'package:json_layer/stores/TabStore.dart';
import 'package:json_layer/stores/WorkspaceStore.dart';

/// 左侧工作空间文件树组件。
class WorkspaceTree extends StatefulWidget {
  const WorkspaceTree({super.key});

  @override
  State<WorkspaceTree> createState() => _WorkspaceTreeState();
}

class _WorkspaceTreeState extends State<WorkspaceTree> {
  String? _expandedFolderPath;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
                decoration: const InputDecoration(
                  hintText: '搜索文档',
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
        if (store.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final root = store.root;
        if (root == null) {
          return const Center(child: Text('暂无数据'));
        }
        final filtered = _filterTree(root, _searchQuery);
        return _buildTreeNode(filtered, 0);
      },
    );
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
    final isExpanded = _expandedFolderPath == node.path || node.isExpanded;
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.08),
        highlightColor: theme.colorScheme.primary.withValues(alpha: 0.05),
        onTap: () {
          setState(() {
            _expandedFolderPath = isExpanded ? null : node.path;
          });
          context.read<WorkspaceStore>().toggleExpand(node.path);
        },
        onSecondaryTapDown: (details) =>
            _showFolderMenu(node, details.globalPosition),
        child: Container(
          height: 26,
          padding: EdgeInsets.only(left: 8 + depth * 14),
          alignment: Alignment.centerLeft,
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
          child: Row(
            children: [
              _buildFileIcon(node.documentType),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isOpen ? theme.colorScheme.primary : null,
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
      if (value == 'rename') {
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
      } else if (value == 'rename') {
        _showRenameDialog(node, store);
      } else if (value == 'delete') {
        _showDeleteConfirm(node, store);
      }
    });
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
