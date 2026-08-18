import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/json.dart' as json_lang;

import 'package:json_layer/contants/CommonConstant.dart';

/// 自研 JSON 文本编辑器。
///
/// 特性：语法高亮、顺序行号（1~N）、缩进引导线、Ctrl+F 搜索、
/// 双击选中值（不含引号）、格式化/压缩、Ctrl+Shift+L 格式化、Ctrl+S 保存。
class JsonEditor extends StatefulWidget {
  final String content;
  final ValueChanged<String> onChanged;
  final String title;
  final bool readOnly;
  final VoidCallback? onSave;

  const JsonEditor({
    super.key,
    required this.content,
    required this.onChanged,
    this.title = '',
    this.readOnly = false,
    this.onSave,
  });

  @override
  State<JsonEditor> createState() => _JsonEditorState();
}

/// 支持 JSON 语法高亮的文本控制器（高亮文本与原文字符 1:1 对齐）。
class JsonTextEditingController extends TextEditingController {
  static final Highlight _highlight =
      Highlight()..registerLanguage('json', json_lang.json);

  JsonTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool? withComposing,
  }) {
    final base = style ?? const TextStyle();
    if (text.isEmpty) {
      return TextSpan(text: ' ', style: base);
    }
    try {
      final result = _highlight.parse(text, language: 'json');
      final spans = result.nodes
          ?.map((node) => _nodeToSpan(node, base))
          .toList(growable: false);
      return TextSpan(style: base, children: spans);
    } catch (_) {
      return TextSpan(text: text, style: base);
    }
  }

  TextSpan _nodeToSpan(Node node, TextStyle base) {
    return TextSpan(
      text: node.value,
      style: _styleForClass(node.className, base),
      children: node.children
          ?.map((c) => _nodeToSpan(c, base))
          .toList(growable: false),
    );
  }

  TextStyle? _styleForClass(String? className, TextStyle base) {
    switch (className) {
      case 'attr':
        return base.copyWith(color: Color(CommonConstants.jsonKeyColorValue));
      case 'string':
        return base.copyWith(color: Color(CommonConstants.jsonStringColorValue));
      case 'number':
        return base.copyWith(color: Color(CommonConstants.jsonNumberColorValue));
      case 'literal':
        return base.copyWith(color: Color(CommonConstants.jsonBooleanColorValue));
      case 'comment':
        return base.copyWith(
          color: Color(CommonConstants.jsonNullColorValue),
          fontStyle: FontStyle.italic,
        );
      default:
        return base;
    }
  }
}

class _JsonEditorState extends State<JsonEditor> {
  late JsonTextEditingController _controller;
  final ScrollController _lineScroll = ScrollController();

  // 搜索状态
  bool _searchVisible = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';
  final List<int> _matches = [];
  int _currentMatch = -1;

  bool _suppressSelection = false;

