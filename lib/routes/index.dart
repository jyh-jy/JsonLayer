import 'package:flutter/material.dart';

import 'package:json_layer/contants/CommonConstant.dart';

/// 路由与主题统一管理。

/// 根组件：根据是否已配置工作空间决定进入欢迎页或主页。
Widget getRootWidget({required bool hasWorkspace}) {
  // 延迟导入以避免循环依赖
  if (hasWorkspace) {
    return const _HomeEntry();
  }
  return const _WelcomeEntry();
}

/// 全局主题（APIFOX 风格：Indigo 主色 + 现代化布局）
ThemeData getRootTheme(Brightness brightness) {
  final seedColor = Color(CommonConstants.primaryColorValue);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    fontFamily: 'Microsoft YaHei UI',
    scaffoldBackgroundColor: Color(CommonConstants.backgroundColorValue),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: Color(CommonConstants.surfaceColorValue),
      foregroundColor: Color(CommonConstants.textPrimaryColorValue),
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(
      color: Color(CommonConstants.borderColorValue),
      thickness: 1,
      space: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Color(CommonConstants.surfaceColorValue),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Color(CommonConstants.borderColorValue)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Color(CommonConstants.borderColorValue)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: seedColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(
        color: Color(CommonConstants.textPrimaryColorValue),
        fontSize: 13,
      ),
      bodySmall: TextStyle(
        color: Color(CommonConstants.textSecondaryColorValue),
        fontSize: 12,
      ),
      titleSmall: TextStyle(
        color: Color(CommonConstants.textPrimaryColorValue),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: Color(CommonConstants.textPrimaryColorValue),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
    visualDensity: VisualDensity.compact,
  );
}

const String appTitle = CommonConstants.appName;

// 内部占位组件，实际逻辑在 main.dart 中通过 Import 引入
class _HomeEntry extends StatelessWidget {
  const _HomeEntry();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _WelcomeEntry extends StatelessWidget {
  const _WelcomeEntry();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
