import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:json_layer/contants/CommonConstant.dart';

/// 皮肤类型
enum SkinMode {
  light, // 亮色模式
  dark, // 暗色模式
  customBg, // 亮色调 + 自定义背景图
}

/// 皮肤 & 主题状态管理。
///
/// 使用 Flutter 内置的 ColorScheme.fromSeed 生成 Indigo 主色系的
/// 亮/暗两套主题，不引入三方配色依赖，保证版本兼容性。
class ThemeStore extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  SkinMode _skinMode = SkinMode.light;
  String? _customBackgroundPath;

  ThemeMode get themeMode => _themeMode;
  SkinMode get skinMode => _skinMode;
  String? get customBackgroundPath => _customBackgroundPath;
  bool get hasCustomBackground =>
      _customBackgroundPath != null &&
      _customBackgroundPath!.isNotEmpty &&
      File(_customBackgroundPath!).existsSync();

  // --------------------------- 生命周期 ---------------------------

  /// 启动时从 SharedPreferences 恢复用户选择
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final skinIndex = prefs.getInt('skin_mode') ?? SkinMode.light.index;
    final bgPath = prefs.getString('custom_bg_path');

    switch (SkinMode.values.elementAtOrNull(skinIndex) ?? SkinMode.light) {
      case SkinMode.light:
        _themeMode = ThemeMode.light;
        _skinMode = SkinMode.light;
        break;
      case SkinMode.dark:
        _themeMode = ThemeMode.dark;
        _skinMode = SkinMode.dark;
        break;
      case SkinMode.customBg:
        _themeMode = ThemeMode.light; // 自定义背景 + 浅色调内容
        _skinMode = SkinMode.customBg;
        _customBackgroundPath = bgPath;
        break;
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('skin_mode', _skinMode.index);
    if (_customBackgroundPath != null) {
      await prefs.setString('custom_bg_path', _customBackgroundPath!);
    } else {
      await prefs.remove('custom_bg_path');
    }
  }

  // --------------------------- 通用主题辅助 ---------------------------

  ThemeData _baseTheme(Brightness brightness) {
    const seed = Color(CommonConstants.primaryColorValue); // 0xFF6366F1 (Indigo)
    final cs = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final textBase = (brightness == Brightness.light)
        ? const Color(0xFF111827)
        : const Color(0xFFF3F4F6);
    final textMuted = (brightness == Brightness.light)
        ? const Color(0xFF6B7280)
        : const Color(0xFF9CA3AF);
    final border = (brightness == Brightness.light)
        ? const Color(0xFFE5E7EB)
        : const Color(0xFF374151);
    final surface = (brightness == Brightness.light)
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF1F2937);
    final background = (brightness == Brightness.light)
        ? const Color(0xFFF5F6F8)
        : const Color(0xFF111827);
    final appBarBg = (brightness == Brightness.light)
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF111827);

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: Colors.transparent, // 由外部 _SkinBackgroundWrapper 负责背景
      canvasColor: surface,
      fontFamily: 'Microsoft YaHei UI',
      primaryColor: cs.primary,
      dividerColor: border,
      visualDensity: VisualDensity.compact,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: appBarBg,
        foregroundColor: textBase,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
        titleTextStyle: TextStyle(
          color: textBase,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.primary, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.error, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.error),
        ),
        hintStyle: TextStyle(color: textMuted, fontSize: 13),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
        elevation: 3,
        textStyle: TextStyle(fontSize: 13, color: textBase),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textBase,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelColor: cs.primary,
        labelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelColor: textMuted,
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        overlayColor:
            WidgetStatePropertyAll(cs.primary.withValues(alpha: 0.08)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textBase,
        contentTextStyle: TextStyle(color: background),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        iconColor: textMuted,
        textColor: textBase,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: textBase.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: TextStyle(color: background, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        preferBelow: true,
        waitDuration: const Duration(milliseconds: 400),
      ),
      textTheme: TextTheme(
        bodyMedium: TextStyle(color: textBase, fontSize: 13, height: 1.45),
        bodySmall: TextStyle(color: textMuted, fontSize: 12, height: 1.4),
        titleSmall: TextStyle(
          color: textBase,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: textBase,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: textBase,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: TextStyle(color: textMuted, fontSize: 12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: cs.primary,
        linearTrackColor: border,
      ),
    );
  }

  // --------------------------- 主题数据 ---------------------------

  /// 亮色 [ThemeData]（APIFOX 风格 Indigo 主色）
  ThemeData lightTheme() => _baseTheme(Brightness.light);

  /// 暗色 [ThemeData]（同主色系深背景）
  ThemeData darkTheme() => _baseTheme(Brightness.dark);

  // --------------------------- 外部接口 ---------------------------

  /// 切换到亮色模式
  void switchToLight() {
    _skinMode = SkinMode.light;
    _themeMode = ThemeMode.light;
    notifyListeners();
    _persist();
  }

  /// 切换到暗色模式
  void switchToDark() {
    _skinMode = SkinMode.dark;
    _themeMode = ThemeMode.dark;
    notifyListeners();
    _persist();
  }

  /// 设置自定义背景图
  ///
  /// 会把选中的文件复制到应用目录，下次启动直接加载。
  Future<void> setCustomBackground(String sourcePath) async {
    final dir = await getApplicationSupportDirectory();
    final targetBase = '${dir.path}${Platform.pathSeparator}custom_bg';
    final ext = sourcePath.contains('.')
        ? sourcePath.substring(sourcePath.lastIndexOf('.'))
        : '.png';
    final dest = '$targetBase$ext';
    final file = File(sourcePath);
    if (!file.existsSync()) return;

    // 清理旧背景文件
    if (_customBackgroundPath != null &&
        _customBackgroundPath != dest &&
        File(_customBackgroundPath!).existsSync()) {
      try {
        File(_customBackgroundPath!).deleteSync();
      } catch (_) {}
    }
    await file.copy(dest);

    _skinMode = SkinMode.customBg;
    _themeMode = ThemeMode.light;
    _customBackgroundPath = dest;
    notifyListeners();
    await _persist();
  }

  /// 手动刷新 UI
  void refresh() => notifyListeners();

  /// 清除自定义背景，回落为亮色模式
  void clearCustomBackground() {
    if (_customBackgroundPath != null &&
        File(_customBackgroundPath!).existsSync()) {
      try {
        File(_customBackgroundPath!).deleteSync();
      } catch (_) {}
    }
    _customBackgroundPath = null;
    switchToLight();
  }
}
