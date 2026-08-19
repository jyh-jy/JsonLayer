import 'dart:io';

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
import 'package:json_layer/stores/ThemeStore.dart';
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

  /// 设置对话框：Tab 切换（工作空间 / 外观）
  Future<void> _showSettingsDialog() async {
    final workspaceStore = context.read<WorkspaceStore>();
    final themeStore = context.read<ThemeStore>();
    final tabStore = context.read<TabStore>();

    // 缓存工作空间/皮肤的"修改后"状态，点保存才真正写回 store
    String pendingWorkspacePath = workspaceStore.workspacePath;
    SkinMode pendingSkinMode = themeStore.skinMode;
    String? pendingBgPath = themeStore.customBackgroundPath;
    bool dirtyBg = false;
    String? pendingBgSourcePath;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final workspaceController = TextEditingController(
          text: pendingWorkspacePath,
        );
        return DefaultTabController(
          length: 2,
          child: StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              title: const Text(
                '设置',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              content: SizedBox(
                width: 600,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ---- Tab 栏 ----
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: TabBar(
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        indicator: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.surface,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        labelColor:
                            Theme.of(ctx).colorScheme.onSurface,
                        labelStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        unselectedLabelColor: Color(
                          CommonConstants.textSecondaryColorValue,
                        ),
                        unselectedLabelStyle: const TextStyle(fontSize: 13),
                        tabs: const [
                          Tab(text: '工作空间'),
                          Tab(text: '外观'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ---- Tab 内容 ----
                    SizedBox(
                      height: 320,
                      child: TabBarView(
                        children: [
                          // ============ Tab 1: 工作空间 ============
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '工作空间路径',
                                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                      color: Color(
                                        CommonConstants.textSecondaryColorValue,
                                      ),
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: workspaceController,
                                      readOnly: true,
                                      decoration: InputDecoration(
                                        hintText: '选择工作空间目录...',
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                            color: Color(
                                              CommonConstants
                                                  .borderColorValue,
                                            ),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                            color: Color(
                                              CommonConstants
                                                  .borderColorValue,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                            color: Theme.of(ctx)
                                                .colorScheme
                                                .primary,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.tonalIcon(
                                    onPressed: () async {
                                      final selected = await FilePicker.platform
                                          .getDirectoryPath(
                                        dialogTitle: '选择工作空间目录',
                                        initialDirectory:
                                            workspaceStore.workspacePath,
                                      );
                                      if (selected != null) {
                                        pendingWorkspacePath = selected;
                                        workspaceController.text = selected;
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
                                    icon:
                                        const Icon(Icons.folder_open, size: 16),
                                    label: const Text('选择'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '切换工作空间后会清空当前已打开的所有标签页。',
                                style:
                                    Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                          color: Color(
                                            CommonConstants
                                                .textSecondaryColorValue,
                                          ),
                                        ),
                              ),
                            ],
                          ),
                          // ============ Tab 2: 外观 ============
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '皮肤模式',
                                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                        color: Color(
                                          CommonConstants
                                              .textSecondaryColorValue,
                                        ),
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                _buildSkinOptionRow(
                                  ctx,
                                  selected: pendingSkinMode,
                                  onChange: (mode) {
                                    pendingSkinMode = mode;
                                    setDialogState(() {});
                                  },
                                ),
                                const SizedBox(height: 20),
                                // 自定义背景区域（在自定义模式+上传后，或已经有自定义路径时才显示预览）
                                if (pendingSkinMode == SkinMode.customBg ||
                                    (pendingBgPath != null &&
                                        pendingBgPath!.isNotEmpty)) ...[
                                  Text(
                                    '自定义背景',
                                    style: Theme.of(ctx)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Color(
                                            CommonConstants
                                                .textSecondaryColorValue,
                                          ),
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    height: 150,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Color(
                                          CommonConstants.borderColorValue,
                                        ),
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(7),
                                      child: () {
                                        final source =
                                            pendingBgSourcePath ?? pendingBgPath;
                                        if (source != null &&
                                            File(source).existsSync()) {
                                          return Image.file(
                                            File(source),
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                          );
                                        }
                                        return Container(
                                          width: double.infinity,
                                          alignment: Alignment.center,
                                          color: Theme.of(ctx)
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.25),
                                          child: Text(
                                            '还未选择图片',
                                            style: Theme.of(ctx)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Color(CommonConstants
                                                      .textSecondaryColorValue),
                                                ),
                                          ),
                                        );
                                      }(),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () async {
                                            final picked = await FilePicker
                                                .platform
                                                .pickFiles(
                                              dialogTitle: '选择背景图',
                                              type: FileType.image,
                                              allowMultiple: false,
                                            );
                                            if (picked == null ||
                                                picked.files.isEmpty) {
                                              return;
                                            }
                                            final p = picked.files.single.path;
                                            if (p == null) {
                                              return;
                                            }
                                            pendingBgSourcePath = p;
                                            pendingSkinMode =
                                                SkinMode.customBg;
                                            dirtyBg = true;
                                            setDialogState(() {});
                                          },
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(
                                              color: Color(CommonConstants
                                                  .borderColorValue),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          icon: const Icon(
                                              Icons.image_outlined, size: 16),
                                          label: const Text('选择图片'),
                                        ),
                                      ),
                                      if (dirtyBg ||
                                          (pendingBgPath != null &&
                                              pendingBgPath!
                                                  .isNotEmpty)) ...[
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            pendingBgSourcePath = null;
                                            pendingBgPath = null;
                                            dirtyBg = false;
                                            if (pendingSkinMode ==
                                                SkinMode.customBg) {
                                              pendingSkinMode = SkinMode.light;
                                            }
                                            setDialogState(() {});
                                          },
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: const Color(
                                                0xFFDC2626),
                                            side: const BorderSide(
                                                color: Color(0xFFFCA5A5)),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          icon: const Icon(Icons.delete_outline,
                                              size: 16),
                                          label: const Text('清除背景'),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Color(
                      CommonConstants.textPrimaryColorValue,
                    ),
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
                    backgroundColor: Theme.of(ctx).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    // ---- 应用皮肤 ----
                    switch (pendingSkinMode) {
                      case SkinMode.light:
                        themeStore.switchToLight();
                        break;
                      case SkinMode.dark:
                        themeStore.switchToDark();
                        break;
                      case SkinMode.customBg:
                        if (dirtyBg && pendingBgSourcePath != null) {
                          try {
                            await themeStore
                                .setCustomBackground(pendingBgSourcePath!);
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('背景图保存失败: $e'),
                                  backgroundColor:
                                      Theme.of(context).colorScheme.error,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        } else if (pendingBgPath != null &&
                            pendingBgPath!.isNotEmpty) {
                          // 仅皮肤模式恢复到 customBg（比如用户切到 custom 没换图）
                          if (themeStore.skinMode != SkinMode.customBg) {
                            themeStore.refresh();
                          }
                        }
                        break;
                    }
                    // 用户手动清除了背景 → 回到亮色
                    if (pendingBgPath == null &&
                        pendingBgSourcePath == null &&
                        pendingSkinMode == SkinMode.light &&
                        themeStore.skinMode == SkinMode.customBg) {
                      themeStore.clearCustomBackground();
                    }

                    // ---- 应用工作空间 ----
                    if (pendingWorkspacePath !=
                        workspaceStore.workspacePath) {
                      try {
                        await workspaceStore
                            .configureWorkspace(pendingWorkspacePath);
                        tabStore.closeAll();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '工作空间已切换到：$pendingWorkspacePath'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('切换工作空间失败: $e'),
                              backgroundColor:
                                  Theme.of(context).colorScheme.error,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 三种皮肤模式的横向卡片选择
  Widget _buildSkinOptionRow(
    BuildContext ctx, {
    required SkinMode selected,
    required void Function(SkinMode) onChange,
  }) {
    Widget card({
      required SkinMode mode,
      required String title,
      required String desc,
      required Color bg,
      required Color fg,
      required IconData icon,
    }) {
      final isSelected = selected == mode;
      return Expanded(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onChange(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? Theme.of(ctx).colorScheme.primary
                      : Color(CommonConstants.borderColorValue),
                  width: isSelected ? 1.8 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Theme.of(ctx)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.14),
                          blurRadius: 0,
                          spreadRadius: 1.5,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        card(
          mode: SkinMode.light,
          title: '亮色模式',
          desc: '干净清爽，适合白天',
          bg: const Color(0xFFFFFFFF),
          fg: const Color(0xFF111827),
          icon: Icons.light_mode_outlined,
        ),
        const SizedBox(width: 10),
        card(
          mode: SkinMode.dark,
          title: '暗色模式',
          desc: '护眼沉浸，适合夜晚',
          bg: const Color(0xFF111827),
          fg: const Color(0xFFE5E7EB),
          icon: Icons.dark_mode_outlined,
        ),
        const SizedBox(width: 10),
        card(
          mode: SkinMode.customBg,
          title: '自定义背景',
          desc: '上传自己喜欢的图片',
          bg: const Color(0xFFEEF2FF),
          fg: const Color(0xFF4338CA),
          icon: Icons.photo_outlined,
        ),
      ],
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
