import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:json_layer/contants/CommonConstant.dart';

/// 固定背景图资源路径（随包内置，不可替换）
const String kFixedBackgroundAsset = 'images/bgPic.jpg';

/// 皮肤类型
enum SkinMode {
  light, // 亮色模式（纯色背景）
  builtInBg, // 亮色调 + 内置背景图（bgPic.jpg）
  customBg, // 亮色调 + 用户上传的自定义背景图
}

/// 皮肤 & 主题状态管理。
///
/// 使用 Flutter 内置的 ColorScheme.fromSeed 生成 Indigo 主色系的
/// 浅色主题，不引入三方配色依赖，保证版本兼容性。
class ThemeStore extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  SkinMode _skinMode = SkinMode.light;

  /// 用户上传的自定义背景图（应用支持目录下的绝对路径）。
  /// 仅 [SkinMode.customBg] 时才会使用；其他模式即使存在也不展示。
  String? _customBackgroundPath;

  ThemeMode get themeMode => _themeMode;
  SkinMode get skinMode => _skinMode;

  /// 是否为"用户上传背景图"模式（且对应文件真实存在）。
  bool get hasCustomBackground =>
      _skinMode == SkinMode.customBg && hasValidCustomBackgroundFile;

  /// 是否有内置背景图或自定义背景图（主窗口需要叠加背景图 + 毛玻璃时用）。
  bool get hasAnyBackground =>
      _skinMode == SkinMode.builtInBg || hasCustomBackground;

  /// 当前要展示的背景图文件路径（仅 customBg 模式、文件存在时非空）。
  String? get customBackgroundPath =>
      hasValidCustomBackgroundFile ? _customBackgroundPath : null;

  /// 用户图文件是否真实存在
  bool get hasValidCustomBackgroundFile {
    final p = _customBackgroundPath;
    if (p == null || p.isEmpty) return false;
    return File(p).existsSync();
  }

  static const _Uuid _uuid = _Uuid();

  // --------------------------- 生命周期 ---------------------------

  /// 启动时从 SharedPreferences 恢复用户选择
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final skinIndex = prefs.getInt('skin_mode') ?? SkinMode.light.index;
    final savedMode =
        SkinMode.values.elementAtOrNull(skinIndex) ?? SkinMode.light;

    // 兼容升级：旧版把内置 bgPic 模式存为 customBg（index=1）
    // 新定义 builtInBg=1 刚好对应，无需迁移；customBg 现在是 index=2
    switch (savedMode) {
      case SkinMode.light:
        _themeMode = ThemeMode.light;
        _skinMode = SkinMode.light;
        break;
      case SkinMode.builtInBg:
        _themeMode = ThemeMode.light;
        _skinMode = SkinMode.builtInBg;
        break;
      case SkinMode.customBg:
        _themeMode = ThemeMode.light;
        _skinMode = SkinMode.customBg;
        _customBackgroundPath = prefs.getString('custom_bg_path');
        // 如果保存的图不存在，自动降级到内置背景图，避免白屏
        if (!hasValidCustomBackgroundFile) {
          _skinMode = SkinMode.builtInBg;
          _customBackgroundPath = null;
        }
        break;
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('skin_mode', _skinMode.index);
    if (_skinMode == SkinMode.customBg && _customBackgroundPath != null) {
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

  /// 切换到亮色模式（纯色背景）
  void switchToLight() {
    _skinMode = SkinMode.light;
    _themeMode = ThemeMode.light;
    notifyListeners();
    _persist();
  }

  /// 切换到内置背景图模式（使用包内的 images/bgPic.jpg）
  void switchToBuiltInBg() {
    _skinMode = SkinMode.builtInBg;
    _themeMode = ThemeMode.light;
    notifyListeners();
    _persist();
  }

  /// 切换到自定义背景模式，并把 sourcePath 拷贝到应用支持目录作为背景
  ///
  /// 返回 true 表示保存成功，false 表示文件读取/复制失败
  Future<bool> switchToCustomBackground(String sourcePath) async {
    try {
      final srcFile = File(sourcePath);
      if (!srcFile.existsSync()) return false;

      final appDir = await _getAppSupportSubDir('custom_bg');
      if (!appDir.existsSync()) {
        await appDir.create(recursive: true);
      }

      final ext = srcFile.uri.pathSegments.lastOrNull?.split('.').last ?? 'jpg';
      final newName = 'custom_bg_${_uuid.v4()}.$ext';
      final dstFile = File('${appDir.path}${Platform.pathSeparator}$newName');

      // 先复制、替换，再清旧文件，避免同名覆盖时中途失败丢图
      await srcFile.copy(dstFile.path);

      final oldPath = _customBackgroundPath;
      _customBackgroundPath = dstFile.path;
      _skinMode = SkinMode.customBg;
      _themeMode = ThemeMode.light;

      notifyListeners();
      await _persist();

      _tryDeleteOldFile(oldPath, exclude: dstFile.path);
      return true;
    } catch (e) {
      debugPrint('[ThemeStore] switchToCustomBackground failed: $e');
      return false;
    }
  }

  /// 手动刷新 UI
  void refresh() => notifyListeners();

  // --------------------------- 内部辅助 ---------------------------

  Future<Directory> _getAppSupportSubDir(String subDir) async {
    final base = await getApplicationSupportDirectory();
    final p = '${base.path}${Platform.pathSeparator}JsonLayer${Platform.pathSeparator}$subDir';
    return Directory(p);
  }

  /// 清理上一张用户背景图（排除掉当前已在用的，避免误删）
  void _tryDeleteOldFile(String? path, {required String exclude}) {
    if (path == null || path.isEmpty) return;
    if (path == exclude) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (e) {
      debugPrint('[ThemeStore] delete old bg failed: $e');
    }
  }
}

// tiny wrapper to avoid importing uuid package if not used
class _Uuid {
  const _Uuid();
  String v4() => DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      (identityHashCode(Object())).toRadixString(36);
}
