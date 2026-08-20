import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:json_layer/contants/CommonConstant.dart' show CommonConstants;
import 'package:json_layer/pages/home/HomePage.dart';
import 'package:json_layer/pages/welcome/WelcomePage.dart';
import 'package:json_layer/routes/index.dart';
import 'package:json_layer/services/FileWorkspaceService.dart';
import 'package:json_layer/services/WorkspaceService.dart';
import 'package:json_layer/stores/EditorStore.dart';
import 'package:json_layer/stores/TabStore.dart';
import 'package:json_layer/stores/ThemeStore.dart' show ThemeStore, kFixedBackgroundAsset, SkinMode;
import 'package:json_layer/stores/WorkspaceStore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  // 提前初始化 ThemeStore，MaterialApp 启动时就能拿到 themeMode
  final themeStore = ThemeStore();
  await themeStore.loadFromPrefs();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(900, 600),
    center: true,
    title: CommonConstants.appName,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(JsonLayerApp(themeStore: themeStore));
}

class JsonLayerApp extends StatelessWidget {
  final ThemeStore themeStore;

  const JsonLayerApp({super.key, required this.themeStore});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasConfiguredWorkspace(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: themeStore.lightTheme(),
            home: const _LoadingScreen(),
          );
        }

        final hasWorkspace = snapshot.data!;
        final service = FileWorkspaceService();
        final workspaceStore = WorkspaceStore(service);
        final tabStore = TabStore();
        final editorStore = EditorStore();

        if (hasWorkspace) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            workspaceStore.loadFromPrefs();
          });
        }

        return MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeStore>.value(value: themeStore),
            ChangeNotifierProvider<WorkspaceStore>.value(value: workspaceStore),
            ChangeNotifierProvider<TabStore>.value(value: tabStore),
            ChangeNotifierProvider<EditorStore>.value(value: editorStore),
            Provider<WorkspaceService>.value(value: service),
          ],
          child: Consumer<ThemeStore>(
            builder: (context, store, child) {
              return _SkinBackgroundWrapper(
                store: store,
                child: MaterialApp(
                  title: appTitle,
                  debugShowCheckedModeBanner: false,
                  theme: store.lightTheme(),
                  darkTheme: store.darkTheme(),
                  themeMode: store.themeMode,
                  home: hasWorkspace ? const HomePage() : const WelcomePage(),
                  onGenerateRoute: (settings) {
                    if (settings.name == '/home') {
                      return MaterialPageRoute(builder: (_) => const HomePage());
                    }
                    if (settings.name == '/welcome') {
                      return MaterialPageRoute(builder: (_) => const WelcomePage());
                    }
                    return null;
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<bool> _hasConfiguredWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(CommonConstants.workspacePathKey);
    return path != null && path.isNotEmpty;
  }
}

/// 在 MaterialApp 外层（它自己的 Scaffold 背景层之上 + 窗口之下）绘制
/// 背景图。
/// - SkinMode.light → 纯色 0xFFF5F6F8；
/// - SkinMode.builtInBg → 内置 $kFixedBackgroundAsset 整窗原样展示；
/// - SkinMode.customBg → 用户上传的图整窗展示；文件不存在/读失败时回退到内置 $kFixedBackgroundAsset。
class _SkinBackgroundWrapper extends StatelessWidget {
  final ThemeStore store;
  final Widget child;

  const _SkinBackgroundWrapper({
    required this.store,
    required this.child,
  });

  /// 背景层：根据皮肤模式返回对应背景。任何图片加载失败都回退到纯色。
  Widget _buildBackground() {
    final skin = store.skinMode;
    switch (skin) {
      case SkinMode.light:
        // 亮色模式：真实不透明底色（不用 lightTheme.scaffoldBackgroundColor，
        // 它在 ThemeStore 里被故意设成 Colors.transparent 了）
        return Container(color: Color(CommonConstants.backgroundColorValue));

      case SkinMode.builtInBg:
        return _buildBuiltInBg();

      case SkinMode.customBg:
        final customPath = store.customBackgroundPath;
        if (customPath == null || customPath.isEmpty) {
          return _buildBuiltInBg();
        }
        // 自定义文件无法解码（损坏/格式不支持）→ 回退内置图
        return Image.file(
          File(customPath),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, err, stack) => _buildBuiltInBg(),
        );
    }
  }

  /// 内置背景 $kFixedBackgroundAsset；资源加载失败时回退纯色。
  Widget _buildBuiltInBg() {
    return Image.asset(
      kFixedBackgroundAsset,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, err, stack) =>
          Container(color: Color(CommonConstants.backgroundColorValue)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 关键：根节点始终是同一个 [Stack] 类型，只切换背景层。
    // 若根节点类型随皮肤模式在 Container / Stack 之间切换，会导致其子树
    // （含 MaterialApp、Navigator、Theme 等）被整体卸载重建，触发
    // "_dependents.isEmpty" / "wrong build scope" 断言崩溃。
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.topLeft,
      children: [
        _buildBackground(),
        child,
      ],
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'images/JsonLayer.png',
              width: 80,
              height: 80,
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              '正在加载 $appTitle ...',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
