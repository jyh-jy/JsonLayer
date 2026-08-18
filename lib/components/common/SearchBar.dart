import 'package:flutter/material.dart';

import 'package:json_layer/contants/CommonConstant.dart';

/// 通用搜索栏（APIFOX 风格）。
///
/// 结构：
///   [搜索输入框 (高亮)] [Aa(大小写)] [.*(正则)] [↑↓(前后导航)] [计数 n/N] [×(关闭)]
///
/// 用法：把它嵌入到任意编辑器的 header 中，通过回调驱动搜索逻辑。
class SearchQueryBar extends StatefulWidget {
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onCaseSensitiveChanged;
  final ValueChanged<bool> onRegexChanged;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onClose;

  /// 当前匹配序号（1-based），传 null 则不显示
  final int? currentMatch;

  /// 总匹配数，传 null 则不显示
  final int? totalMatches;

  /// 输入框宽度
  final double inputWidth;

  /// 高度
  final double height;

  /// 初始查询内容
  final String? initialQuery;

  const SearchQueryBar({
    super.key,
    required this.onQueryChanged,
    required this.onCaseSensitiveChanged,
    required this.onRegexChanged,
    this.onPrev,
    this.onNext,
    this.onClose,
    this.currentMatch,
    this.totalMatches,
    this.inputWidth = 200,
    this.height = 28,
    this.initialQuery,
  });

  @override
  State<SearchQueryBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchQueryBar> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _caseSensitive = false;
  bool _isRegex = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
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
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Color(CommonConstants.primaryColorValue);
    final secondary = Color(CommonConstants.textSecondaryColorValue);
    final borderColor = Color(CommonConstants.borderColorValue);
    final bgColor = Color(CommonConstants.surfaceColorValue);
    final sidebarBg = Color(CommonConstants.sidebarColorValue);

    final total = widget.totalMatches ?? 0;
    final current = widget.currentMatch ?? 0;
    final hasMatches = total > 0;
    final showCount = widget.totalMatches != null;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: sidebarBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildInput(primary, borderColor, bgColor),
          const SizedBox(width: 4),
          _buildToggleBtn(
            label: 'Aa',
            tooltip: _caseSensitive ? '区分大小写 (已开启)' : '区分大小写',
            active: _caseSensitive,
            primary: primary,
            secondary: secondary,
            onTap: () {
              setState(() => _caseSensitive = !_caseSensitive);
              widget.onCaseSensitiveChanged(_caseSensitive);
            },
          ),
          const SizedBox(width: 2),
          _buildToggleBtn(
            label: '.*',
            tooltip: _isRegex ? '正则表达式 (已开启)' : '正则表达式',
            active: _isRegex,
            primary: primary,
            secondary: secondary,
            onTap: () {
              setState(() => _isRegex = !_isRegex);
              widget.onRegexChanged(_isRegex);
            },
          ),
          const SizedBox(width: 4),
          _buildNavBtn(
            icon: Icons.keyboard_arrow_up,
            tooltip: '上一个 (Shift+Enter)',
            enabled: hasMatches && widget.onPrev != null,
            primary: primary,
            secondary: secondary,
            onTap: widget.onPrev,
          ),
          _buildNavBtn(
            icon: Icons.keyboard_arrow_down,
            tooltip: '下一个 (Enter)',
            enabled: hasMatches && widget.onNext != null,
            primary: primary,
            secondary: secondary,
            onTap: widget.onNext,
          ),
          if (showCount) ...[
            const SizedBox(width: 4),
            _buildCount(current, total, secondary),
          ],
          if (widget.onClose != null) ...[
            const SizedBox(width: 2),
            _buildCloseBtn(secondary),
          ],
        ],
      ),
    );
  }

  Widget _buildInput(Color primary, Color borderColor, Color bgColor) {
    return SizedBox(
      width: widget.inputWidth,
      height: widget.height - 6,
      child: Focus(
        focusNode: _focusNode,
        child: Builder(builder: (context) {
          final focused = Focus.of(context).hasFocus;
          final hasText = _controller.text.isNotEmpty;
          final noMatch = hasText && (widget.totalMatches == 0);
          return Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                width: 1.5,
                color: noMatch
                    ? Colors.red
                    : focused
                        ? primary
                        : borderColor,
              ),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: (v) {
                widget.onQueryChanged(v);
                setState(() {});
              },
              onSubmitted: (_) => widget.onNext?.call(),
              style: const TextStyle(fontSize: 12, height: 1.2),
              cursorHeight: 14,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                border: InputBorder.none,
                hintText: '搜索',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: Color(CommonConstants.textSecondaryColorValue),
                ),
                prefixIcon: hasText
                    ? null
                    : Icon(Icons.search,
                        size: 13,
                        color: Color(CommonConstants.textSecondaryColorValue)),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 22, maxHeight: 16),
                suffixIcon: hasText
                    ? GestureDetector(
                        onTap: () {
                          _controller.clear();
                          widget.onQueryChanged('');
                          setState(() {});
                        },
                        child: Icon(Icons.close,
                            size: 13,
                            color: Color(
                                CommonConstants.textSecondaryColorValue)),
                      )
                    : null,
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 22, maxHeight: 16),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildToggleBtn({
    required String label,
    required String tooltip,
    required bool active,
    required Color primary,
    required Color secondary,
    required VoidCallback onTap,
  }) {
    final color = active ? primary : secondary;
    final bg = active ? primary.withValues(alpha: 0.1) : Colors.transparent;
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          height: widget.height - 8,
          constraints: const BoxConstraints(minWidth: 24),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavBtn({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required Color primary,
    required Color secondary,
    required VoidCallback? onTap,
  }) {
    final color = enabled ? primary : secondary.withValues(alpha: 0.4);
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(3),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  Widget _buildCount(int current, int total, Color secondary) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        total == 0 ? '0/0' : '$current/$total',
        style: TextStyle(
          fontSize: 12,
          color: total == 0 ? Colors.red : secondary,
          fontFamily: 'Consolas',
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
        borderRadius: BorderRadius.circular(3),
        child: Icon(Icons.close, size: 18, color: secondary),
      ),
    );
  }
}
