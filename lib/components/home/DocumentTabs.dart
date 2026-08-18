import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:json_layer/contants/CommonConstant.dart';
import 'package:json_layer/model/DocumentItem.dart';
import 'package:json_layer/stores/TabStore.dart';
import 'package:json_layer/stores/WorkspaceStore.dart';

/// 顶部标签栏组件（参考 APIFOX Tab 设计）。
class DocumentTabs extends StatefulWidget {
  const DocumentTabs({super.key});

  @override
  State<DocumentTabs> createState() => _DocumentTabsState();
}

class _DocumentTabsState extends State<DocumentTabs> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: CommonConstants.tabBarHeight,
      color: Color(CommonConstants.surfaceColorValue),
      child: Consumer<TabStore>(
        builder: (context, tabStore, _) {
          final tabs = tabStore.tabs;
          if (tabs.isEmpty) {
            return _buildEmptyState(theme);
          }
          return Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: tabs
                        .map((tab) => _buildTab(tab, tabStore, theme))
                        .toList(),
                  ),
                ),
              ),
              _buildAddButton(tabStore, theme),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '选择左侧文档或点击 + 新建',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Color(CommonConstants.textSecondaryColorValue),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(DocumentTab tab, TabStore tabStore, ThemeData theme) {
    final isActive = tabStore.activeTabId == tab.id;
    return GestureDetector(
      onTap: () => tabStore.activateTab(tab.id),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: CommonConstants.tabBarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: Color(CommonConstants.borderColorValue),
              width: 1,
            ),
            bottom: BorderSide(
              color: isActive ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          color: isActive
              ? Color(CommonConstants.backgroundColorValue)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 12),
            _buildTypeBadge(tab.documentType, theme),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                tab.title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isActive
                      ? theme.colorScheme.primary
                      : Color(CommonConstants.textPrimaryColorValue),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            if (tab.isDirty)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: () => tabStore.closeTab(tab.id),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: Color(CommonConstants.textSecondaryColorValue),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(DocumentType type, ThemeData theme) {
    final color = type == DocumentType.log
        ? Colors.orange
        : theme.colorScheme.primary;
    final bgColor = type == DocumentType.log
        ? Colors.orange.withValues(alpha: 0.1)
        : theme.colorScheme.primary.withValues(alpha: 0.1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _buildAddButton(TabStore tabStore, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: PopupMenuButton<DocumentType>(
        icon: Icon(
          Icons.add,
          size: 16,
          color: Color(CommonConstants.textSecondaryColorValue),
        ),
        tooltip: '新建文档',
        itemBuilder: (_) => const [
          PopupMenuItem(value: DocumentType.json, child: Text('JSON 文档')),
        ],
        onSelected: (type) => _createJsonDocument(),
      ),
    );
  }

  /// 新建 JSON 文档：命名 → 落盘创建文件 → 打开标签（绑定磁盘路径）。
  Future<void> _createJsonDocument() async {
    final workspaceStore = context.read<WorkspaceStore>();
    final root = workspaceStore.root;
    if (root == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('工作空间未就绪')),
      );
      return;
    }

    final name = await _promptFileName();
    if (name == null || name.isEmpty || !mounted) return;

    try {
      final item = await workspaceStore.createDocument(
        root.path,
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

  /// 弹出命名对话框，返回输入的文件名（未输入返回 null）。
  Future<String?> _promptFileName() {
    final controller = TextEditingController(text: '未命名.json');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建 JSON 文档'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '文件名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
