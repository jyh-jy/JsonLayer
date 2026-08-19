import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:json_layer/components/common/SafeSnackBar.dart';
import 'package:json_layer/components/home/JsonEditor.dart';
import 'package:json_layer/components/home/ObjectTreeEditor.dart';
import 'package:json_layer/contants/CommonConstant.dart';
import 'package:json_layer/model/DocumentItem.dart';
import 'package:json_layer/stores/EditorStore.dart';
import 'package:json_layer/stores/TabStore.dart';
import 'package:json_layer/stores/WorkspaceStore.dart';

/// 数据面板（参考 APIFOX Body 设计）。
///
/// 结构：
///   TabBar: JSON 模式 | 对象模式
class RequestResponsePanel extends StatefulWidget {
  const RequestResponsePanel({super.key});

  @override
  State<RequestResponsePanel> createState() => _RequestResponsePanelState();
}

class _RequestResponsePanelState extends State<RequestResponsePanel>
    with TickerProviderStateMixin {
  late TabController _subTabController;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer2<TabStore, EditorStore>(
      builder: (context, tabStore, editorStore, _) {
        final activeTab = tabStore.activeTab;
        if (activeTab == null) {
          return _buildEmptyState(theme);
        }
        // 打开了 JSON 文档：给编辑器区域套上不透明底色，让自定义背景不影响 JSON/对象模式区域
        return Container(
          color: Color(CommonConstants.backgroundColorValue),
          child: _buildEditorArea(
            theme: theme,
            tab: activeTab,
          ),
        );
      },
    );
  }

  /// 未打开文档时：保持透明，让外层的自定义背景图（或亮色背景色）直接透过来显示，
  /// 不再展示"请选择或新建一个文档"的提示文字。
  Widget _buildEmptyState(ThemeData theme) {
    return const SizedBox.expand();
  }

  Widget _buildEditorArea({
    required ThemeData theme,
    required DocumentTab tab,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubTabBar(theme),
        Expanded(
          // 用 IndexedStack 替代 TabBarView：
          // - JSON/对象两种 Editor 常驻内存，模式切换零重建
          // - 对象模式避免每次切过去都重新 jsonDecode 整棵树并重建
          //   SelectableText/ListView（这是切换卡顿的最大来源）
          //
          // 注意：直接监听 _subTabController（ChangeNotifier），而不是
          // _subTabController.animation!，因为后者在 Flutter 里是可空的，
          // 初始化阶段的那一帧可能为 null 导致 Null check 崩溃。
          child: AnimatedBuilder(
            animation: _subTabController,
            builder: (context, child) {
              return IndexedStack(
                index: _subTabController.index,
                children: [
                  _buildJsonMode(theme, tab),
                  _buildObjectMode(theme, tab),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSubTabBar(ThemeData theme) {
    return Container(
      height: 30,
      color: Color(CommonConstants.sidebarColorValue),
      child: TabBar(
        controller: _subTabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        labelStyle: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelStyle: theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
        ),
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: theme.colorScheme.primary,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: Color(CommonConstants.textSecondaryColorValue),
        tabs: const [
          Tab(text: 'JSON 模式'),
          Tab(text: '对象模式'),
        ],
      ),
    );
  }

  Widget _buildJsonMode(ThemeData theme, DocumentTab tab) {
    final content = tab.requestBody;
    const title = '数据';
    return JsonEditor(
      content: content,
      title: title,
      onChanged: (value) {
        final tabStore = context.read<TabStore>();
        tabStore.updateTab(
          tab.id,
          requestBody: value,
          isDirty: true,
        );
      },
      onSave: _saveActiveTab,
    );
  }

  /// Ctrl+S 保存：将当前数据内容写回磁盘文件。
  Future<void> _saveActiveTab() async {
    final tabStore = context.read<TabStore>();
    final tab = tabStore.activeTab;
    if (tab == null) return;

    if (!tab.isBound) {
      SafeSnackBar.show(
        context,
        message: '当前文档未绑定磁盘文件，请先在左侧新建或打开一个 JSON 文档',
        idempotencyKey: 'save_not_bound',
      );
      return;
    }

    final workspaceStore = context.read<WorkspaceStore>();
    try {
      await workspaceStore.writeDocument(tab.path, tab.requestBody);
      // 保存成功后文件头红点消失即为标识，无需弹框提示。
      tabStore.updateTab(tab.id, isDirty: false);
    } catch (e) {
      if (mounted) {
        SafeSnackBar.show(
          context,
          message: '保存失败: $e',
          idempotencyKey: 'save_failed',
          backgroundColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  Widget _buildObjectMode(ThemeData theme, DocumentTab tab) {
    final content = tab.requestBody;
    const title = '数据';
    return ObjectTreeEditor(
      content: content,
      title: title,
      readOnly: true,
      onChanged: (value) {
        final tabStore = context.read<TabStore>();
        tabStore.updateTab(
          tab.id,
          requestBody: value,
          isDirty: true,
        );
      },
    );
  }
}
