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
import 'package:json_layer/stores/WorkspaceStore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(900, 600),
    center: true,
    title: CommonConstants.appName,
    backgroundColor: Color(0xFFF5F6F8),
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const JsonLayerApp());
}

class JsonLayerApp extends StatelessWidget {
  const JsonLayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasConfiguredWorkspace(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _AppShell(home: _LoadingScreen());
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

        return _AppShell(
          home: hasWorkspace ? const HomePage() : const WelcomePage(),
          workspaceStore: workspaceStore,
          tabStore: tabStore,
          editorStore: editorStore,
          service: service,
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

class _AppShell extends StatelessWidget {
  final Widget home;
  final WorkspaceStore? workspaceStore;
  final TabStore? tabStore;
  final EditorStore? editorStore;
  final WorkspaceService? service;

  const _AppShell({
    required this.home,
    this.workspaceStore,
    this.tabStore,
    this.editorStore,
    this.service,
  });

  @override
  Widget build(BuildContext context) {
    final child = MaterialApp(
      title: appTitle,
      debugShowCheckedModeBanner: false,
      theme: getRootTheme(Brightness.light),
      darkTheme: getRootTheme(Brightness.dark),
      home: home,
      onGenerateRoute: (settings) {
        if (settings.name == '/home') {
          return MaterialPageRoute(builder: (_) => const HomePage());
        }
        if (settings.name == '/welcome') {
          return MaterialPageRoute(builder: (_) => const WelcomePage());
        }
        return null;
      },
    );

    if (workspaceStore == null) {
      return child;
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<WorkspaceStore>.value(value: workspaceStore!),
        ChangeNotifierProvider<TabStore>.value(value: tabStore!),
        ChangeNotifierProvider<EditorStore>.value(value: editorStore!),
        Provider<WorkspaceService>.value(value: service!),
      ],
      child: child,
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
