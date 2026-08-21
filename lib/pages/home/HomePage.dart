import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'package:json_layer/components/common/DialogActions.dart';
import 'package:json_layer/components/common/EditorActionButton.dart';
import 'package:json_layer/components/common/HoverBuilder.dart';
import 'package:json_layer/components/common/SafeSnackBar.dart';
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

  /// 全局 Ctrl+S 保存：将当前激活标签的数据写回磁盘。
  ///
  /// 通过 [CallbackShortcuts] 在整棵 HomePage 子树上注册，
  /// 无论焦点在左侧树、标签栏、编辑区、顶栏还是空白区域，都能直接保存，
  /// 不再需要先点击中间的内容区。
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
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    // 全局 Ctrl+S：用 CallbackShortcuts（基于 Flutter 的 Shortcuts/Actions 机制）
    // 比 Focus.onKeyEvent 冒泡更可靠 — Shortcuts 的匹配是对**整个焦点所在
    // 的 widget 子树**生效，焦点在哪儿都能命中。
    const saveShortcut =
        SingleActivator(LogicalKeyboardKey.keyS, control: true);
    return Scaffold(
      backgroundColor: Colors.transparent, // 由外部 _SkinBackgroundWrapper 负责背景（亮色纯色/自定义图片）
      body: CallbackShortcuts(
        bindings: {saveShortcut: _saveActiveTab},
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
    return Consumer<ThemeStore>(
      builder: (context, themeStore, _) {
        final hasBg = themeStore.hasAnyBackground;
        final bar = Container(
          height: CommonConstants.toolbarHeight,
          color: hasBg
              ? Color(CommonConstants.surfaceColorValue)
                  .withValues(alpha: CommonConstants.glassToolbarAlpha)
              : Color(CommonConstants.surfaceColorValue),
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
        if (!hasBg) return bar;
        // 有背景图（内置或自定义）：给顶栏叠加毛玻璃，文字清晰且背景图能透出。
        // bar 必须保持半透明，否则模糊层被完全遮住。
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

  Widget _buildLeftPanel() {
    return Consumer<ThemeStore>(
      builder: (context, themeStore, _) {
        final hasBg = themeStore.hasAnyBackground;
        final panel = Container(
          width: CommonConstants.leftNavWidth,
          color: hasBg
              ? Color(CommonConstants.sidebarColorValue)
                  .withValues(alpha: CommonConstants.glassSidebarAlpha)
              : Color(CommonConstants.sidebarColorValue),
          child: Column(
            children: [
              const Expanded(child: WorkspaceTree()),
              _buildLeftFooter(),
            ],
          ),
        );
        if (!hasBg) return panel;
        // 有背景图：左侧栏叠加毛玻璃
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: CommonConstants.glassBlurSigma,
              sigmaY: CommonConstants.glassBlurSigma,
            ),
            child: panel,
          ),
        );
      },
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
      child: HoverBuilder(
        builder: (context, isHovered) {
          // 整行都是热区，悬停时图标与文字一起染成主色
          final foreground = isHovered
              ? Color(CommonConstants.primaryColorValue)
              : Color(CommonConstants.textSecondaryColorValue);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _showSettingsDialog,
            child: AnimatedContainer(
              duration: CommonConstants.hoverAnimation,
              curve: Curves.easeOut,
              color: isHovered
                  ? CommonConstants.primaryOverlay(
                      CommonConstants.rowHoverAlpha,
                    )
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  AnimatedRotation(
                    // 齿轮转一点点，是这个按钮最自然的悬停语言
                    turns: isHovered ? 0.125 : 0,
                    duration: CommonConstants.hoverAnimation,
                    curve: Curves.easeOut,
                    child: Icon(
                      Icons.settings_outlined,
                      size: CommonConstants.buttonIconSize,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '设置',
                    style: TextStyle(
                      fontSize: CommonConstants.menuFontSize,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
    // 待使用的自定义背景图路径（仅用户刚选了图、尚未保存时非空）
    // 如果 pendingSkinMode == customBg 但 pendingCustomBgFile 为空，
    // 则使用 store 中已存在的用户图（若 store 也没有则提示用户先选一张）
    String? pendingCustomBgFile = themeStore.customBackgroundPath;

    // 提示词框框预设内容：从 SharedPreferences 读取
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // 提示词当前值由 _PromptField 通过 onChanged 回写，避免在对话框退出
    // 动画期间持有/销毁 TextEditingController（会导致"used after dispose"崩溃）。
    String pendingPrompt =
        prefs.getString(CommonConstants.presetPromptKey) ??
        CommonConstants.defaultPresetPrompt;

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
                          SingleChildScrollView(
                            child: Column(
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
                              const SizedBox(height: 20),
                              // ----- 提示词框框 -----
                              Text(
                                '提示词',
                                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                      color: Color(
                                        CommonConstants
                                            .textSecondaryColorValue,
                                      ),
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              _PromptField(
                                initialValue: pendingPrompt,
                                onChanged: (v) => pendingPrompt = v,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '配合 JSON 模式工具栏的"生成提示词"按钮 + 顶栏 DeepSeek 入口，可一键复制并打开官网提问。',
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
                                // ----- 内置背景预览（builtInBg 时显示）-----
                                if (pendingSkinMode == SkinMode.builtInBg) ...[
                                  Text(
                                    '内置背景',
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
                                      child: Image.asset(
                                        kFixedBackgroundAsset,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        errorBuilder: (_, _, _) =>
                                          Container(
                                            width: double.infinity,
                                            alignment: Alignment.center,
                                            color: Theme.of(ctx)
                                                .colorScheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.25),
                                            child: Text(
                                              '内置背景图 $kFixedBackgroundAsset',
                                              style: Theme.of(ctx)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Color(CommonConstants
                                                        .textSecondaryColorValue),
                                                  ),
                                            ),
                                          ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '使用项目内置的固定背景图（$kFixedBackgroundAsset），无需上传。',
                                    style:
                                        Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                              color: Color(
                                                CommonConstants
                                                    .textSecondaryColorValue,
                                              ),
                                            ),
                                  ),
                                ],
                                // ----- 自定义背景（customBg：支持用户上传 + 预览）-----
                                if (pendingSkinMode == SkinMode.customBg) ...[
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
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          height: 150,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Color(
                                                CommonConstants
                                                    .borderColorValue,
                                              ),
                                            ),
                                          ),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(7),
                                            child: Builder(
                                              builder: (context) {
                                                final p =
                                                    pendingCustomBgFile;
                                                if (p != null &&
                                                    p.isNotEmpty &&
                                                    File(p).existsSync()) {
                                                  return Image.file(
                                                    File(p),
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    errorBuilder:
                                                        (_, _, _) =>
                                                            Container(
                                                      alignment:
                                                          Alignment.center,
                                                      color: Theme.of(ctx)
                                                          .colorScheme
                                                          .error
                                                          .withValues(alpha: 0.08),
                                                      child: Text(
                                                        '图片无法读取，请重新选择',
                                                        style: Theme.of(ctx)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: Color(CommonConstants
                                                                  .textSecondaryColorValue),
                                                            ),
                                                      ),
                                                    ),
                                                  );
                                                }
                                                return Container(
                                                  width: double.infinity,
                                                  alignment: Alignment.center,
                                                  color: Theme.of(ctx)
                                                      .colorScheme
                                                      .surfaceContainerHighest
                                                      .withValues(alpha: 0.2),
                                                  child: Text(
                                                    '还未选择图片，点击右侧"选择图片"上传',
                                                    style: Theme.of(ctx)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: Color(CommonConstants
                                                              .textSecondaryColorValue),
                                                        ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          FilledButton.tonalIcon(
                                            onPressed: () async {
                                              final result = await FilePicker
                                                  .platform
                                                  .pickFiles(
                                                dialogTitle: '选择背景图片',
                                                type: FileType.image,
                                                allowMultiple: false,
                                              );
                                              final picked =
                                                  result?.files.single.path;
                                              if (picked != null &&
                                                  picked.isNotEmpty) {
                                                pendingCustomBgFile = picked;
                                                setDialogState(() {});
                                              }
                                            },
                                            icon: const Icon(
                                                Icons.image_search_outlined,
                                                size: 15),
                                            label: const Text('选择图片'),
                                          ),
                                          if (pendingCustomBgFile != null) ...[
                                            const SizedBox(height: 8),
                                            OutlinedButton.icon(
                                              onPressed: () {
                                                pendingCustomBgFile = null;
                                                setDialogState(() {});
                                              },
                                              icon: const Icon(
                                                  Icons.remove_circle_outline,
                                                  size: 15),
                                              label: const Text('清除'),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '点击"选择图片"上传本地图片作为应用背景（保存后生效，仅支持常见图片格式）。',
                                    style:
                                        Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                              color: Color(
                                                CommonConstants
                                                    .textSecondaryColorValue,
                                              ),
                                            ),
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
                DialogActions(
                  confirmLabel: '保存',
                  onConfirm: () async {
                    // ---- 应用皮肤 ----
                    switch (pendingSkinMode) {
                      case SkinMode.light:
                        themeStore.switchToLight();
                        break;
                      case SkinMode.builtInBg:
                        themeStore.switchToBuiltInBg();
                        break;
                      case SkinMode.customBg:
                        // 自定义背景：必须有一张可用的图（已选或 store 已有）
                        final bgFile = pendingCustomBgFile;
                        if (bgFile == null ||
                            bgFile.isEmpty ||
                            !File(bgFile).existsSync()) {
                          Navigator.pop(ctx);
                          if (mounted) {
                            SafeSnackBar.show(
                              context,
                              message: '请先选择一张图片作为自定义背景',
                              idempotencyKey: 'bg_no_image',
                              backgroundColor:
                                  Theme.of(context).colorScheme.error,
                              behavior: SnackBarBehavior.floating,
                            );
                          }
                          return;
                        }
                        final ok =
                            await themeStore.switchToCustomBackground(bgFile);
                        if (!ok && mounted) {
                          SafeSnackBar.show(
                            context,
                            message: '自定义背景保存失败，请检查图片是否可访问',
                            idempotencyKey: 'bg_save_error',
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                            behavior: SnackBarBehavior.floating,
                          );
                        }
                        break;
                    }
                    if (ctx.mounted) Navigator.pop(ctx);

                    // ---- 保存提示词 ----
                    await prefs.setString(
                      CommonConstants.presetPromptKey,
                      pendingPrompt.trim(),
                    );

                    // ---- 应用工作空间 ----
                    if (pendingWorkspacePath !=
                        workspaceStore.workspacePath) {
                      try {
                        await workspaceStore
                            .configureWorkspace(pendingWorkspacePath);
                        tabStore.closeAll();
                        if (mounted) {
                          SafeSnackBar.show(
                            context,
                            message: '工作空间已切换到：$pendingWorkspacePath',
                            idempotencyKey: 'workspace_switched',
                            behavior: SnackBarBehavior.floating,
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          SafeSnackBar.show(
                            context,
                            message: '切换工作空间失败: $e',
                            idempotencyKey: 'workspace_switch_failed',
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                            behavior: SnackBarBehavior.floating,
                          );
                        }
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 三种皮肤模式的横向卡片选择：亮色 | 内置背景 | 自定义背景（用户上传）
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
          mode: SkinMode.builtInBg,
          title: '内置背景',
          desc: '内置 $kFixedBackgroundAsset 背景图',
          bg: const Color(0xFFF5F3FF),
          fg: const Color(0xFF6D28D9),
          icon: Icons.photo_library_outlined,
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
    return Consumer<ThemeStore>(
      builder: (context, themeStore, _) {
        final hasBg = themeStore.hasAnyBackground;
        return Container(
          width: 1,
          color: hasBg
              ? Color(CommonConstants.borderColorValue).withValues(alpha: 0.5)
              : Color(CommonConstants.borderColorValue),
        );
      },
    );
  }

  Widget _buildRightPanel() {
    return Consumer<ThemeStore>(
      builder: (context, themeStore, _) {
        final hasBg = themeStore.hasAnyBackground;
        return Column(
          children: [
            const DocumentTabs(),
            Container(
              height: 1,
              color: hasBg
                  ? Color(CommonConstants.borderColorValue).withValues(alpha: 0.5)
                  : Color(CommonConstants.borderColorValue),
            ),
            const Expanded(child: RequestResponsePanel()),
          ],
        );
      },
    );
  }
}

/// 设置对话框里的提示词输入框。
///
/// 自己持有 [TextEditingController] 并在自身 dispose 时释放，避免控制器被
/// 对话框外部的状态（`_showSettingsDialog`）提前 dispose，导致对话框退出动画
/// 期间重建 `TextField` 时触发 "TextEditingController was used after being
/// disposed" 崩溃。
class _PromptField extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onChanged;

  const _PromptField({
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_PromptField> createState() => _PromptFieldState();
}

class _PromptFieldState extends State<_PromptField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    return TextField(
      controller: _controller,
      maxLines: 5,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: '可留空。设置后，点击 JSON 模式工具栏的"生成提示词"按钮，会自动将此处提示词 + JSON 内容一起复制到剪贴板',
        isDense: true,
        alignLabelWithHint: true,
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

  static const double _logoSize = 16;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        EditorActionButton(
          tooltip: 'DP 官网',
          color: Color(CommonConstants.actionPromptColorValue),
          onTap: () => _openUrl('https://www.deepseek.com'),
          child: Image.asset(
            'images/deepseek.webp',
            width: _logoSize,
            height: _logoSize,
          ),
        ),
        EditorActionButton(
          tooltip: 'GitHub 仓库',
          color: Color(CommonConstants.textPrimaryColorValue),
          onTap: () => _openUrl('https://github.com/jyh-jy/JsonLayer'),
          child: Image.asset(
            'images/github.webp',
            width: _logoSize,
            height: _logoSize,
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
