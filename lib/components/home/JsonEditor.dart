import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/json.dart' as json_highlight;

import 'package:json_layer/components/common/SearchBar.dart' show SearchQueryBar;
import 'package:json_layer/contants/CommonConstant.dart';

/// JSON 文本编辑器组件（基于 flutter_code_editor）。
///
/// 特性：语法高亮、行号、花括号折叠、Ctrl+F 搜索（库内置）、
/// 格式化/压缩、Ctrl+Shift+L 格式化、Ctrl+S 保存。
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
  int _lineCount = 1;

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
    _lineNumberScrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _updateLineCount();
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
      _selectCurrent();
    }
    setState(() {});
  }

  void _selectCurrent() {
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _matches.length) return;
    final range = _matches[_currentMatchIndex];
    // 在下一帧设置 selection，避免和输入冲突
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _controller.selection = TextSelection(
          baseOffset: range.start,
          extentOffset: range.end,
          affinity: TextAffinity.downstream,
        );
        // 通过 bringIntoView 让光标所在位置滚动到可见
        _bringSelectionIntoView(range);
      } catch (_) {}
    });
  }

  Future<void> _bringSelectionIntoView(TextRange range) async {
    // Flutter 的 TextField 会在 selection 变化时自动滚动
    await Future.delayed(const Duration(milliseconds: 20));
    if (!mounted) return;
    // 尝试再设置一次触发滚动
    try {
      _controller.selection = TextSelection.collapsed(
        offset: range.start,
      );
      await Future.delayed(const Duration(milliseconds: 10));
      if (!mounted) return;
      _controller.selection = TextSelection(
        baseOffset: range.start,
        extentOffset: range.end,
      );
    } catch (_) {}
  }

  void _nextMatch() {
    if (_matches.isEmpty) return;
    _currentMatchIndex = (_currentMatchIndex + 1) % _matches.length;
    setState(() {});
    _selectCurrent();
  }

  void _prevMatch() {
    if (_matches.isEmpty) return;
    _currentMatchIndex = _currentMatchIndex <= 0
        ? _matches.length - 1
        : _currentMatchIndex - 1;
    setState(() {});
    _selectCurrent();
  }

  void _openSearch() {
    setState(() => _showSearchBar = true);
    _controller.searchBarVisible = true;
  }

  void _closeSearch() {
    _controller.searchBarVisible = false;
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
    // 原有快捷键：Ctrl+Shift+L 格式化、Ctrl+S 保存
    if (event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed) {
      final s = HardwareKeyboard.instance.isShiftPressed;
      if (s && event.logicalKey == LogicalKeyboardKey.keyL) {
        _formatJson();
        return KeyEventResult.handled;
      }
      if (!s && event.logicalKey == LogicalKeyboardKey.keyS) {
        widget.onSave?.call();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
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
    final lineHeight = 13 * 1.5;

    return Container(
      color: Color(CommonConstants.surfaceColorValue),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLineNumbers(lineHeight),
          Expanded(
            child: NotificationListener<ScrollNotification>(
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
                child: CodeField(
                  controller: _controller,
                  readOnly: widget.readOnly,
                  expands: true,
                  textStyle: baseStyle,
                  background: Color(CommonConstants.surfaceColorValue),
                  gutterStyle: GutterStyle(
                    showLineNumbers: false,
                    showFoldingHandles: false,
                    showErrors: false,
                    width: 0,
                  ),
                  onChanged: widget.onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
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
}