  final ScrollController _codeScroll = ScrollController();
  final FocusNode _controllerFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = JsonTextEditingController(text: widget.content);
    _controller.addListener(_onControllerChanged);
    _codeScroll.addListener(_syncLineScroll);
  }

  @override
  void didUpdateWidget(JsonEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != _controller.text) {
      _controller.text = widget.content;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _codeScroll.removeListener(_syncLineScroll);
    _controller.dispose();
    _lineScroll.dispose();
    _codeScroll.dispose();
    _controllerFocus.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    _handleQuoteSelection();
  }

  void _syncLineScroll() {
    if (_lineScroll.hasClients && _lineScroll.offset != _codeScroll.offset) {
      _lineScroll.jumpTo(_codeScroll.offset);
    }
  }

  /// 双击/选中字符串时，去掉首尾双引号。
  void _handleQuoteSelection() {
    if (_suppressSelection) return;
    final sel = _controller.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final t = _controller.text;
    final s = sel.start;
    final e = sel.end;
    if (s >= e || e > t.length || s >= t.length) return;

    // 选区两端正好是引号：收缩到引号内部
    if (t[s] == '"' && t[e - 1] == '"') {
      final isStart = s == 0 || !_insideStringAt(t, s - 1);
      final isEnd = _isStringClosingQuote(t, e - 1);
      if (isStart && isEnd && e - 1 > s) {
        _suppressSelection = true;
        _controller.selection =
            TextSelection(baseOffset: s + 1, extentOffset: e - 1);
        _suppressSelection = false;
      }
    }
  }

  bool _insideStringAt(String t, int pos) {
    bool inString = false;
    for (int i = 0; i <= pos && i < t.length; i++) {
      if (t[i] == '"' && !_isEscaped(t, i)) inString = !inString;
    }
    return inString;
  }

  bool _isStringClosingQuote(String t, int pos) {
    if (t[pos] != '"') return false;
    // 该引号左侧处于字符串内，即它是闭合引号
    return _insideStringAt(t, pos - 1);
  }

  bool _isEscaped(String t, int i) {
    int count = 0;
    int j = i - 1;
    while (j >= 0 && t[j] == '\\') {
      count++;
      j--;
    }
    return count.isOdd;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(theme),
        Expanded(child: _buildEditor(theme)),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      height: CommonConstants.editorHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Color(CommonConstants.surfaceColorValue),
        border: Border(
          bottom: BorderSide(color: Color(CommonConstants.borderColorValue)),
        ),
      ),
      child: Row(
        children: [
          Text(
            widget.title,
            style: theme.textTheme.bodySmall?.copyWith(
                  color: Color(CommonConstants.textSecondaryColorValue),
                  fontWeight: FontWeight.w500,
                ),
          ),
          const Spacer(),
          _buildActionButton(
            theme,
            icon: Icons.search,
            tooltip: '搜索 (Ctrl+F)',
            onTap: _toggleSearch,
          ),
          _buildActionButton(
            theme,
            icon: Icons.format_align_left,
            tooltip: '格式化 (Ctrl+Shift+L)',
            onTap: _formatJson,
          ),
          _buildActionButton(
            theme,
            icon: Icons.compress,
            tooltip: '压缩',
            onTap: _compressJson,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    ThemeData theme, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: Color(CommonConstants.textSecondaryColorValue)),
        ),
      ),
    );
  }

  Widget _buildEditor(ThemeData theme) {
    final baseStyle = TextStyle(
      fontFamily: 'Consolas',
      fontSize: 13,
      color: Color(CommonConstants.textPrimaryColorValue),
      height: 1.5,
    );
    final lineHeight = baseStyle.fontSize! * (baseStyle.height ?? 1.5);

    final lines = _controller.text.split('\n');
    final lineIndents = lines
        .map((l) => (l.length - l.trimLeft().length) ~/ 2)
        .toList(growable: false);

    return Stack(
      children: [
        Positioned.fill(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LineNumberGutter(
                lineCount: lines.length,
                lineIndents: lineIndents,
                lineHeight: lineHeight,
                scrollController: _lineScroll,
                textStyle: baseStyle,
              ),
              Expanded(
                child: Focus(
                  onKeyEvent: _onKeyEvent,
                  child: TextField(
                    controller: _controller,
                    focusNode: _controllerFocus,
                    readOnly: widget.readOnly,
                    maxLines: null,
                    expands: true,
                    scrollController: _codeScroll,
                    style: baseStyle,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      widget.onChanged(v);
                      _refreshSearch();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_searchVisible) _buildSearchBar(theme),
        // 右侧滚动条区域：悬停显示箭头光标
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: 10,
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    final total = _matches.length;
    final current = total == 0 ? 0 : _currentMatch + 1;
    return Positioned(
      top: 0,
      right: 12,
      child: Container(
        width: 320,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Color(CommonConstants.surfaceColorValue),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Color(CommonConstants.borderColorValue)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 14, color: Color(CommonConstants.textSecondaryColorValue)),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autofocus: true,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '搜索',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (v) {
                  _searchQuery = v;
                  _refreshSearch();
                },
                onSubmitted: (_) => _findNext(),
              ),
            ),
            Text(
              total == 0 ? '0/0' : '$current/$total',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            _searchIconButton(Icons.keyboard_arrow_up, '上一个', _findPrev),
            _searchIconButton(Icons.keyboard_arrow_down, '下一个', _findNext),
            _searchIconButton(Icons.close, '关闭', _toggleSearch),
          ],
        ),
      ),
    );
  }

  Widget _searchIconButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: Color(CommonConstants.textSecondaryColorValue)),
        ),
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (_searchVisible) {
        _searchQuery = _controller.selection.isValid && !_controller.selection.isCollapsed
            ? _controller.text.substring(
                _controller.selection.start, _controller.selection.end)
            : '';
        _searchController.text = _searchQuery;
        _refreshSearch();
      }
    });
  }

  void _refreshSearch() {
    final t = _controller.text.toLowerCase();
    final q = _searchQuery.toLowerCase();
    _matches.clear();
    _currentMatch = -1;
    if (q.isEmpty) {
      setState(() {});
      return;
    }
    int from = 0;
    while (true) {
      final idx = t.indexOf(q, from);
      if (idx == -1) break;
      _matches.add(idx);
      from = idx + 1;
    }
    if (_matches.isNotEmpty) {
      // 定位到离光标最近的匹配
      final caret = _controller.selection.baseOffset;
      _currentMatch = _matches.lastIndexWhere((m) => m <= caret);
      if (_currentMatch == -1) _currentMatch = 0;
    }
    setState(() {});
  }

  void _findNext() {
    if (_matches.isEmpty) return;
    _currentMatch = (_currentMatch + 1) % _matches.length;
    _selectMatch(_currentMatch);
  }

  void _findPrev() {
    if (_matches.isEmpty) return;
    _currentMatch = (_currentMatch - 1 + _matches.length) % _matches.length;
    _selectMatch(_currentMatch);
  }

  void _selectMatch(int index) {
    final start = _matches[index];
    final end = start + _searchQuery.length;
    _controller.selection = TextSelection(baseOffset: end, extentOffset: start);
    _controllerFocus.requestFocus();
    setState(() {});
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (event.logicalKey == LogicalKeyboardKey.keyL && shift) {
        _formatJson();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyS && !shift) {
        widget.onSave?.call();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyF && !shift) {
        _toggleSearch();
        return KeyEventResult.handled;
      }
    }
    if (_searchVisible) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
        _toggleSearch();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _formatJson() {
    try {
      final text = _controller.text.trim();
      if (text.isEmpty) return;
      final decoded = jsonDecode(text);
      final formatted = const JsonEncoder.withIndent('  ').convert(decoded);
      _controller.text = formatted;
      widget.onChanged(formatted);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('格式化失败: $e')),
      );
    }
  }

  void _compressJson() {
    try {
      final text = _controller.text.trim();
      if (text.isEmpty) return;
      final decoded = jsonDecode(text);
      final compressed = jsonEncode(decoded);
      _controller.text = compressed;
      widget.onChanged(compressed);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('压缩失败: $e')),
      );
    }
  }
}

