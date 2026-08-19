import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:json_layer/contants/CommonConstant.dart';
import 'package:json_layer/pages/home/HomePage.dart';
import 'package:json_layer/pages/welcome/WelcomePage.dart';
import 'package:json_layer/routes/index.dart';
import 'package:json_layer/services/FileWorkspaceService.dart';
import 'package:json_layer/services/WorkspaceService.dart';
import 'package:json_layer/stores/EditorStore.dart';
import 'package:json_layer/stores/TabStore.dart';
import 'package:json_layer/stores/ThemeStore.dart';
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
/// 自定义背景图。只有 SkinMode.customBg 时显示，其他皮肤直接透明。
class _SkinBackgroundWrapper extends StatelessWidget {
  final ThemeStore store;
  final Widget child;

  const _SkinBackgroundWrapper({
    required this.store,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!store.hasCustomBackground) {
      // 无自定义图时直接用主题自带的背景色
      final bgColor = store.skinMode == SkinMode.dark
          ? store.darkTheme().scaffoldBackgroundColor
          : store.lightTheme().scaffoldBackgroundColor;
      return Container(color: bgColor, child: child);
    }
    final file = File(store.customBackgroundPath!);
    return Stack(
      fit: StackFit.expand,
      children: [
        // 底：背景图，整窗铺满
        Image.file(
          file,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, err, stack) =>
            Container(color: store.lightTheme().scaffoldBackgroundColor),
        ),
        // 一层柔和的暗化，保证面板对比度（不会影响视线，因为内容区面板本身不透明）
        Container(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.25),
        ),
        // 顶：整棵 app
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
