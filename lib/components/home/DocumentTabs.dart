import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';

import 'package:json_layer/components/common/SafeSnackBar.dart';
import 'package:json_layer/contants/CommonConstant.dart';
import 'package:json_layer/model/DocumentItem.dart';
import 'package:json_layer/stores/TabStore.dart';
import 'package:json_layer/stores/ThemeStore.dart';
import 'package:json_layer/stores/WorkspaceStore.dart';

/// 顶部标签栏组件（参考 APIFOX Tab 设计）。
class DocumentTabs extends StatefulWidget {
  const DocumentTabs({super.key});

  @override
  State<DocumentTabs> createState() => _DocumentTabsState();
}

class _DocumentTabsState extends State<DocumentTabs> {
  final ScrollController _tabScrollController = ScrollController();

  @override
  void dispose() {
    _tabScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer2<ThemeStore, TabStore>(
      builder: (context, themeStore, tabStore, _) {
        final hasBg = themeStore.hasAnyBackground;
        final bar = Container(
          height: CommonConstants.tabBarHeight,
          color: hasBg
              ? Color(CommonConstants.surfaceColorValue).withValues(alpha: 0.6)
              : Color(CommonConstants.surfaceColorValue),
          child: _buildTabBarContent(theme, tabStore),
        );
        if (!hasBg) return bar;
        // 有背景图（内置或自定义）：固定高度的标签栏叠加毛玻璃
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: bar,
          ),
        );
      },
    );
  }

  Widget _buildTabBarContent(ThemeData theme, TabStore tabStore) {
    final tabs = tabStore.tabs;
    if (tabs.isEmpty) {
      return _buildEmptyState(theme);
    }
    return Row(
      children: [
        Expanded(
          child: _buildScrollableTabs(tabs, tabStore, theme),
        ),
        _buildAddButton(tabStore, theme),
      ],
    );
  }

  Widget _buildScrollableTabs(List<DocumentTab> tabs, TabStore tabStore, ThemeData theme) {
    return Listener(
      onPointerSignal: (signal) {
        if (signal is PointerScrollEvent) {
          // 将垂直滚轮转换为水平滚动
          if (_tabScrollController.hasClients) {
            final delta = signal.scrollDelta.dy != 0
                ? signal.scrollDelta.dy
                : signal.scrollDelta.dx;
            final maxExtent = _tabScrollController.position.maxScrollExtent;
            final newOffset = (_tabScrollController.offset + delta).clamp(0.0, maxExtent);
            _tabScrollController.jumpTo(newOffset);
          }
        }
      },
      child: SingleChildScrollView(
        controller: _tabScrollController,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(
          children: tabs
              .map((tab) => _buildTab(tab, tabStore, theme))
              .toList(),
        ),
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
      onSecondaryTapDown: (details) =>
          _showTabMenu(tab, tabStore, details.globalPosition),
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

  /// 标签右键菜单位置计算
  RelativeRect _menuPosition(Offset globalPosition) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );
  }

  /// 标签右键菜单
  void _showTabMenu(DocumentTab tab, TabStore tabStore, Offset globalPosition) {
    showMenu<String>(
      context: context,
      position: _menuPosition(globalPosition),
      color: Color(CommonConstants.surfaceColorValue),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CommonConstants.menuBorderRadius),
        side: BorderSide(color: Color(CommonConstants.borderColorValue)),
      ),
      items: [
        _buildMenuItem(
          '关闭其他', Icons.tab_unselected, 'close_others',
        ),
        _buildMenuItem(
          '定位', Icons.my_location, 'locate',
          iconColor: Color(CommonConstants.primaryColorValue),
        ),
        const PopupMenuDivider(height: 8),
        _buildMenuItem(
          '关闭所有', Icons.clear_all, 'close_all',
          iconColor: const Color(0xFFDC2626),
        ),
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      if (value == 'close_others') {
        tabStore.closeOthers(tab.id);
      } else if (value == 'locate') {
        if (tab.path.isNotEmpty) {
          context.read<WorkspaceStore>().requestLocate(tab.path);
        } else {
          SafeSnackBar.show(
            context,
            message: '该标签未绑定文件，无法定位',
            idempotencyKey: 'locate_not_bound',
          );
        }
      } else if (value == 'close_all') {
        tabStore.closeAll();
      }
    });
  }

  /// 构建菜单项（与 WorkspaceTree 风格统一）
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
      child: Tooltip(
        message: '新建 JSON 文档',
        child: InkWell(
          onTap: () => _createJsonDocument(),
          borderRadius: BorderRadius.circular(CommonConstants.buttonRadius),
          splashColor: CommonConstants.primaryOverlay(0.08),
          highlightColor: CommonConstants.primaryOverlay(0.05),
          child: Padding(
            padding: const EdgeInsets.all(CommonConstants.buttonPadding),
            child: Icon(
              Icons.add,
              size: 16,
              color: Color(CommonConstants.textSecondaryColorValue),
            ),
          ),
        ),
      ),
    );
  }

  /// 新建 JSON 文档：自动命名 → 落盘创建文件 → 打开标签。
  Future<void> _createJsonDocument() async {
    final workspaceStore = context.read<WorkspaceStore>();
    final root = workspaceStore.root;
    if (root == null) {
      SafeSnackBar.show(
        context,
        message: '工作空间未就绪',
        idempotencyKey: 'workspace_not_ready',
      );
      return;
    }

    // 自动生成唯一文件名，无需弹窗
    final now = DateTime.now();
    final timestamp =
        '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final name = '未命名_$timestamp.json';

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
        SafeSnackBar.show(
          context,
          message: '新建文档失败: $e',
          idempotencyKey: 'create_doc_failed',
          backgroundColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }
}
