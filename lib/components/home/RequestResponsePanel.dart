import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:json_layer/components/home/JsonEditor.dart';
import 'package:json_layer/components/home/ObjectTreeEditor.dart';
import 'package:json_layer/contants/CommonConstant.dart';
import 'package:json_layer/model/DocumentItem.dart';
import 'package:json_layer/stores/EditorStore.dart';
import 'package:json_layer/stores/TabStore.dart';
import 'package:json_layer/stores/WorkspaceStore.dart';

/// 请求体/响应体面板（参考 APIFOX Body 设计）。
///
/// 结构：
///   TabBar: 请求体 | 响应体
///     子 TabBar: JSON 模式 | 对象模式
class RequestResponsePanel extends StatefulWidget {
  const RequestResponsePanel({super.key});

  @override
  State<RequestResponsePanel> createState() => _RequestResponsePanelState();
}

class _RequestResponsePanelState extends State<RequestResponsePanel>
    with TickerProviderStateMixin {
  late TabController _mainTabController;
  late TabController _subTabController;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);
    _subTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _mainTabController.dispose();
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMainTabBar(theme),
            Expanded(
              child: TabBarView(
                controller: _mainTabController,
                children: [
                  _buildEditorArea(
                    theme: theme,
                    tab: activeTab,
                    isRequest: true,
                  ),
                  _buildEditorArea(
                    theme: theme,
                    tab: activeTab,
                    isRequest: false,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 64,
            color: Color(CommonConstants.textSecondaryColorValue).withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '请选择或新建一个文档',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Color(CommonConstants.textSecondaryColorValue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainTabBar(ThemeData theme) {
    return Container(
      height: 36,
      color: Color(CommonConstants.surfaceColorValue),
      child: TabBar(
        controller: _mainTabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
        labelStyle: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelStyle: theme.textTheme.bodySmall?.copyWith(
          fontSize: 13,
        ),
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: theme.colorScheme.primary,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: Color(CommonConstants.textSecondaryColorValue),
        tabs: const [
          Tab(text: '请求体'),
          Tab(text: '响应体'),
        ],
      ),
    );
  }

  Widget _buildEditorArea({
    required ThemeData theme,
    required DocumentTab tab,
    required bool isRequest,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubTabBar(theme),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              _buildJsonMode(theme, tab, isRequest),
              _buildObjectMode(theme, tab, isRequest),
            ],
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

  Widget _buildJsonMode(ThemeData theme, DocumentTab tab, bool isRequest) {
    final content = isRequest ? tab.requestBody : tab.responseBody;
    final title = isRequest ? '请求体' : '响应体';
    return JsonEditor(
      content: content,
      title: title,
      onChanged: (value) {
        final tabStore = context.read<TabStore>();
        tabStore.updateTab(
          tab.id,
          requestBody: isRequest ? value : null,
          responseBody: isRequest ? null : value,
          isDirty: true,
        );
      },
      // 仅请求体（承载磁盘文件内容）响应 Ctrl+S 保存
      onSave: isRequest ? _saveActiveTab : null,
    );
  }

  /// Ctrl+S 保存：将当前请求体内容写回磁盘文件。
  Future<void> _saveActiveTab() async {
    final tabStore = context.read<TabStore>();
    final tab = tabStore.activeTab;
    if (tab == null) return;

    if (!tab.isBound) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前文档未绑定磁盘文件，请先在左侧新建或打开一个 JSON 文档'),
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Widget _buildObjectMode(ThemeData theme, DocumentTab tab, bool isRequest) {
    final content = isRequest ? tab.requestBody : tab.responseBody;
    final title = isRequest ? '请求体' : '响应体';
    return ObjectTreeEditor(
      content: content,
      title: title,
      readOnly: true,
      onChanged: (value) {
        final tabStore = context.read<TabStore>();
        tabStore.updateTab(
          tab.id,
          requestBody: isRequest ? value : null,
          responseBody: isRequest ? null : value,
          isDirty: true,
        );
      },
    );
  }
}
