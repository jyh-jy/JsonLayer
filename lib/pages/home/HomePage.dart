import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'package:json_layer/components/home/WorkspaceTree.dart';
import 'package:json_layer/components/home/DocumentTabs.dart';
import 'package:json_layer/components/home/RequestResponsePanel.dart';
import 'package:json_layer/contants/CommonConstant.dart';
import 'package:json_layer/stores/TabStore.dart';
import 'package:json_layer/stores/WorkspaceStore.dart';

/// 主页面：三栏布局（文件树 + 标签栏 + 编辑器）。
///
/// 参考 APIFOX 离线空间布局。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WorkspaceStore>().reloadTree();
    });
  }

  KeyEventResult _onGlobalKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyS) {
        _saveActiveTab();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// 全局 Ctrl+S 保存：将当前激活标签的数据写回磁盘。
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
      if (!mounted) return;
      tabStore.updateTab(tab.id, isDirty: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(CommonConstants.backgroundColorValue),
      body: Focus(
        onKeyEvent: _onGlobalKeyEvent,
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildLeftPanel(),
                  _buildVerticalDivider(),
                  Expanded(child: _buildRightPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final theme = Theme.of(context);
    return Container(
      height: CommonConstants.toolbarHeight,
      color: Color(CommonConstants.surfaceColorValue),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.data_object,
                      color: theme.colorScheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      CommonConstants.appName,
                      style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(width: 20),
                    Consumer<WorkspaceStore>(
                      builder: (context, store, _) {
                        return Expanded(
                          child: Text(
                            '工作空间 · ${store.workspacePath}',
                            style: theme.textTheme.bodySmall?.copyWith(
                                  color: Color(CommonConstants.textSecondaryColorValue),
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const _ExternalLinks(),
          const _WindowControls(),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Container(
      width: CommonConstants.leftNavWidth,
      color: Color(CommonConstants.sidebarColorValue),
      child: Column(
        children: [
          const Expanded(child: WorkspaceTree()),
          _buildLeftFooter(),
        ],
      ),
    );
  }

  /// 左侧栏底部：设置按钮
  Widget _buildLeftFooter() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(CommonConstants.borderColorValue)),
        ),
      ),
      child: Tooltip(
        message: '设置',
        child: InkWell(
          borderRadius: BorderRadius.circular(CommonConstants.buttonRadius),
          onTap: _showSettingsDialog,
          splashColor: CommonConstants.primaryOverlay(0.08),
          highlightColor: CommonConstants.primaryOverlay(0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: CommonConstants.buttonIconSize,
                  color: Color(CommonConstants.textSecondaryColorValue),
                ),
                const SizedBox(width: 8),
                Text(
                  '设置',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(CommonConstants.textSecondaryColorValue),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 设置对话框：修改工作空间路径
  Future<void> _showSettingsDialog() async {
    final workspaceStore = context.read<WorkspaceStore>();
    final tabStore = context.read<TabStore>();

    final newPath = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final controller = TextEditingController(
          text: workspaceStore.workspacePath,
        );
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text(
              '设置',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '工作空间路径',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Color(CommonConstants.textSecondaryColorValue),
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          readOnly: true,
                          decoration: InputDecoration(
                            hintText: '选择工作空间目录...',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Color(CommonConstants.borderColorValue),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Color(CommonConstants.borderColorValue),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Theme.of(ctx).colorScheme.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final selected =
                              await FilePicker.platform.getDirectoryPath(
                            dialogTitle: '选择工作空间目录',
                            initialDirectory: workspaceStore.workspacePath,
                          );
                          if (selected != null) {
                            controller.text = selected;
                            setDialogState(() {});
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Theme.of(ctx).colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('选择'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '切换工作空间后会清空当前已打开的所有标签页。',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Color(CommonConstants.textSecondaryColorValue),
                        ),
                  ),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Color(CommonConstants.textPrimaryColorValue),
                  side: BorderSide(color: Color(CommonConstants.borderColorValue)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    );

    if (newPath == null || newPath.isEmpty) return;
    if (newPath == workspaceStore.workspacePath) return;

    try {
      await workspaceStore.configureWorkspace(newPath);
      // 切换工作空间：关闭所有标签，内容对不上了
      tabStore.closeAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('工作空间已切换到：$newPath'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('切换工作空间失败: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 1,
      color: Color(CommonConstants.borderColorValue),
    );
  }

  Widget _buildRightPanel() {
    return Column(
      children: [
        const DocumentTabs(),
        Container(
          height: 1,
          color: Color(CommonConstants.borderColorValue),
        ),
        const Expanded(child: RequestResponsePanel()),
      ],
    );
  }
}

/// 外部链接按钮组（DP + GitHub）
class _ExternalLinks extends StatelessWidget {
  const _ExternalLinks();

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // DP 图标
        Tooltip(
          message: 'DP 官网',
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => _openUrl('https://www.deepseek.com'),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Image.asset(
                'images/deepseek.webp',
                width: 16,
                height: 16,
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        // GitHub 图标
        Tooltip(
          message: 'GitHub 仓库',
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => _openUrl('https://github.com/jyh-jy/JsonLayer'),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Image.asset(
                'images/github.webp',
                width: 16,
                height: 16,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// 自定义窗口控制按钮（最小化 / 最大化 / 关闭）。
class _WindowControls extends StatefulWidget {
  const _WindowControls();

  @override
  State<_WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<_WindowControls> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        WindowCaptionButton.minimize(
          brightness: Brightness.light,
          onPressed: () => windowManager.minimize(),
        ),
        _isMaximized
            ? WindowCaptionButton.unmaximize(
                brightness: Brightness.light,
                onPressed: () => windowManager.unmaximize(),
              )
            : WindowCaptionButton.maximize(
                brightness: Brightness.light,
                onPressed: () => windowManager.maximize(),
              ),
        WindowCaptionButton.close(
          brightness: Brightness.light,
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }
}
