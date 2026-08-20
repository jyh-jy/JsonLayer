import 'package:flutter/material.dart';

import 'package:json_layer/contants/CommonConstant.dart';

/// 编辑器工具栏图标按钮（JSON 模式 / 对象模式共用）。
///
/// 相比裸 [InkWell] 增加三层视觉反馈，每个动作用自己的语义色（见
/// `CommonConstants.action*ColorValue`），静默时统一为次要灰，
/// 只有在需要「被看见」的时刻才显色：
/// - **悬停**：语义色淡底 + 图标染色 + 轻微放大；
/// - **按下**：轻微缩小，给点击一个实感；
/// - **激活**（[active]）：常驻淡底与染色，用于「搜索栏已打开」这类开关态；
/// - **成功**（[succeeded]）：图标短暂切换为对勾，给格式化/压缩/复制一个完成回执。
class EditorActionButton extends StatefulWidget {
  /// 图标。与 [child] 二选一。
  final IconData? icon;

  /// 用自定义内容替代图标（如 [Image.asset] 的外链 logo）。
  /// 此时仍保留悬停淡底与缩放，但不做染色，也没有对勾回执。
  final Widget? child;

  final String tooltip;
  final VoidCallback onTap;

  /// 该动作的语义色（悬停/激活/成功时显示）。
  final Color color;

  /// 开关态：为 true 时常驻淡底与染色（如搜索栏已展开）。
  final bool active;

  /// 成功态：为 true 时图标临时替换为对勾。由父组件用定时器控制时长。
  final bool succeeded;

  const EditorActionButton({
    super.key,
    this.icon,
    this.child,
    required this.tooltip,
    required this.onTap,
    required this.color,
    this.active = false,
    this.succeeded = false,
  }) : assert(
         icon != null || child != null,
         'EditorActionButton 需要 icon 或 child 其中之一',
       );

  @override
  State<EditorActionButton> createState() => _EditorActionButtonState();
}

class _EditorActionButtonState extends State<EditorActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  /// 背景淡底的透明度：成功 > 激活 > 悬停 > 无。
  double get _backgroundAlpha {
    if (widget.succeeded) return CommonConstants.actionButtonSuccessAlpha;
    if (widget.active) return CommonConstants.actionButtonActiveAlpha;
    if (_hovered) return CommonConstants.actionButtonHoverAlpha;
    return 0;
  }

  double get _scale {
    if (_pressed) return CommonConstants.actionButtonPressScale;
    if (_hovered) return CommonConstants.actionButtonHoverScale;
    return 1;
  }

  /// 只有在悬停 / 激活 / 成功时才染成语义色，其余时刻保持次要灰，
  /// 避免一排彩色图标喧宾夺主。
  Color get _iconColor {
    final highlighted = _hovered || widget.active || widget.succeeded;
    return highlighted
        ? widget.color
        : Color(CommonConstants.textSecondaryColorValue);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: AnimatedContainer(
            duration: CommonConstants.hoverAnimation,
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.all(CommonConstants.buttonPadding),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: _backgroundAlpha),
              borderRadius: BorderRadius.circular(
                CommonConstants.actionButtonRadius,
              ),
            ),
            child: AnimatedScale(
              scale: _scale,
              duration: CommonConstants.hoverAnimation,
              curve: Curves.easeOut,
              child: _buildIcon(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    // 自定义内容（图片等）无法染色，只享受淡底与缩放
    final child = widget.child;
    if (child != null) return child;

    // 颜色用 TweenAnimationBuilder 补间（Icon 自身不会动画化 color）；
    // 图标形状的切换（原图标 ↔ 对勾）交给 AnimatedSwitcher。
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(
        begin: Color(CommonConstants.textSecondaryColorValue),
        end: _iconColor,
      ),
      duration: CommonConstants.hoverAnimation,
      curve: Curves.easeOut,
      builder: (context, color, _) {
        return AnimatedSwitcher(
          duration: CommonConstants.iconSwapAnimation,
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Icon(
            widget.succeeded ? Icons.check_rounded : widget.icon!,
            key: ValueKey<bool>(widget.succeeded),
            size: CommonConstants.buttonIconSize,
            color: color,
          ),
        );
      },
    );
  }
}

/// 工具栏中的分组竖线，用于把「AI 动作」与「编辑动作」在视觉上分开。
class EditorActionDivider extends StatelessWidget {
  const EditorActionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: CommonConstants.buttonIconSize,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: Color(CommonConstants.borderColorValue),
    );
  }
}
