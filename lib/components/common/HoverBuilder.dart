import 'package:flutter/material.dart';

/// 把「鼠标是否悬停」这件事抽出来的极小原语。
///
/// 桌面端几乎每个可点区域都要悬停反馈，但 [MouseRegion] + `setState` 写在
/// 每个组件里既啰嗦又容易漏掉 `onExit`（比如控件在悬停状态下被移除，
/// 悬停态就永远卡住）。用它包一层，[builder] 直接拿到 `isHovered`。
class HoverBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool isHovered) builder;

  /// 悬停时的鼠标指针样式。不可点的区域传 [SystemMouseCursors.basic]。
  final MouseCursor cursor;

  /// 为 false 时不响应悬停，[builder] 恒收到 false（如禁用态）。
  final bool enabled;

  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
    this.enabled = true,
  });

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  void didUpdateWidget(HoverBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从可用切到禁用时，把悬停态收干净，避免禁用后仍显示高亮
    if (!widget.enabled && _hovered) {
      _hovered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.builder(context, false);
    }
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: widget.builder(context, _hovered),
    );
  }
}
