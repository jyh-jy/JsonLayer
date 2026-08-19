import 'package:flutter/material.dart';

/// 全局去重的 SnackBar 工具，避免用户高频点击导致相同提示连续弹出（toast 幂等）。
///
/// 幂等策略：
/// - 默认以展示内容 [message] 作为幂等 key。
/// - 可通过 [idempotencyKey] 显式指定一个 key（例："rename_empty_name"），
///   即使 message 文本不同（如拼了变量）也能按业务语义去重。
/// - 在 [windowMs] 时间窗口（默认 1500 ms）内，相同 key 的 [show] 调用会被直接丢弃。
/// - 当已缓存的 key 超过 200 个时会自动清理过期记录，防止内存无限增长。
///
/// 支持所有原生 SnackBar 的常用样式参数：backgroundColor / textColor / duration /
/// behavior / shape / margin / padding / action 等。
class SafeSnackBar {
  SafeSnackBar._();

  /// key(幂等 key) → 最近一次真正弹出的毫秒时间戳
  static final Map<String, int> _lastShownAt = {};
  static const int _defaultWindowMs = 1500;
  static const int _cacheLimit = 200;

  /// 只做"该不该弹"的判断，不弹。用于外层自己做逻辑。
  static bool shouldFire(
    String message, {
    String? idempotencyKey,
    int windowMs = _defaultWindowMs,
  }) {
    final key = idempotencyKey ?? message;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastShownAt[key] ?? 0;
    if (now - last < windowMs) return false;
    _lastShownAt[key] = now;
    if (_lastShownAt.length > _cacheLimit) {
      final cutoff = now - windowMs;
      _lastShownAt.removeWhere((_, t) => t < cutoff);
    }
    return true;
  }

  /// 弹出一次幂等 SnackBar。如果窗口内重复调用会被丢弃并返回 null。
  ///
  /// 调用方不需要再写 `ScaffoldMessenger.of(context)`。
  /// 如果当前 context 上找不到 ScaffoldMessenger 也会安全返回 null。
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? show(
    BuildContext context, {
    required String message,
    String? idempotencyKey,
    int windowMs = _defaultWindowMs,
    Duration duration = const Duration(milliseconds: 2200),
    Color? backgroundColor,
    Color? textColor,
    SnackBarBehavior? behavior,
    ShapeBorder? shape,
    EdgeInsetsGeometry? margin,
    EdgeInsetsGeometry? padding,
    double? width,
    SnackBarAction? action,
    bool? showCloseIcon,
    VoidCallback? onVisible,
  }) {
    if (!shouldFire(message,
        idempotencyKey: idempotencyKey, windowMs: windowMs)) {
      return null;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return null;
    return messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: textColor == null ? null : TextStyle(color: textColor),
        ),
        duration: duration,
        backgroundColor: backgroundColor,
        behavior: behavior,
        shape: shape,
        margin: margin,
        padding: padding,
        width: width,
        action: action,
        showCloseIcon: showCloseIcon,
        onVisible: onVisible,
      ),
    );
  }
}
