import 'package:flutter/material.dart';

/// 全局共享常量集中管理。
class CommonConstants {
  CommonConstants._();

  /// 应用名称
  static const String appName = 'JsonLayer';

  /// 工作空间子目录名
  static const String workspaceDirName = 'JsonLayer';

  /// 本地存储 key
  static const String workspacePathKey = 'workspace_path';

  /// 提示词框框预设内容存储 key
  static const String presetPromptKey = 'preset_prompt';

  /// JSON 默认缩进空格数
  static const int defaultIndentSpaces = 2;

  /// UI 常量
  static const double leftNavWidth = 240.0;
  static const double tabBarHeight = 40.0;
  static const double toolbarHeight = 40.0;
  static const double editorHeaderHeight = 32.0;

  /// 颜色常量（APIFOX 风格）
  static const int primaryColorValue = 0xFF6366F1; // Indigo
  static const int accentColorValue = 0xFF8B5CF6; // Violet
  static const int backgroundColorValue = 0xFFF5F6F8;
  static const int surfaceColorValue = 0xFFFFFFFF;
  static const int sidebarColorValue = 0xFFF7F8FA;
  static const int borderColorValue = 0xFFE5E7EB;
  static const int textPrimaryColorValue = 0xFF1F2937;
  static const int textSecondaryColorValue = 0xFF6B7280;

  /// JSON 语法高亮颜色（浅色主题，适配白色背景）
  static const int jsonKeyColorValue = 0xFF001080; // 键名：深蓝
  static const int jsonStringColorValue = 0xFFA31515; // 字符串：深红
  static const int jsonNumberColorValue = 0xFF098658; // 数字：绿
  static const int jsonBooleanColorValue = 0xFF0000FF; // 布尔：蓝
  static const int jsonNullColorValue = 0xFF6B7280; // null：灰
  static const int jsonPunctuationColorValue = 0xFF383A42; // 标点：深灰

  /// 按钮尺寸常量
  static const double buttonIconSize = 14.0;
  static const double buttonPadding = 4.0;
  static const double buttonRadius = 3.0;

  /// 菜单样式常量
  static const double menuItemHeight = 32.0;
  static const double menuItemPadding = 12.0;
  static const double menuBorderRadius = 8.0;
  static const double menuFontSize = 13.0;

  /// 获取主色透明度背景色（用于 hover/splash）
  static Color primaryOverlay(double alpha) =>
      Color(primaryColorValue).withValues(alpha: alpha);
}
