import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:json_layer/components/home/WorkspaceTree.dart';
import 'package:json_layer/components/home/DocumentTabs.dart';
import 'package:json_layer/components/home/RequestResponsePanel.dart';
import 'package:json_layer/contants/CommonConstant.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(CommonConstants.backgroundColorValue),
      body: Column(
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
          const _WindowControls(),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Container(
      width: CommonConstants.leftNavWidth,
      color: Color(CommonConstants.sidebarColorValue),
      child: const WorkspaceTree(),
    );
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
