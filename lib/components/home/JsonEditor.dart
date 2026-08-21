import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/json.dart' as json_highlight;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:json_layer/components/common/EditorActionButton.dart';
import 'package:json_layer/components/common/EditorContextMenu.dart';
import 'package:json_layer/components/common/SearchBar.dart'
    show SearchQueryBar;
import 'package:json_layer/components/common/SafeSnackBar.dart';
import 'package:json_layer/components/common/SearchHighlight.dart';
import 'package:json_layer/contants/CommonConstant.dart';

/// 工具栏中会给出「成功回执」的动作。
enum _ToolbarAction { prompt, format, compress }

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
  final ScrollController _verticalScrollController = ScrollController();
  final FocusNode _editorFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();

  /// 搜索栏的撤销/重做控制器：由 JsonEditor 持有，以便当焦点在 JSON
  /// 主编辑器上时，Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y 也能路由到搜索框。
  final UndoHistoryController _searchUndoController = UndoHistoryController();
  int _lineCount = 1;
  String _longestLine = '';

  /// 编辑器内容的测量宽度（最长行的像素宽度），在文本变化时一次性计算，
  /// 避免每帧用 [IntrinsicWidth] 对整段文本做昂贵的固有宽度测量。
  double _contentWidth = 0;
  int _lastPointerDownTime = 0;
  int _lastPointerDownPointer = -1;

  /// 刚刚执行成功的工具栏动作（见 [_ToolbarAction]），用于让对应按钮的图标
  /// 短暂变成对勾。格式化/压缩这类「结果在下方文本里」的操作本身没有提示音
  /// 也没有 toast，靠这个回执让用户确认点到了。
  _ToolbarAction? _succeededAction;
  Timer? _successTimer;

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
    _longestLine = _computeLongestLine(_controller.text);
    _measureContentWidth();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(JsonEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content == _controller.text) return;

    // 输入法拼字进行中，绝对不能覆写 controller。
    //
    // 编辑内容会经 onChanged → TabStore → Consumer 重建回传到这里，回传途中
    // 用户往往还在拼字。此刻写 controller 会清空 composing，输入法以为字还没
    // 提交、敲定时再提交一次 —— 表现为「汉字出现两次 + 光标跳回第一行」。
    // 拼字结束后文本自然会再触发一次同步，什么都不做是安全的。
    if (_controller.value.composing.isValid) return;

    _syncExternalContent(widget.content);
    _updateLineCount();
    _measureContentWidth();
  }

  /// 用外部内容替换编辑器文本，并尽量保住光标位置。
  ///
  /// 不能用 `_controller.text = x`：它的 setter 会把 selection 重置成
  /// `collapsed(offset: -1)`（光标弹回开头），并清空 composing。
  void _syncExternalContent(String content) {
    final offset = _controller.selection.baseOffset.clamp(0, content.length);
    _controller.value = TextEditingValue(
      text: content,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _searchUndoController.dispose();
    _verticalScrollController.dispose();
    _lineNumberScrollController.dispose();
    _editorFocusNode.dispose();
    _searchFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _computeLongestLine(String text) => text.isEmpty
      ? ''
      : text.split('\n').reduce((a, b) => a.length > b.length ? a : b);

  void _onTextChanged() {
    _updateLineCount();
    final longest = _computeLongestLine(_controller.text);
    if (longest != _longestLine) {
      _longestLine = longest;
      _measureContentWidth();
      setState(() {});
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
      _scrollToMatch(range);
    }
  }

  /// 直接滚动正文视口，避免通过聚焦正文来触发框架的光标定位。
  ///
  /// 搜索框在 Windows 上重新获得焦点时会全选已有查询，下一次输入便会
  /// 覆盖旧字符；因此搜索导航期间不能让搜索框短暂失焦。
  void _scrollToMatch(TextRange range) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_verticalScrollController.hasClients) return;

      final prefix = _controller.text.substring(0, range.start);
      final lineIndex = '\n'.allMatches(prefix).length;
      final position = _verticalScrollController.position;
      final lineCenter =
          CommonConstants.editorContentVerticalPadding +
          (lineIndex + 0.5) * CommonConstants.editorLineHeight;
      final target = (lineCenter - position.viewportDimension / 2)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();

      if ((position.pixels - target).abs() < 1) return;
      _verticalScrollController.animateTo(
        target,
        duration: CommonConstants.searchNavigationAnimation,
        curve: Curves.easeOut,
      );
    });
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
    // Ctrl+F 打开搜索时：如果编辑器里有选中的文本（非零长度），直接回填到搜索词。
    // 省去手动复制粘贴。
    final sel = _controller.value.selection;
    if (sel.isValid && !sel.isCollapsed) {
      final picked = sel.textInside(_controller.text);
      if (picked.isNotEmpty) {
        _searchQuery = picked;
        // 已填词：立即算一次匹配，避免打开后显示"0 结果"再等用户输入。
        _recollectMatches();
      }
    }
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
    // Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y：当搜索栏可见时，优先让搜索框执行撤销/重做。
    // （即使焦点已经从搜索框移回 JSON 主编辑器，也能用同一个快捷键撤销刚才
    //  在搜索栏输入的内容，无需先手动把焦点移回搜索框。）
    final searchUndoResult = _tryHandleSearchUndoRedo(event);
    if (searchUndoResult == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
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
    // 原有快捷键：Ctrl+L 格式化（Ctrl+S 全局保存交给上层 HomePage 的 CallbackShortcuts，
    // 避免这里和上层重复写盘）
    if (event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyL) {
        _formatJson();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onEditorKeyEvent(FocusNode node, KeyEvent event) {
    // 主编辑器焦点内：搜索框撤销优先级高于主编辑器撤销
    final searchUndoResult = _tryHandleSearchUndoRedo(event);
    if (searchUndoResult == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
    return _controller.onKey(event);
  }

  /// 如果搜索栏打开且目标 undo/redo 键按下，调用搜索框 UndoHistoryController
  /// 执行撤销/重做，并返回 handled 让外层的主编辑器跳过默认的 Undo/Redo。
  /// 其它情况返回 ignored，让事件继续传播到主编辑器的默认处理。
  KeyEventResult _tryHandleSearchUndoRedo(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_showSearchBar) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (!ctrl) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final undoVal = _searchUndoController.value;

    // Ctrl+Z = Undo
    if (event.logicalKey == LogicalKeyboardKey.keyZ && !shift) {
      if (undoVal.canUndo) {
        _searchUndoController.undo();
        return KeyEventResult.handled;
      }
      // 搜索框撤销栈已经没有东西了：让主编辑器自己处理 Ctrl+Z
      return KeyEventResult.ignored;
    }
    // Ctrl+Shift+Z / Ctrl+Y = Redo
    final isRedo =
        (event.logicalKey == LogicalKeyboardKey.keyZ && shift) ||
        event.logicalKey == LogicalKeyboardKey.keyY;
    if (isRedo) {
      if (undoVal.canRedo) {
        _searchUndoController.redo();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
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
        initialQuery: _searchQuery,
        undoController: _searchUndoController,
        currentMatch: _currentMatchIndex < 0 ? null : _currentMatchIndex + 1,
        totalMatches: _matches.isEmpty && _searchQuery.trim().isEmpty
            ? null
            : _matches.length,
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
          EditorActionButton(
            icon: Icons.auto_awesome,
            tooltip: '生成提示词',
            color: Color(CommonConstants.actionPromptColorValue),
            succeeded: _succeededAction == _ToolbarAction.prompt,
            onTap: _generatePrompt,
          ),
          const EditorActionDivider(),
          EditorActionButton(
            icon: Icons.search,
            tooltip: _showSearchBar ? '关闭搜索 (Esc)' : '搜索 (Ctrl+F)',
            color: Color(CommonConstants.actionSearchColorValue),
            // 搜索栏展开时按钮常驻高亮，让「当前正在搜索」这一状态可见。
            active: _showSearchBar,
            onTap: () => _showSearchBar ? _closeSearch() : _openSearch(),
          ),
          EditorActionButton(
            icon: Icons.format_align_left,
            tooltip: '格式化 (Ctrl+L)',
            color: Color(CommonConstants.actionFormatColorValue),
            succeeded: _succeededAction == _ToolbarAction.format,
            onTap: _formatJson,
          ),
          EditorActionButton(
            icon: Icons.compress,
            tooltip: '压缩',
            color: Color(CommonConstants.actionCompressColorValue),
            succeeded: _succeededAction == _ToolbarAction.compress,
            onTap: _compressJson,
          ),
        ],
      ),
    );
  }

  /// 让 [action] 对应的按钮短暂显示对勾回执。重复触发会重置计时。
  void _flashSuccess(_ToolbarAction action) {
    _successTimer?.cancel();
    setState(() => _succeededAction = action);
    _successTimer = Timer(CommonConstants.successFlash, () {
      if (!mounted) return;
      setState(() => _succeededAction = null);
    });
  }

  // ---------------- 右键菜单 ----------------

  /// 内容区右键菜单：替换 Flutter 默认的英文系统选择工具条，改成与
  /// 左侧文件树、标签栏一致的中文菜单，并把编辑器自己的动作（搜索 /
  /// 格式化 / 压缩 / 生成提示词）一并挂上，省去一次到顶栏的往返。
  ///
  /// 剪切/复制/粘贴/全选的可用性与具体行为都复用 Flutter 计算好的
  /// [EditableTextState.contextMenuButtonItems]（它会考虑当前选区、只读
  /// 状态与剪贴板内容），我们只负责换一层皮。
  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final buttonItems = editableTextState.contextMenuButtonItems;

    VoidCallback? systemAction(ContextMenuButtonType type) {
      for (final item in buttonItems) {
        if (item.type == type) return item.onPressed;
      }
      return null; // Flutter 未提供该动作 → 条目置灰
    }

    /// 自定义动作统一先收起菜单再执行，避免菜单挡住结果。
    VoidCallback ownAction(VoidCallback action) {
      return () {
        editableTextState.hideToolbar();
        action();
      };
    }

    final selection = _controller.selection;
    final hasSelection = selection.isValid && !selection.isCollapsed;

    return EditorContextMenu(
      anchor: editableTextState.contextMenuAnchors.primaryAnchor,
      entries: [
        if (!widget.readOnly)
          EditorMenuEntry(
            label: '剪切',
            icon: Icons.content_cut,
            shortcut: 'Ctrl+X',
            onTap: systemAction(ContextMenuButtonType.cut),
          ),
        EditorMenuEntry(
          label: '复制',
          icon: Icons.content_copy,
          shortcut: 'Ctrl+C',
          onTap: systemAction(ContextMenuButtonType.copy),
        ),
        if (!widget.readOnly)
          EditorMenuEntry(
            label: '粘贴',
            icon: Icons.content_paste,
            shortcut: 'Ctrl+V',
            onTap: systemAction(ContextMenuButtonType.paste),
          ),
        EditorMenuEntry(
          label: '全选',
          icon: Icons.select_all,
          shortcut: 'Ctrl+A',
          onTap: systemAction(ContextMenuButtonType.selectAll),
        ),
        const EditorMenuDivider(),
        EditorMenuEntry(
          // 有选区时 _openSearch 会把选中的文字直接回填进搜索框
          label: hasSelection ? '搜索选中内容' : '搜索',
          icon: Icons.search,
          shortcut: 'Ctrl+F',
          color: Color(CommonConstants.actionSearchColorValue),
          onTap: ownAction(_openSearch),
        ),
        if (!widget.readOnly) ...[
          EditorMenuEntry(
            label: '格式化',
            icon: Icons.format_align_left,
            shortcut: 'Ctrl+L',
            color: Color(CommonConstants.actionFormatColorValue),
            onTap: ownAction(_formatJson),
          ),
          EditorMenuEntry(
            label: '压缩',
            icon: Icons.compress,
            color: Color(CommonConstants.actionCompressColorValue),
            onTap: ownAction(_compressJson),
          ),
        ],
        const EditorMenuDivider(),
        EditorMenuEntry(
          label: '生成提示词',
          icon: Icons.auto_awesome,
          color: Color(CommonConstants.actionPromptColorValue),
          onTap: ownAction(_generatePrompt),
        ),
      ],
    );
  }

  Widget _buildEditor(ThemeData theme) {
    final baseStyle = _baseStyle;
    final maxLines = math.max(_lineCount, 1);

    return Container(
      color: Color(CommonConstants.surfaceColorValue),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLineNumbers(CommonConstants.editorLineHeight),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewportWidth = constraints.maxWidth;
                final editorWidth = _contentWidth < viewportWidth
                    ? viewportWidth
                    : _contentWidth;
                return Column(
                  children: [
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollUpdateNotification) {
                            // 外层垂直 SingleChildScrollView 的滚动位置同步给行号
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
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: editorWidth,
                                  child: Listener(
                                    onPointerDown: _handlePointerDown,
                                    child: TextField(
                                      focusNode: _editorFocusNode,
                                      controller: _controller,
                                      readOnly: widget.readOnly,
                                      maxLines: maxLines,
                                      style: baseStyle,
                                      cursorColor: Color(
                                        CommonConstants.textPrimaryColorValue,
                                      ),
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      contextMenuBuilder: _buildContextMenu,
                                      decoration: const InputDecoration(
                                        isCollapsed: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: CommonConstants
                                              .editorContentVerticalPadding,
                                        ),
                                        disabledBorder: InputBorder.none,
                                        border: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                      ),
                                      onChanged: widget.onChanged,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 编辑器文本样式（提取为 getter，供宽度测量复用同一套字体参数）。
  TextStyle get _baseStyle => TextStyle(
    fontFamily: 'Consolas',
    fontSize: CommonConstants.editorFontSize,
    color: Color(CommonConstants.textPrimaryColorValue),
    height: 1.5,
  );

  /// 用 [TextPainter] 一次性测量最长行的像素宽度。
  ///
  /// 结果缓存到 [_contentWidth]，布局时直接用 [SizedBox] 固定宽度给
  /// [TextField]，让其 scrollController（水平方向）自然溢出，避免嵌套
  /// 横向 SingleChildScrollView 的双滚动开销。
  void _measureContentWidth() {
    final text = _longestLine;
    if (text.isEmpty) {
      _contentWidth = 0;
      return;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: _baseStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _contentWidth = painter.width + 24; // 右侧留白，避免行尾光标/选区被裁切。
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
      _syncExternalContent(formatted);
      widget.onChanged(formatted);
      _flashSuccess(_ToolbarAction.format);
    } catch (e) {
      SafeSnackBar.show(
        context,
        message: '格式化失败: $e',
        idempotencyKey: 'format_failed',
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  void _compressJson() {
    try {
      final text = _controller.text.trim();
      if (text.isEmpty) return;
      final decoded = jsonDecode(text);
      final compressed = jsonEncode(decoded);
      _syncExternalContent(compressed);
      widget.onChanged(compressed);
      _flashSuccess(_ToolbarAction.compress);
    } catch (e) {
      SafeSnackBar.show(
        context,
        message: '压缩失败: $e',
        idempotencyKey: 'compress_failed',
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  /// 生成提示词：将用户预设的提示词 + 当前 JSON 内容一起复制到剪贴板。
  ///
  /// 配合顶栏右侧的 DeepSeek 入口使用：点此按钮复制 → 点 DeepSeek 打开官网 →
  /// 在 DP 输入框中粘贴，即可直接询问 AI。
  Future<void> _generatePrompt() async {
    final jsonContent = _controller.text.trim();
    if (jsonContent.isEmpty) {
      SafeSnackBar.show(
        context,
        message: 'JSON 内容为空，无法生成提示词',
        idempotencyKey: 'prompt_empty',
        backgroundColor: Theme.of(context).colorScheme.error,
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final presetPrompt =
        (prefs.getString(CommonConstants.presetPromptKey) ??
                CommonConstants.defaultPresetPrompt)
            .trim();

    // 预设提示词非空时：提示词 + 换行 + JSON 内容；否则只复制 JSON 内容
    final combined = presetPrompt.isEmpty
        ? jsonContent
        : '$presetPrompt\n\n$jsonContent';

    await Clipboard.setData(ClipboardData(text: combined));
    if (!mounted) return;
    _flashSuccess(_ToolbarAction.prompt);
    SafeSnackBar.show(
      context,
      message: presetPrompt.isEmpty
          ? '已复制 JSON 内容到剪贴板（未设置提示词）'
          : '已复制提示词 + JSON 内容到剪贴板，点击右上角 DeepSeek 即可粘贴提问',
      idempotencyKey: 'prompt_copied',
    );
  }

  static const Set<String> _separators = {
    ' ',
    '\t',
    '\n',
    '\r',
    '{',
    '}',
    '[',
    ']',
    ':',
    ',',
    '"',
  };

  bool _isWordChar(String char) {
    return !_separators.contains(char);
  }

  void _handlePointerDown(PointerDownEvent event) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isDoubleTap =
        _lastPointerDownPointer == event.pointer &&
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

  @override
  set value(TextEditingValue newValue) {
    final currentValue = super.value;
    final onlyComposingChanged =
        newValue.text == currentValue.text &&
        newValue.selection == currentValue.selection &&
        newValue.composing != currentValue.composing;

    if (!onlyComposingChanged) {
      super.value = newValue;
      return;
    }

    // flutter_code_editor 0.3.5 会忽略仅 composing 变化的更新。Windows
    // 输入法确认候选时常只清空 composing；若未接收，输入法会再次提交汉字。
    // 临时翻转不影响显示的 selection 元数据，让父类接收 composing 后立即复原。
    final selection = newValue.selection;
    final forcedSelection = TextSelection(
      baseOffset: selection.baseOffset,
      extentOffset: selection.extentOffset,
      affinity: selection.affinity,
      isDirectional: !selection.isDirectional,
    );
    super.value = newValue.copyWith(selection: forcedSelection);
    super.value = newValue;
  }

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
            : baseStyle.copyWith(
                backgroundColor: SearchHighlight.matchBackground,
              );
        spans.add(
          TextSpan(text: text.substring(local, end), style: highlightStyle),
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
