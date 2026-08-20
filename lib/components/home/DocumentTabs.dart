import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';

import 'package:json_layer/components/common/EditorActionButton.dart';
import 'package:json_layer/components/common/EditorContextMenu.dart';
import 'package:json_layer/components/common/HoverBuilder.dart';
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
              ? Color(CommonConstants.surfaceColorValue)
                  .withValues(alpha: CommonConstants.glassToolbarAlpha)
              : Color(CommonConstants.surfaceColorValue),
          child: _buildTabBarContent(theme, tabStore),
        );
        if (!hasBg) return bar;
        // 有背景图（内置或自定义）：固定高度的标签栏叠加毛玻璃。
        // bar 必须保持半透明，否则模糊层被完全遮住、背景图看不见。
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: CommonConstants.glassBlurSigma,
              sigmaY: CommonConstants.glassBlurSigma,
            ),
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
    return HoverBuilder(
      builder: (context, isHovered) {
        return GestureDetector(
          onTap: () => tabStore.activateTab(tab.id),
          onSecondaryTapDown: (details) =>
              _showTabMenu(tab, tabStore, details.globalPosition),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: CommonConstants.hoverAnimation,
            curve: Curves.easeOut,
            height: CommonConstants.tabBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: Color(CommonConstants.borderColorValue),
                  width: 1,
                ),
                bottom: BorderSide(
                  // 悬停时下划线先淡淡浮现，提示「点这里会切过来」
                  color: isActive
                      ? theme.colorScheme.primary
                      : isHovered
                          ? theme.colorScheme.primary.withValues(alpha: 0.35)
                          : Colors.transparent,
                  width: 2,
                ),
              ),
              color: isActive
                  ? Color(CommonConstants.backgroundColorValue)
                  : isHovered
                      ? CommonConstants.primaryOverlay(
                          CommonConstants.rowHoverAlpha,
                        )
                      : Colors.transparent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 12),
                _buildTypeBadge(tab.documentType, theme),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: CommonConstants.tabTitleMaxWidth,
                  ),
                  child: Text(
                    tab.title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isActive
                          ? theme.colorScheme.primary
                          : Color(CommonConstants.textPrimaryColorValue),
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
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
                EditorActionButton(
                  icon: Icons.close,
                  tooltip: '关闭',
                  color: Color(CommonConstants.destructiveColorValue),
                  onTap: () => tabStore.closeTab(tab.id),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 标签右键菜单
  void _showTabMenu(DocumentTab tab, TabStore tabStore, Offset globalPosition) {
    showEditorContextMenu(
      context: context,
      anchor: globalPosition,
      entries: [
        EditorMenuEntry(
          label: '关闭其他',
          icon: Icons.tab_unselected,
          onTap: () => tabStore.closeOthers(tab.id),
        ),
        EditorMenuEntry(
          label: '定位',
          icon: Icons.my_location,
          color: Color(CommonConstants.primaryColorValue),
          onTap: () {
            if (tab.path.isNotEmpty) {
              context.read<WorkspaceStore>().requestLocate(tab.path);
            } else {
              SafeSnackBar.show(
                context,
                message: '该标签未绑定文件，无法定位',
                idempotencyKey: 'locate_not_bound',
              );
            }
          },
        ),
        const EditorMenuDivider(),
        EditorMenuEntry(
          label: '关闭所有',
          icon: Icons.clear_all,
          color: Color(CommonConstants.destructiveColorValue),
          onTap: tabStore.closeAll,
        ),
      ],
    );
  }

  Widget _buildTypeBadge(DocumentType type, ThemeData theme) {
    final color = type == DocumentType.log
        ? Color(CommonConstants.logColorValue)
        : theme.colorScheme.primary;
    final bgColor = color.withValues(alpha: 0.1);
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
      child: EditorActionButton(
        icon: Icons.add,
        tooltip: '新建 JSON 文档',
        color: Color(CommonConstants.primaryColorValue),
        onTap: _createJsonDocument,
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
