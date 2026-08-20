import 'package:flutter/material.dart';

import 'package:json_layer/contants/CommonConstant.dart';

/// 弹窗底部的「取消 / 确定」按钮对。
///
/// 这一对按钮此前在新建、重命名、删除、设置四个弹窗里各抄了一份，样式靠
/// 手工对齐。抽出来后圆角、描边、危险色都只有一处定义。
///
/// [isDestructive] 为 true 时确认键用统一的危险红
/// （[CommonConstants.destructiveColorValue]），用于删除这类不可撤销的操作。
class DialogActions extends StatelessWidget {
  /// 确认键文案，如「确定」「删除」「保存」。
  final String confirmLabel;

  final String cancelLabel;

  /// 点确认。为 null 时确认键置灰（如必填项为空）。
  final VoidCallback? onConfirm;

  /// 点取消。默认就是关掉当前弹窗。
  final VoidCallback? onCancel;

  final bool isDestructive;

  const DialogActions({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    this.cancelLabel = '取消',
    this.onCancel,
    this.isDestructive = false,
  });

  static const double _radius = 8;

  @override
  Widget build(BuildContext context) {
    final confirmColor = isDestructive
        ? Color(CommonConstants.destructiveColorValue)
        : Theme.of(context).colorScheme.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          onPressed: onCancel ?? () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: Color(CommonConstants.textPrimaryColorValue),
            side: BorderSide(color: Color(CommonConstants.borderColorValue)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius),
            ),
          ),
          child: Text(cancelLabel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: onConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius),
            ),
          ),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
