import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/json.dart' as json_highlight;

import 'package:json_layer/components/common/SearchBar.dart' show SearchQueryBar;
import 'package:json_layer/components/common/SearchHighlight.dart';
import 'package:json_layer/contants/CommonConstant.dart';

/// JSON 文本编辑器组件（基于 flutter_code_editor）。
///
/// 特性：语法高亮、行号、花括号折叠、Ctrl+F 搜索（库内置）、
/// 格式化/压缩、Ctrl+L 格式化、Ctrl+S 保存。
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

class _JsonEditorState extends State<JsonEditor> {
  late _JsonCodeController _controller;
  final ScrollController _lineNumberScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final FocusNode _editorFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  int _lineCount = 1;
  String _longestLine = '';
  int _lastPointerDownTime = 0;
  int _lastPointerDownPointer = -1;

  // 搜索相关
  bool _showSearchBar = false;
  String _searchQuery = '';
  bool _caseSensitive = false;
  bool _isRegex = false;
  final List<TextRange> _matches = [];
  int _currentMatchIndex = -1;

  @override
  void initState() {
    super.initState();
    _controller = _JsonCodeController(text: widget.content);
    _controller
      ..onOpenSearch = _openSearch
      ..onCloseSearch = _closeSearch
      ..onNavigate = (shift) => shift ? _prevMatch() : _nextMatch();
    _editorFocusNode.attach(context, onKeyEvent: _onEditorKeyEvent);
    _updateLineCount();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(JsonEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != _controller.text) {
      _controller.text = widget.content;
      _updateLineCount();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _lineNumberScrollController.dispose();
    _editorFocusNode.dispose();
    _searchFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _updateLineCount();
    final text = _controller.text;
    final longest = text.isEmpty
        ? ''
        : text.split('\n').reduce((a, b) => a.length > b.length ? a : b);
    if (longest != _longestLine) {
      setState(() {
        _longestLine = longest;
      });
    }
  }

  void _updateLineCount() {
    final text = _controller.text;
    final count = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
    if (count != _lineCount) {
      setState(() {
        _lineCount = count;
      });
    }
  }

  // ---------------- 搜索 ----------------

  void _recollectMatches() {
    _matches.clear();
    _currentMatchIndex = -1;
    final q = _searchQuery.trim();
    if (q.isEmpty) {
      _syncHighlight();
      setState(() {});
      return;
    }
    final text = _controller.text;
    RegExp? regex;
    try {
      if (_isRegex) {
        regex = RegExp(q, caseSensitive: _caseSensitive, multiLine: false);
      }
    } catch (_) {
      regex = null;
    }

    if (_isRegex) {
      if (regex != null) {
        for (final m in regex.allMatches(text)) {
          if (m.start == m.end) continue;
          _matches.add(TextRange(start: m.start, end: m.end));
        }
      }
    } else if (_caseSensitive) {
      int idx = 0;
      while ((idx = text.indexOf(q, idx)) != -1) {
        _matches.add(TextRange(start: idx, end: idx + q.length));
        idx += q.length;
      }
    } else {
      final lower = text.toLowerCase();
      final ql = q.toLowerCase();
      int idx = 0;
      while ((idx = lower.indexOf(ql, idx)) != -1) {
        _matches.add(TextRange(start: idx, end: idx + q.length));
        idx += q.length;
      }
    }
    if (_matches.isNotEmpty) {
      _currentMatchIndex = 0;
    }
    _syncHighlight();
    setState(() {});
    if (_matches.isNotEmpty) {
      _selectCurrent(scroll: true);
    }
  }

  /// 把命中与当前序号同步到控制器，供 buildTextSpan 高亮使用。
  void _syncHighlight() {
    _controller.updateSearchHighlight(
      List<TextRange>.from(_matches),
      _currentMatchIndex,
    );
  }

  /// 选中当前命中，并（可选）让编辑器滚动到该位置。
  void _selectCurrent({bool scroll = false}) {
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _matches.length) return;
    final range = _matches[_currentMatchIndex];
    _controller.selection = TextSelection(
      baseOffset: range.start,
      extentOffset: range.end,
      affinity: TextAffinity.downstream,
    );
    if (scroll) {
      // 让编辑器获得焦点以触发滚动，随后把焦点还给搜索框。
      _editorFocusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _searchFocusNode.requestFocus();
      });
    }
  }

  void _nextMatch() {
    if (_matches.isEmpty) return;
    _currentMatchIndex = (_currentMatchIndex + 1) % _matches.length;
    _syncHighlight();
    setState(() {});
    _selectCurrent(scroll: true);
  }

  void _prevMatch() {
    if (_matches.isEmpty) return;
    _currentMatchIndex = _currentMatchIndex <= 0
        ? _matches.length - 1
        : _currentMatchIndex - 1;
    _syncHighlight();
    setState(() {});
    _selectCurrent(scroll: true);
  }

  void _openSearch() {
    setState(() => _showSearchBar = true);
    _controller.searchBarVisible = true;
    // 唤起后让输入框自动获得焦点，用户无需再点击输入框。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _controller.searchBarVisible = false;
    _controller.updateSearchHighlight(const [], -1);
    setState(() {
      _showSearchBar = false;
      _searchQuery = '';
      _caseSensitive = false;
      _isRegex = false;
      _matches.clear();
      _currentMatchIndex = -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      onKeyEvent: _onKeyEvent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          if (_showSearchBar) _buildSearchBarWrap(theme),
          Expanded(child: _buildEditor(theme)),
        ],
      ),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final ctrl = HardwareKeyboard.instance.isControlPressed;
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (ctrl && event.logicalKey == LogicalKeyboardKey.keyF) {
        _openSearch();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape && _showSearchBar) {
        _closeSearch();
        return KeyEventResult.handled;
      }
      if (_showSearchBar && _matches.isNotEmpty) {
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (shift) {
            _prevMatch();
          } else {
            _nextMatch();
          }
          return KeyEventResult.handled;
        }
      }
    }
    // 原有快捷键：Ctrl+L 格式化、Ctrl+S 保存
    if (event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyL) {
        _formatJson();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyS) {
        widget.onSave?.call();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onEditorKeyEvent(FocusNode node, KeyEvent event) {
    return _controller.onKey(event);
  }

  Widget _buildSearchBarWrap(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: Color(CommonConstants.sidebarColorValue),
        border: Border(
          bottom: BorderSide(color: Color(CommonConstants.borderColorValue)),
        ),
      ),
      child: SearchQueryBar(
        currentMatch: _currentMatchIndex < 0 ? null : _currentMatchIndex + 1,
        totalMatches:
            _matches.isEmpty && _searchQuery.trim().isEmpty ? null : _matches.length,
        onQueryChanged: (q) {
          _searchQuery = q;
          _recollectMatches();
        },
        onClose: _closeSearch,
        onNavigate: (shift) => shift ? _prevMatch() : _nextMatch(),
        onEscape: _closeSearch,
        focusNode: _searchFocusNode,
      ),
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
            onTap: () => _showSearchBar ? _closeSearch() : _openSearch(),
          ),
          _buildActionButton(
            theme,
            icon: Icons.format_align_left,
            tooltip: '格式化 (Ctrl+L)',
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
        borderRadius: BorderRadius.circular(CommonConstants.buttonRadius),
        splashColor: CommonConstants.primaryOverlay(0.08),
        highlightColor: CommonConstants.primaryOverlay(0.05),
        child: Padding(
          padding: const EdgeInsets.all(CommonConstants.buttonPadding),
          child: Icon(
            icon,
            size: CommonConstants.buttonIconSize,
            color: Color(CommonConstants.textSecondaryColorValue),
          ),
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
    final lineHeight = 13 * 1.5;
    final maxLines = math.max(_lineCount, 1);

    return Container(
      color: Color(CommonConstants.surfaceColorValue),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLineNumbers(lineHeight),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final minHeight = constraints.maxHeight;
                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification) {
                      final offset = notification.metrics.pixels;
                      if (_lineNumberScrollController.hasClients &&
                          _lineNumberScrollController.offset != offset) {
                        _lineNumberScrollController.jumpTo(offset);
                      }
                    }
                    return false;
                  },
                  child: CodeTheme(
                    data: CodeThemeData(styles: _buildHighlightStyles()),
                    child: Scrollbar(
                      controller: _verticalScrollController,
                      child: SingleChildScrollView(
                        controller: _verticalScrollController,
                        child: _wrapInScrollView(
                          minHeight: minHeight,
                          Listener(
                            onPointerDown: _handlePointerDown,
                            child: TextField(
                              focusNode: _editorFocusNode,
                              controller: _controller,
                              readOnly: widget.readOnly,
                              maxLines: maxLines,
                              style: baseStyle,
                              cursorColor:
                                  Color(CommonConstants.textPrimaryColorValue),
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: const InputDecoration(
                                isCollapsed: true,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 16),
                                disabledBorder: InputBorder.none,
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                              onChanged: widget.onChanged,
                            ),
                          ),
                          baseStyle,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapInScrollView(
    Widget codeField,
    TextStyle textStyle, {
    required double minHeight,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          thickness: 6,
          radius: const Radius.circular(3),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _horizontalScrollController,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth,
                minHeight: minHeight,
              ),
              child: IntrinsicWidth(
                child: codeField,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLineNumbers(double lineHeight) {
    return Container(
      width: 56,
      color: Color(CommonConstants.sidebarColorValue),
      child: RawScrollbar(
        controller: _lineNumberScrollController,
        thumbVisibility: false,
        trackVisibility: false,
        child: ListView.builder(
          controller: _lineNumberScrollController,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(vertical: 8),
          itemCount: _lineCount,
          itemExtent: lineHeight,
          itemBuilder: (context, index) {
            return Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 12,
                  color: Color(CommonConstants.textSecondaryColorValue),
                  height: 1.5,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 高亮配色（浅色主题）。
  Map<String, TextStyle> _buildHighlightStyles() {
    return {
      'root': TextStyle(color: Color(CommonConstants.textPrimaryColorValue)),
      'attr': TextStyle(color: Color(CommonConstants.jsonKeyColorValue)),
      'string': TextStyle(color: Color(CommonConstants.jsonStringColorValue)),
      'number': TextStyle(color: Color(CommonConstants.jsonNumberColorValue)),
      'literal': TextStyle(color: Color(CommonConstants.jsonBooleanColorValue)),
      'comment': TextStyle(
        color: Color(CommonConstants.jsonNullColorValue),
        fontStyle: FontStyle.italic,
      ),
    };
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

  static const Set<String> _separators = {
    ' ', '\t', '\n', '\r',
    '{', '}', '[', ']', ':', ',', '"',
  };

  bool _isWordChar(String char) {
    return !_separators.contains(char);
  }

  void _handlePointerDown(PointerDownEvent event) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isDoubleTap = _lastPointerDownPointer == event.pointer &&
        now - _lastPointerDownTime < 300;

    _lastPointerDownTime = now;
    _lastPointerDownPointer = event.pointer;

    if (isDoubleTap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _adjustWordSelection();
      });
    }
  }

  void _adjustWordSelection() {
    final selection = _controller.selection;
    if (selection.isCollapsed) return;

    final text = _controller.text;
    if (text.isEmpty) return;

    int start = selection.start;
    int end = selection.end;

    while (start > 0 && _isWordChar(text[start - 1])) {
      start--;
    }

    while (end < text.length && _isWordChar(text[end])) {
      end++;
    }

    if (start != selection.start || end != selection.end) {
      _controller.selection = TextSelection(
        baseOffset: start,
        extentOffset: end,
      );
    }
  }
}

/// 自定义 [CodeController]：拦截 Ctrl+F 打开自己的搜索栏，避免触发
/// flutter_code_editor 内置搜索框（它会弹出右下角覆盖层，而不是我们的组件）。
///
/// 搜索栏打开期间，编辑器聚焦时也能响应 Enter/Shift+Enter 导航与 Esc 关闭。
class _JsonCodeController extends CodeController {
  _JsonCodeController({required String text})
      : super(text: text, language: json_highlight.json);

  /// 搜索栏是否可见（由外部同步），用于决定 Enter/Esc 是否用于搜索。
  bool searchBarVisible = false;

  /// 当前命中的高亮数据（全文偏移，已排序且不重叠），由外部同步。
  List<TextRange> highlightMatches = const [];

  /// 当前命中在 [highlightMatches] 中的序号。
  int highlightCurrentIndex = -1;

  /// 更新搜索高亮并触发重绘（确保清空时高亮也能消失）。
  void updateSearchHighlight(List<TextRange> matches, int currentIndex) {
    highlightMatches = matches;
    highlightCurrentIndex = currentIndex;
    notifyListeners();
  }

  VoidCallback? onOpenSearch;
  VoidCallback? onCloseSearch;
  void Function(bool shift)? onNavigate;

  @override
  KeyEventResult onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      final ctrl = HardwareKeyboard.instance.isControlPressed;
      if (ctrl && event.logicalKey == LogicalKeyboardKey.keyF) {
        onOpenSearch?.call();
        return KeyEventResult.handled;
      }

      if (searchBarVisible) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          onCloseSearch?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          final shift = HardwareKeyboard.instance.isShiftPressed;
          onNavigate?.call(shift);
          return KeyEventResult.handled;
        }
      }
    }
    return super.onKey(event);
  }

  /// 在语法高亮之上叠加搜索高亮：所有命中用琥珀色，当前命中用主题色。
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool? withComposing,
  }) {
    final base = super.buildTextSpan(
      context: context,
      style: style,
      withComposing: withComposing,
    );
    if (highlightMatches.isEmpty) return base;
    return _applySearchHighlight(base, style);
  }

  TextSpan _applySearchHighlight(TextSpan base, TextStyle? rootStyle) {
    final matches = highlightMatches;
    final spans = <InlineSpan>[];
    int matchIndex = 0; // 下一个待处理的命中
    int offset = 0; // 当前叶子的全文起始偏移

    base.visitChildren((span) {
      if (span is! TextSpan) return true;
      final text = span.text;
      if (text == null || text.isEmpty) return true;
      final leafStyle = span.style;
      int local = 0;
      while (local < text.length) {
        if (matchIndex >= matches.length) {
          spans.add(TextSpan(text: text.substring(local), style: leafStyle));
          local = text.length;
          break;
        }
        final m = matches[matchIndex];
        final mStart = m.start - offset;
        final mEnd = m.end - offset;
        if (mEnd <= local) {
          matchIndex++;
          continue;
        }
        if (mStart > local) {
          final beforeEnd = math.min(mStart, text.length);
          spans.add(
            TextSpan(text: text.substring(local, beforeEnd), style: leafStyle),
          );
          local = beforeEnd;
          if (mStart >= text.length) break;
          continue;
        }
        // local 落在命中区间内
        final end = math.min(mEnd, text.length);
        final isCurrent = matchIndex == highlightCurrentIndex;
        final baseStyle = leafStyle ?? const TextStyle();
        // 文本编辑器无法画真边框，用上下装饰线模拟对象模式的「框」。
        final highlightStyle = isCurrent
            ? baseStyle.copyWith(
                backgroundColor: SearchHighlight.currentBackground,
                decoration: TextDecoration.combine([
                  TextDecoration.overline,
                  TextDecoration.underline,
                ]),
                decorationColor: SearchHighlight.currentFrameColor,
                decorationThickness: 1.5,
              )
            : baseStyle.copyWith(backgroundColor: SearchHighlight.matchBackground);
        spans.add(
          TextSpan(
            text: text.substring(local, end),
            style: highlightStyle,
          ),
        );
        local = end;
        if (end >= mEnd) matchIndex++;
      }
      offset += text.length;
      return true;
    });

    return TextSpan(children: spans, style: rootStyle);
  }
}
