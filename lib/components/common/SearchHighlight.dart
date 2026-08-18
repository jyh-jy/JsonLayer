import 'package:flutter/material.dart';

import 'package:json_layer/contants/CommonConstant.dart';

/// 搜索命中的统一高亮样式（JSON 模式与对象模式共用）。
///
/// 普通命中用琥珀色背景；当前命中用主题色（靛蓝）强调：
///  - 对象模式通过 [Container] 边框画出「框」；
///  - JSON 模式（文本编辑器 TextSpan）无法画真边框，改用上下装饰线模拟。
class SearchHighlight {
  SearchHighlight._();

  /// 普通命中背景色
  static Color get matchBackground =>
      const Color(0xFFFFC107).withValues(alpha: 0.55);

  /// 当前命中背景色
  static Color get currentBackground =>
      Color(CommonConstants.primaryColorValue).withValues(alpha: 0.35);

  /// 当前命中的「框」颜色（主题色）
  static Color get currentFrameColor =>
      Color(CommonConstants.primaryColorValue);

  /// 当前命中外层容器背景色（对象模式）
  static Color get currentFrameBackground =>
      Color(CommonConstants.primaryColorValue).withValues(alpha: 0.12);
}
