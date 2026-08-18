import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:json_layer/contants/CommonConstant.dart';

/// 通用搜索栏（APIFOX 风格，精简版）。
///
/// 只保留：[搜索输入框] [计数 n/N] [× 关闭]。
/// 大小写 / 正则 / 上一个下一个 不占用输入框空间，输入框占满主宽度。
class SearchQueryBar extends StatefulWidget {
  final ValueChanged<String> onQueryChanged;
  final VoidCallback? onClose;

  /// 当前匹配序号（1-based），传 null 则不显示
  final int? currentMatch;

  /// 总匹配数，传 null 则不显示计数
  final int? totalMatches;

  /// 整体高度
  final double height;

  /// 初始查询内容
  final String? initialQuery;

  /// 输入框内按下 Enter（shift=true 上一个，false 下一个）
  final void Function(bool shift)? onNavigate;

  /// 输入框内按下 Esc
  final VoidCallback? onEscape;

  /// 外部可传入的焦点节点，用于父组件在滚动后把焦点还给输入框
  final FocusNode? focusNode;

  const SearchQueryBar({
    super.key,
    required this.onQueryChanged,
    this.onClose,
    this.currentMatch,
    this.totalMatches,
    this.height = 36,
    this.initialQuery,
    this.onNavigate,
    this.onEscape,
    this.focusNode,
  });

  @override
  State<SearchQueryBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchQueryBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.onKeyEvent = _handleKeyEvent;
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    final focused = _focusNode.hasFocus;
    if (mounted && _focused != focused) {
      setState(() => _focused = focused);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onEscape?.call();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        final shift = HardwareKeyboard.instance.isShiftPressed;
        widget.onNavigate?.call(shift);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void didUpdateWidget(covariant SearchQueryBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != null &&
        widget.initialQuery != oldWidget.initialQuery &&
        widget.initialQuery != _controller.text) {
      _controller.text = widget.initialQuery!;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.totalMatches ?? 0;
    final current = widget.currentMatch ?? 0;
    final showCount = widget.totalMatches != null;
    final hasText = _controller.text.isNotEmpty;
    final noMatch = hasText && widget.totalMatches == 0;

    final primary = Color(CommonConstants.primaryColorValue);
    final secondary = Color(CommonConstants.textSecondaryColorValue);
    final borderColor = Color(CommonConstants.borderColorValue);
    final surface = Color(CommonConstants.surfaceColorValue);

    final border = noMatch
        ? Colors.red
        : _focused
            ? primary
            : borderColor;
    final borderWidth = (_focused || noMatch) ? 1.5 : 1.0;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.only(left: 10, right: 4),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 16,
            color: hasText ? primary : secondary,
          ),
          const SizedBox(width: 6),
          Expanded(child: _buildTextField(primary)),
          if (hasText) _buildClearBtn(secondary),
          if (showCount) ...[
            _buildDivider(borderColor),
            _buildCount(current, total, primary, secondary),
          ],
          if (widget.onClose != null) ...[
            const SizedBox(width: 2),
            _buildCloseBtn(secondary),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField(Color primary) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      onChanged: (v) {
        widget.onQueryChanged(v);
        if (mounted) setState(() {});
      },
      style: TextStyle(
        fontSize: 13,
        height: 1.3,
        color: Color(CommonConstants.textPrimaryColorValue),
      ),
      cursorHeight: 15,
      cursorWidth: 1.5,
      cursorColor: primary,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        isDense: true,
        isCollapsed: true,
        border: InputBorder.none,
        hintText: '搜索',
        hintStyle: TextStyle(
          fontSize: 13,
          color: Color(CommonConstants.textSecondaryColorValue),
        ),
      ),
    );
  }

  Widget _buildClearBtn(Color secondary) {
    return GestureDetector(
      onTap: () {
        _controller.clear();
        widget.onQueryChanged('');
        if (mounted) setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: secondary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.close, size: 12, color: secondary),
        ),
      ),
    );
  }

  Widget _buildDivider(Color borderColor) {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: borderColor,
    );
  }

  Widget _buildCount(int current, int total, Color primary, Color secondary) {
    // 无匹配时用红色醒目标记
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '0/0',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.red,
            fontFamily: 'Consolas',
          ),
        ),
      );
    }

    // 当前序号用主题色突出，总数用次级色
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
          children: [
            TextSpan(
              text: '$current',
              style: TextStyle(
                color: primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: '/$total',
              style: TextStyle(
                color: secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloseBtn(Color secondary) {
    return Tooltip(
      message: '关闭搜索 (Esc)',
      preferBelow: false,
      child: InkWell(
        onTap: widget.onClose,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.close, size: 18, color: secondary),
        ),
      ),
    );
  }
}
