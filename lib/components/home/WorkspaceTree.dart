import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:json_layer/components/common/DialogActions.dart';
import 'package:json_layer/components/common/EditorActionButton.dart';
import 'package:json_layer/components/common/EditorContextMenu.dart';
import 'package:json_layer/components/common/HoverBuilder.dart';
import 'package:json_layer/components/common/SafeSnackBar.dart';
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
  String? _highlightPath;
  String? _dropTargetPath;
  bool _isExternalDragging = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _treeScrollController = ScrollController();
  String _searchQuery = '';

  /// 「新建」按钮的位置锚点，用于让下拉菜单贴着按钮弹出。
  final GlobalKey _createButtonKey = GlobalKey();

  /// 搜索过滤时被强制展开的文件夹（命中项的祖先链）。
  ///
  /// 与用户手动展开的状态（存在 [WorkspaceStore] 里）分开：搜索是临时视图，
  /// 清空搜索词后应当回到用户自己的展开状态，不能污染它。每帧重建。
  final Set<String> _searchForceExpanded = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLocateRequest());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _treeScrollController.dispose();
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
    store.expandPaths(store.getParentPaths(path));
    setState(() {
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
          EditorActionButton(
            key: _createButtonKey,
            icon: Icons.add,
            tooltip: '新建',
            color: Color(CommonConstants.primaryColorValue),
            onTap: _showCreateMenu,
          ),
        ],
      ),
    );
  }

  /// 菜单贴着「新建」按钮的左下角弹出。
  ///
  /// 旧实现拿的是整棵树的 RenderBox，菜单会飘到侧栏顶部而不是按钮下方。
  void _showCreateMenu() {
    final box = _createButtonKey.currentContext?.findRenderObject();
    final anchor = box is RenderBox
        ? box.localToGlobal(box.size.bottomLeft(Offset.zero))
        : Offset.zero;
    showEditorContextMenu(
      context: context,
      anchor: anchor,
      entries: [
        EditorMenuEntry(
          label: '新建文件夹',
          icon: Icons.create_new_folder,
          color: Color(CommonConstants.primaryColorValue),
          onTap: () => _onCreateItem('folder'),
        ),
        EditorMenuEntry(
          label: '新建 JSON 文档',
          icon: Icons.insert_drive_file,
          color: Color(CommonConstants.primaryColorValue),
          onTap: () => _onCreateItem('json'),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final hasQuery = _searchQuery.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: HoverBuilder(
        cursor: SystemMouseCursors.text,
        builder: (context, isHovered) {
          return AnimatedContainer(
            duration: CommonConstants.hoverAnimation,
            curve: Curves.easeOut,
            height: CommonConstants.treeSearchBarHeight,
            decoration: BoxDecoration(
              color: Color(CommonConstants.surfaceColorValue),
              borderRadius: BorderRadius.circular(
                CommonConstants.treeRowRadius,
              ),
              border: Border.all(
                color: hasQuery || isHovered
                    ? Color(CommonConstants.primaryColorValue)
                    : Color(CommonConstants.borderColorValue),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Icon(
                  Icons.search,
                  size: 14,
                  color: hasQuery
                      ? Color(CommonConstants.primaryColorValue)
                      : Color(CommonConstants.textSecondaryColorValue),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: '搜索文档',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        color: Color(CommonConstants.textSecondaryColorValue),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
                // 有搜索词时才出现的清空键
                if (hasQuery)
                  EditorActionButton(
                    icon: Icons.close,
                    tooltip: '清空搜索',
                    color: Color(CommonConstants.textSecondaryColorValue),
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
                const SizedBox(width: 2),
              ],
            ),
          );
        },
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
        // 搜索的强制展开集合每帧重算，不写回 store
        _searchForceExpanded.clear();
        final filtered = _filterTree(root, _searchQuery, _searchForceExpanded);
        return DropTarget(
          onDragEntered: (_) => setState(() => _isExternalDragging = true),
          onDragExited: (_) => setState(() => _isExternalDragging = false),
          onDragDone: (details) async {
            setState(() => _isExternalDragging = false);
            await _handleExternalFilesDropped(details.files, root.path);
          },
          child: Stack(
            children: [
              // 树本身必须能滚：之前是裸 Column 套在 Expanded 里，
              // 文件一多就 RenderFlex 溢出，底部条目永远点不到。
              // 拖放蒙层留在 Stack 里不跟着滚。
              Positioned.fill(
                child: Scrollbar(
                  controller: _treeScrollController,
                  child: SingleChildScrollView(
                    controller: _treeScrollController,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _buildTreeNode(filtered, 0),
                    ),
                  ),
                ),
              ),
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
      final fileName = p.basename(file.path);
      final isJson = fileName.toLowerCase().endsWith('.json');
      if (!isJson) continue;
      try {
        await store.copyExternalFile(file.path, destDirPath);
        successCount++;
      } catch (e) {
        if (mounted) {
          SafeSnackBar.show(
            context,
            message: '导入 $fileName 失败: $e',
            idempotencyKey: 'import_failed',
            backgroundColor: Theme.of(context).colorScheme.error,
          );
        }
      }
    }
    if (mounted && successCount > 0) {
      SafeSnackBar.show(
        context,
        message: '成功导入 $successCount 个文件',
        idempotencyKey: 'import_success',
      );
    }
  }

  /// 过滤文件树，并把「含有命中项、需要临时展开」的文件夹路径收集到
  /// [forceExpanded]（out 参数）。
  ///
  /// 以前这里靠 `copyWith(isExpanded: true)` 就地改模型来强制展开，正是造成
  /// 双数据源的元凶之一；现在模型只描述磁盘结构，展开与否一律外挂。
  DocumentItem _filterTree(
    DocumentItem node,
    String query,
    Set<String> forceExpanded,
  ) {
    if (query.isEmpty) return node;
    if (node.isDocument && node.name.toLowerCase().contains(query.toLowerCase())) {
      return node;
    }
    final filteredChildren = node.children
        .map((child) => _filterTree(child, query, forceExpanded))
        .where((child) {
          if (child.isDocument) return child.name.toLowerCase().contains(query.toLowerCase());
          return child.children.isNotEmpty;
        })
        .toList();
    if (node.isFolder && filteredChildren.isNotEmpty) {
      forceExpanded.add(node.path);
      return node.copyWith(children: filteredChildren);
    }
    return node;
  }

  Widget _buildTreeNode(DocumentItem node, int depth) {
    if (node.isDocument) {
      return _buildDocumentTile(node, depth);
    }
    // 展开状态的唯一权威在 store；搜索命中的临时展开单独叠加
    final isExpanded = context.watch<WorkspaceStore>().isPathExpanded(node.path) ||
        _searchForceExpanded.contains(node.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFolderTile(node, depth, isExpanded),
        // 展开/折叠时子树高度补间，避免整块内容瞬间弹出
        AnimatedSize(
          duration: CommonConstants.hoverAnimation,
          curve: Curves.easeOut,
          alignment: Alignment.topLeft,
          child: isExpanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: node.children
                      .map((child) => _buildTreeNode(child, depth + 1))
                      .toList(),
                )
              : const SizedBox(width: double.infinity),
        ),
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
        if (p.isWithin(data.path, node.path)) return false;
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
    return HoverBuilder(
      builder: (context, isHovered) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 展开状态现在只有一个写入口
          onTap: () => context.read<WorkspaceStore>().toggleExpanded(node.path),
          onSecondaryTapDown: (details) =>
              _showFolderMenu(node, details.globalPosition),
          child: AnimatedContainer(
            duration: CommonConstants.hoverAnimation,
            curve: Curves.easeOut,
            height: CommonConstants.treeRowHeight,
            padding: EdgeInsets.only(
              left: 8 + depth * CommonConstants.treeIndentWidth,
              right: 4,
            ),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              // 拖放高亮优先于悬停高亮：它跟手势逻辑绑定，不能被样式吃掉
              color: isDropTarget
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : isHovered
                      ? CommonConstants.primaryOverlay(
                          CommonConstants.rowHoverAlpha,
                        )
                      : Colors.transparent,
              border: isDropTarget
                  ? Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                      width: 1,
                    )
                  : null,
              borderRadius: BorderRadius.circular(
                CommonConstants.treeRowRadius,
              ),
            ),
            child: Row(
              children: [
                // 折叠 0° / 展开 90°，替代两个图标硬切
                AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0,
                  duration: CommonConstants.hoverAnimation,
                  curve: Curves.easeOut,
                  child: Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: Color(CommonConstants.textSecondaryColorValue),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  isExpanded ? Icons.folder_open : Icons.folder,
                  size: 14,
                  color: isExpanded || isHovered
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
        );
      },
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
    return HoverBuilder(
      builder: (context, isHovered) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openDocument(node),
          onSecondaryTapDown: (details) =>
              _showDocumentMenu(node, details.globalPosition),
          child: AnimatedContainer(
            duration: CommonConstants.hoverAnimation,
            curve: Curves.easeOut,
            height: CommonConstants.treeRowHeight,
            padding: EdgeInsets.only(
              left: 8 + depth * CommonConstants.treeIndentWidth + 18,
              right: 4,
            ),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              // 定位高亮（3 秒）优先于悬停
              color: isHighlighted
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : isHovered
                      ? CommonConstants.primaryOverlay(
                          CommonConstants.rowHoverAlpha,
                        )
                      : Colors.transparent,
              border: isHighlighted
                  ? Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                      width: 1,
                    )
                  : null,
              borderRadius: BorderRadius.circular(
                CommonConstants.treeRowRadius,
              ),
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
        );
      },
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
    if (p.isWithin(data.path, destFolderPath)) return;

    final store = context.read<WorkspaceStore>();
    final name = p.basename(data.path);
    final newPath = p.join(destFolderPath, name);

    // 检查目标是否已存在同名文件
    final exists = await store.exists(newPath);
    if (exists && mounted) {
      SafeSnackBar.show(
        context,
        message: '目标位置已存在 $name',
        idempotencyKey: 'move_exists_$name',
        backgroundColor: Theme.of(context).colorScheme.error,
      );
      return;
    }

    try {
      await store.moveItem(data.path, destFolderPath);
      if (mounted) {
        SafeSnackBar.show(
          context,
          message: '已移动到 ${p.basename(destFolderPath)}',
          idempotencyKey: 'move_success',
        );
      }
    } catch (e) {
      if (mounted) {
        SafeSnackBar.show(
          context,
          message: '移动失败: $e',
          idempotencyKey: 'move_failed',
          backgroundColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  Widget _buildFileIcon(DocumentType? type) {
    final color = type == DocumentType.log
        ? Color(CommonConstants.logColorValue)
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
        SafeSnackBar.show(
          context,
          message: '新建文档失败: $e',
          idempotencyKey: 'create_doc_failed',
          backgroundColor: Theme.of(context).colorScheme.error,
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
          DialogActions(
            confirmLabel: '确定',
            onConfirm: () => _confirmCreate(controller, onSubmit, ctx),
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

  void _showFolderMenu(DocumentItem node, Offset globalPosition) {
    final store = context.read<WorkspaceStore>();
    showEditorContextMenu(
      context: context,
      anchor: globalPosition,
      entries: [
        EditorMenuEntry(
          label: '在资源管理器中打开',
          icon: Icons.folder_open,
          onTap: () => _openInExplorer(node.path),
        ),
        const EditorMenuDivider(),
        EditorMenuEntry(
          label: '重命名',
          icon: Icons.edit,
          onTap: () => _showRenameDialog(node, store),
        ),
        EditorMenuEntry(
          label: '删除',
          icon: Icons.delete_outline,
          color: Color(CommonConstants.destructiveColorValue),
          onTap: () => _showDeleteConfirm(node, store),
        ),
        const EditorMenuDivider(),
        EditorMenuEntry(
          label: '新建子文件夹',
          icon: Icons.create_new_folder,
          color: Color(CommonConstants.primaryColorValue),
          onTap: () => _showCreateDialog(
            title: '新建子文件夹',
            hintText: '文件夹名称',
            onSubmit: (name) => store.createFolder(node.path, name),
          ),
        ),
        EditorMenuEntry(
          label: '新建文档',
          icon: Icons.insert_drive_file,
          color: Color(CommonConstants.primaryColorValue),
          onTap: () => _showCreateDialog(
            title: '新建文档',
            hintText: '文件名称',
            onSubmit: (name) => _createDocumentAndOpen(node.path, name),
          ),
        ),
      ],
    );
  }

  void _showDocumentMenu(DocumentItem node, Offset globalPosition) {
    final store = context.read<WorkspaceStore>();
    showEditorContextMenu(
      context: context,
      anchor: globalPosition,
      entries: [
        EditorMenuEntry(
          label: '打开',
          icon: Icons.open_in_new,
          color: Color(CommonConstants.primaryColorValue),
          onTap: () => _openDocument(node),
        ),
        EditorMenuEntry(
          label: '在资源管理器中打开',
          icon: Icons.folder_open,
          onTap: () => _openInExplorer(node.path),
        ),
        const EditorMenuDivider(),
        EditorMenuEntry(
          label: '重命名',
          icon: Icons.edit,
          onTap: () => _showRenameDialog(node, store),
        ),
        EditorMenuEntry(
          label: '删除',
          icon: Icons.delete_outline,
          color: Color(CommonConstants.destructiveColorValue),
          onTap: () => _showDeleteConfirm(node, store),
        ),
      ],
    );
  }

  void _openInExplorer(String path) {
    // Windows: 在资源管理器中定位并选中该文件
    Process.run('explorer', ['/select,', path]);
  }

  void _showRenameDialog(DocumentItem node, WorkspaceStore store) {
    // 文件重命名：让用户只改"主名"，扩展名固定不展示在输入框里。
    // - 输入框初始值 = 去掉扩展名后的文件名（例: "测试.json" -> "测试"）
    // - 输入框右侧用 suffixText 展示 ".json"/".log"，非编辑、灰字
    // - 用户即便手滑在主名后面又加了 ".json"，确认时也会自动去掉再拼回原扩展名
    // - 文件夹重命名：原来的逻辑，不拆扩展名
    String initialName = node.name;
    String? extensionSuffix; // null = 不使用扩展名机制（文件夹/未知文件）
    String? forcedExtension;  // 确认时强制拼回的扩展名

    if (node.isDocument && node.documentType != null) {
      final ext = node.documentType!.extension; // ".json" / ".log"
      final nameLower = node.name.toLowerCase();
      final extLower = ext.toLowerCase();
      if (nameLower.endsWith(extLower) && node.name.length > ext.length) {
        initialName = node.name.substring(0, node.name.length - ext.length);
        extensionSuffix = ext;
        forcedExtension = ext;
      }
    }

    final controller = TextEditingController(text: initialName);
    // 打开时自动全选主名，用户直接输入即可覆盖，不用再手动拖动选择
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
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
          onSubmitted: (_) => _confirmRename(
            controller,
            node,
            store,
            ctx,
            forcedExtension: forcedExtension,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            // 当是文件时，suffix 非编辑灰色显示原扩展名，提示用户无需输入
            suffixText: extensionSuffix,
            suffixStyle: TextStyle(
              color: Color(CommonConstants.textSecondaryColorValue),
              fontSize: 13,
            ),
            // 有 suffix 时让用户知道这是"原样保留"的，用次级文字颜色
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
          DialogActions(
            confirmLabel: '确定',
            onConfirm: () => _confirmRename(
              controller,
              node,
              store,
              ctx,
              forcedExtension: forcedExtension,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRename(
    TextEditingController controller,
    DocumentItem node,
    WorkspaceStore store,
    BuildContext ctx, {
    required String? forcedExtension,
  }) async {
    var stem = controller.text.trim();
    if (stem.isEmpty) {
      if (ctx.mounted) {
        SafeSnackBar.show(
          ctx,
          message: '文件名不能为空',
          idempotencyKey: 'rename_empty_name',
        );
      }
      return;
    }

    String newName;
    if (forcedExtension != null) {
      // 文件重命名：强制使用原来的扩展名。
      // 容错：如果用户"好心"在主名后面又写了 .json / .log，先剥离再拼，
      // 避免出现 "测试.json.json" 这样的结果。
      final lower = stem.toLowerCase();
      for (final type in DocumentType.values) {
        final ext = type.extension.toLowerCase();
        if (lower.endsWith(ext) && stem.length > ext.length) {
          stem = stem.substring(0, stem.length - ext.length);
          break;
        }
      }
      if (stem.isEmpty) {
        if (ctx.mounted) {
          SafeSnackBar.show(
            ctx,
            message: '文件名不能为空',
            idempotencyKey: 'rename_empty_name',
          );
        }
        return;
      }
      newName = '$stem$forcedExtension';
    } else {
      newName = stem;
    }

    if (newName != node.name) {
      final oldPath = node.path;
      final sep = oldPath.contains('\\') ? '\\' : '/';
      final parentDir = oldPath.substring(0, oldPath.lastIndexOf(sep));
      final newPath = '$parentDir$sep$newName';

      // 先获取 tabStore，避免异步间隙后使用 BuildContext
      final tabStore = context.read<TabStore>();

      await store.renameItem(oldPath, newName);

      // 重命名成功后更新标签页路径，确保标签不会丢失
      tabStore.updateTabPath(oldPath, newPath, newName);

      if (mounted && ctx.mounted) Navigator.pop(ctx);
    } else {
      // 名字没改就直接关对话框，避免空操作
      if (ctx.mounted) Navigator.pop(ctx);
    }
  }

  void _showDeleteConfirm(DocumentItem node, WorkspaceStore store) {
    showDialog(
      context: context,
      builder: (ctx) {
        final focusNode = FocusNode();
        return KeyboardListener(
          focusNode: focusNode,
          autofocus: true,
          onKeyEvent: (event) {
            if (event is KeyDownEvent &&
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
              DialogActions(
                confirmLabel: '删除',
                isDestructive: true,
                onConfirm: () {
                  store.deleteItem(node.path);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