/// 行号 + 缩进引导线列（与代码区同步滚动）。
class _LineNumberGutter extends StatelessWidget {
  final int lineCount;
  final List<int> lineIndents;
  final double lineHeight;
  final ScrollController scrollController;
  final TextStyle textStyle;

  const _LineNumberGutter({
    required this.lineCount,
    required this.lineIndents,
    required this.lineHeight,
    required this.scrollController,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    // 测量字符宽度：数字宽度用于行号，两空格宽度用于缩进步长
    final digitTp = TextPainter(
      text: TextSpan(text: '0', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final indentTp = TextPainter(
      text: TextSpan(text: '  ', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final maxDepth = lineIndents.fold<int>(0, math.max);
    final indentStep = indentTp.width;
    final lineNumberWidth = lineCount.toString().length * digitTp.width + 16;
    final gutterWidth = lineNumberWidth + maxDepth * indentStep + 12;
    final contentHeight = math.max(1, lineCount) * lineHeight + 24;

    return Container(
      width: gutterWidth,
      color: Color(CommonConstants.sidebarColorValue),
      child: SingleChildScrollView(
        controller: scrollController,
        physics: const NeverScrollableScrollPhysics(),
        child: CustomPaint(
          size: Size(gutterWidth, contentHeight),
          painter: _GutterPainter(
            lineCount: lineCount,
            lineIndents: lineIndents,
            lineHeight: lineHeight,
            lineNumberWidth: lineNumberWidth,
            indentStep: indentStep,
            textStyle: textStyle,
          ),
        ),
      ),
    );
  }
}

class _GutterPainter extends CustomPainter {
  final int lineCount;
  final List<int> lineIndents;
  final double lineHeight;
  final double lineNumberWidth;
  final double indentStep;
  final TextStyle textStyle;

  _GutterPainter({
    required this.lineCount,
    required this.lineIndents,
    required this.lineHeight,
    required this.lineNumberWidth,
    required this.indentStep,
    required this.textStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const topPadding = 12.0;
    final numberColor = Color(CommonConstants.textSecondaryColorValue);
    final guideColor = Color(CommonConstants.borderColorValue);

    final numberStyle = textStyle.copyWith(color: numberColor);

    for (int i = 0; i < lineCount; i++) {
      final y = topPadding + i * lineHeight;

      // 缩进引导线（每层一条竖线）
      final depth = i < lineIndents.length ? lineIndents[i] : 0;
      for (int k = 0; k < depth; k++) {
        final x = lineNumberWidth + 8 + k * indentStep;
        canvas.drawLine(
          Offset(x, y),
          Offset(x, y + lineHeight),
          Paint()
            ..color = guideColor
            ..strokeWidth = 1,
        );
      }

      // 行号
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: numberStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(lineNumberWidth - tp.width - 8, y + (lineHeight - tp.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GutterPainter oldDelegate) {
    return oldDelegate.lineCount != lineCount ||
        oldDelegate.lineHeight != lineHeight ||
        oldDelegate.indentStep != indentStep ||
        oldDelegate.lineNumberWidth != lineNumberWidth ||
        oldDelegate.lineIndents != lineIndents;
  }
}
