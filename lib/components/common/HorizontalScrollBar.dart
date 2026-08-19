import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import 'package:json_layer/contants/CommonConstant.dart';

/// 固定在底部、始终可见的水平滚动条。
///
/// 内置的 [RawScrollbar]/[Scrollbar] 依赖 [ScrollNotification] 沿组件树向上
/// 冒泡才能绘制滑块；而水平滚动视图通常与滚动条是兄弟节点（且水平滚动视图
/// 嵌套在垂直滚动视图内、depth 不为 0），通知无法到达。因此改为直接监听
/// [ScrollController]，用滑块位置反映并控制水平滚动。
///
/// 视觉滑块保持纤细，但命中区域加高，便于点击/拖拽。
///
/// 性能优化：滚动期间不每像素 setState，而是按显示器 VSync 的调度节奏
/// （Ticker frame）节流，一次帧更新内合并多次滚动通知，避免高频重建。
class HorizontalScrollBar extends StatefulWidget {
  const HorizontalScrollBar({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<HorizontalScrollBar> createState() => _HorizontalScrollBarState();
}

class _HorizontalScrollBarState extends State<HorizontalScrollBar>
    with SingleTickerProviderStateMixin {
  /// 手势命中区域的高度（可点击/拖拽），比视觉滑块更厚，便于点中。
  static const double _barHeight = 16;

  /// 视觉滑块的厚度（垂直居中显示，保持纤细观感）。
  static const double _thumbThickness = 6;

  static const double _minThumbWidth = 24;

  late final Ticker _ticker;
  bool _frameScheduled = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleScrollChanged);
    _ticker = createTicker((_) {
      _frameScheduled = false;
      if (!_disposed && mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant HorizontalScrollBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleScrollChanged);
      widget.controller.addListener(_handleScrollChanged);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.controller.removeListener(_handleScrollChanged);
    _ticker.dispose();
    super.dispose();
  }

  /// 滚动控制器变更时只调度一帧，同一帧内的多次变更合并为一次重建。
  void _handleScrollChanged() {
    if (_frameScheduled || _disposed) return;
    _frameScheduled = true;
    if (!_ticker.isActive) _ticker.start();
  }

  /// 当前水平滚动位置（控制器仅挂载一个滚动视图时有效）。
  ScrollPosition? get _position {
    final controller = widget.controller;
    if (!controller.hasClients || controller.positions.length != 1) return null;
    return controller.position;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _barHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final position = _position;
          final maxExtent = position?.maxScrollExtent ?? 0.0;
          final hasOverflow = maxExtent > 0;

          double thumbLeft = 0;
          double thumbWidth = 0;
          if (hasOverflow && position != null && width > 0) {
            final viewport = position.viewportDimension;
            final contentExtent = viewport + maxExtent;
            final fraction = viewport / contentExtent;
            thumbWidth = math
                .max(_minThumbWidth, width * fraction)
                .clamp(0.0, width)
                .toDouble();
            final scrolledFraction = (position.pixels / maxExtent)
                .clamp(0.0, 1.0)
                .toDouble();
            thumbLeft = (width - thumbWidth) * scrolledFraction;
          }

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _scrubTo(details.localPosition.dx),
              onHorizontalDragUpdate: (details) =>
                  _scrubTo(details.localPosition.dx),
              child: Stack(
                children: [
                  if (hasOverflow && thumbWidth > 0)
                    Positioned(
                      left: thumbLeft,
                      top: (_barHeight - _thumbThickness) / 2,
                      width: thumbWidth,
                      height: _thumbThickness,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Color(
                            CommonConstants.textSecondaryColorValue,
                          ).withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 根据滑块内的局部 x 坐标，将水平滚动定位到对应位置（点击或拖拽）。
  void _scrubTo(double localX) {
    final position = _position;
    if (position == null) return;
    final maxExtent = position.maxScrollExtent;
    if (maxExtent <= 0) return;

    final width = context.size?.width ?? 0;
    if (width <= 0) return;

    final viewport = position.viewportDimension;
    final contentExtent = viewport + maxExtent;
    final thumbWidth = math
        .max(_minThumbWidth, width * viewport / contentExtent)
        .clamp(0.0, width)
        .toDouble();
    final scrollableTrack = width - thumbWidth;
    if (scrollableTrack <= 0) return;

    final fraction = ((localX - thumbWidth / 2) / scrollableTrack)
        .clamp(0.0, 1.0)
        .toDouble();
    position.jumpTo(fraction * maxExtent);
  }
}
