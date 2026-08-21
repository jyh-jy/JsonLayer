import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:json_layer/components/common/EditorActionButton.dart';
import 'package:json_layer/components/common/EditorContextMenu.dart';
import 'package:json_layer/components/common/SearchBar.dart'
    show SearchQueryBar;
import 'package:json_layer/components/common/SearchHighlight.dart';
import 'package:json_layer/contants/CommonConstant.dart';

/// 对象模式编辑器（树形展示 JSON 结构，参考 APIFOX 对象模式）。
///
/// 只读模式下仍支持折叠/展开 []/{} 与搜索；可编辑模式下额外支持新增字段。
class ObjectTreeEditor extends StatefulWidget {
  final String content;
  final ValueChanged<String> onChanged;
  final String title;
  final bool readOnly;

  const ObjectTreeEditor({
    super.key,
    required this.content,
    required this.onChanged,
    this.title = '',
    this.readOnly = false,
  });

  @override
  State<ObjectTreeEditor> createState() => _ObjectTreeEditorState();
}

class _ObjectTreeEditorState extends State<ObjectTreeEditor> {
  late Map<String, dynamic> _parsed;
  String? _errorMessage;

  final FocusNode _focusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();

  /// 搜索框的撤销/重做控制器（即便焦点不在搜索框也能 Ctrl+Z 撤回搜索词）。
  final UndoHistoryController _searchUndoController = UndoHistoryController();
  final Set<String> _collapsedPaths = {};

  /// 内容宽度（横向滚动内容总宽），在内容变化时一次性测量，避免每帧重算。
  double _contentWidth = 0;

  /// 等宽字体（Consolas 13）单字符宽度，测量一次复用。
  double _charWidth = 8;

  /// 类型徽标（含 margin/padding）估算宽度，宁可偏大以免横向溢出。
  double _badgeWidth = 64;

  // 搜索相关状态
  bool _showSearchBar = false;
  String _searchQuery = '';
  bool _caseSensitive = false;
  bool _isRegex = false;
  final List<MatchInfo> _matches = [];
  final Map<String, int> _matchIndexByKey =
      {}; // "path:kind" -> index in _matches
  int _currentMatchIndex = -1;
  final ScrollController _treeScrollController = ScrollController();
  final Map<int, GlobalKey> _matchKeys = {};

  /// 对象模式中用户最近一次在 SelectionArea 里选中的纯文本。
  /// 用 SelectionArea.onSelectionChanged 回调实时更新，
  /// 避免使用高版本 Flutter 才有的 SelectionContainer.getSelectedContent()
  /// （本项目 SDK 还不支持该方法，编译会报 undefined_method）。
  String _lastSelectedText = '';

  @override
  void initState() {
    super.initState();
    _parsed = _parseContent(widget.content);
    _measureContentWidth();
  }

  @override
  void didUpdateWidget(ObjectTreeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 完全相同的字符串直接短路：identical（同一对象）先命中 O(1)，
    // 再退化为逐字符比对，避免大 JSON 反复 parse + recollect。
    if (identical(widget.content, oldWidget.content) ||
        widget.content == oldWidget.content) {
      return;
    }
    _parsed = _parseContent(widget.content);
    _measureContentWidth();
    _recollectMatches();
  }

  @override
  void dispose() {
    _treeScrollController.dispose();
    _searchUndoController.dispose();
    _focusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Map<String, dynamic> _parseContent(String content) {
    if (content.trim().isEmpty) {
      _errorMessage = null;
      return {};
    }
    try {
      final decoded = jsonDecode(content);
      _errorMessage = null;
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return {'value': decoded};
    } catch (e) {
      _errorMessage = e.toString();
      return {};
    }
  }

  // ---------------- 搜索核心逻辑 ----------------

  /// 根据当前设置重新收集所有匹配项
  void _recollectMatches() {
    _matches.clear();
    _matchIndexByKey.clear();
    _matchKeys.clear();
    _currentMatchIndex = -1;

    final q = _searchQuery.trim();
    if (q.isEmpty) {
      setState(() {});
      return;
    }

    RegExp? regex;
    try {
      if (_isRegex) {
        regex = RegExp(q, caseSensitive: _caseSensitive, multiLine: false);
      }
    } catch (_) {
      regex = null;
    }

    bool matches(String text) {
      if (_isRegex) {
        final r = regex;
        if (r == null) return false;
        return r.hasMatch(text);
      }
      return _caseSensitive
          ? text.contains(q)
          : text.toLowerCase().contains(q.toLowerCase());
    }

    void record(String text, String kind, String path) {
      if (matches(text)) {
        final lookup = '$path:$kind';
        final idx = _matches.length;
        final gk = GlobalKey(debugLabel: 'match_$idx');
        _matchKeys[idx] = gk;
        _matchIndexByKey[lookup] = idx;
        _matches.add(MatchInfo(text: text, kind: kind, path: path, key: gk));
      }
    }

    void walk(dynamic node, String path) {
      if (node is Map<String, dynamic>) {
        for (final e in node.entries) {
          final keyPath = '$path.${e.key}';
          record(e.key, 'key', keyPath);
          walk(e.value, keyPath);
        }
      } else if (node is List) {
        for (var i = 0; i < node.length; i++) {
          final p = '$path[$i]';
          walk(node[i], p);
        }
      } else {
        final text = node == null ? 'null' : jsonEncode(node);
        record(text, 'value', path);
      }
    }

    walk(_parsed, 'root');

    if (_matches.isNotEmpty) {
      _currentMatchIndex = 0;
    }
    setState(() {});
  }

  void _gotoMatch(int index) {
    if (index < 0 || index >= _matches.length) return;
    _currentMatchIndex = index;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetKey = _matchKeys[index];
      if (targetKey == null) return;
      final ctx = targetKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: Listener(
        // 点击编辑器任意位置即聚焦，保证 Ctrl+F 能被捕获。
        onPointerDown: (_) => _focusNode.requestFocus(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(theme),
            if (_showSearchBar) _buildSearchBarWrap(theme),
            Expanded(
              // 用 SelectionArea 包裹整棵树：一个系统选择区域即可让所有
              // Text/Text.rich 都支持鼠标拖拽选择和复制，性能远好于每个
              // 节点都用 SelectableText（后者会为每个节点建立独立的选择状态）。
              child: SelectionArea(
                contextMenuBuilder: _buildContextMenu,
                onSelectionChanged: (content) {
                  // 实时记录最近在对象模式下选中的文本（用于 Ctrl+F 自动回填）
                  _lastSelectedText = content?.plainText ?? '';
                },
                child: _buildTree(theme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y：搜索栏打开时优先让搜索框撤销/重做，
    // 即便焦点已经移到了树上也能直接撤回刚才输入的搜索词。
    final searchUndoResult = _tryHandleSearchUndoRedo(event);
    if (searchUndoResult == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      final ctrl = HardwareKeyboard.instance.isControlPressed;
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (ctrl && event.logicalKey == LogicalKeyboardKey.keyF) {
        _openSearch(context);
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
    return KeyEventResult.ignored;
  }

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

  void _openSearch(BuildContext context) {
    // Ctrl+F 打开搜索时：如果对象模式的 SelectionArea 里最近有选中文本，
    // 直接回填到搜索词，省去手动复制粘贴。
    //
    // 选中词通过 SelectionArea.onSelectionChanged 缓存在
    // _lastSelectedText 里，不依赖高版本 Flutter 才有
    // SelectionContainer.getSelectedContent() API。
    final picked = _lastSelectedText;
    if (picked.isNotEmpty) {
      _searchQuery = picked;
      _recollectMatches();
    }
    setState(() => _showSearchBar = true);
    // 唤起后让输入框自动获得焦点，用户无需再点击输入框。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    setState(() {
      _showSearchBar = false;
      _searchQuery = '';
      _caseSensitive = false;
      _isRegex = false;
      _matches.clear();
      _matchKeys.clear();
      _currentMatchIndex = -1;
    });
  }

  void _nextMatch() {
    if (_matches.isEmpty) return;
    final next = (_currentMatchIndex + 1) % _matches.length;
    _gotoMatch(next);
  }

  void _prevMatch() {
    if (_matches.isEmpty) return;
    final prev = _currentMatchIndex <= 0
        ? _matches.length - 1
        : _currentMatchIndex - 1;
    _gotoMatch(prev);
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      height: CommonConstants.editorHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Color(CommonConstants.sidebarColorValue),
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
          if (widget.readOnly) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Text(
                '只读',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
            ),
          ],
          const Spacer(),
          EditorActionButton(
            icon: Icons.search,
            tooltip: _showSearchBar ? '关闭搜索 (Esc)' : '搜索 (Ctrl+F)',
            color: Color(CommonConstants.actionSearchColorValue),
            active: _showSearchBar,
            onTap: () => _showSearchBar ? _closeSearch() : _openSearch(context),
          ),
          if (!widget.readOnly)
            EditorActionButton(
              icon: Icons.add,
              tooltip: '新增字段',
              color: Color(CommonConstants.actionAddColorValue),
              onTap: _addField,
            ),
        ],
      ),
    );
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

  /// 对象树的右键菜单：与 JSON 模式同款外观，但只保留树上有意义的动作
  /// （树本身不可直接输入，故无剪切/粘贴）。
  Widget _buildContextMenu(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    final buttonItems = selectableRegionState.contextMenuButtonItems;

    VoidCallback? systemAction(ContextMenuButtonType type) {
      for (final item in buttonItems) {
        if (item.type == type) return item.onPressed;
      }
      return null;
    }

    VoidCallback ownAction(VoidCallback action) {
      return () {
        selectableRegionState.hideToolbar();
        action();
      };
    }

    final hasSelection = _lastSelectedText.trim().isNotEmpty;

    return EditorContextMenu(
      anchor: selectableRegionState.contextMenuAnchors.primaryAnchor,
      entries: [
        EditorMenuEntry(
          label: '复制',
          icon: Icons.content_copy,
          shortcut: 'Ctrl+C',
          onTap: systemAction(ContextMenuButtonType.copy),
        ),
        EditorMenuEntry(
          label: '全选',
          icon: Icons.select_all,
          shortcut: 'Ctrl+A',
          onTap: systemAction(ContextMenuButtonType.selectAll),
        ),
        const EditorMenuDivider(),
        EditorMenuEntry(
          label: hasSelection ? '搜索选中内容' : '搜索',
          icon: Icons.search,
          shortcut: 'Ctrl+F',
          color: Color(CommonConstants.actionSearchColorValue),
          onTap: ownAction(() => _openSearch(context)),
        ),
        if (!widget.readOnly)
          EditorMenuEntry(
            label: '新增字段',
            icon: Icons.add,
            color: Color(CommonConstants.actionAddColorValue),
            onTap: ownAction(_addField),
          ),
      ],
    );
  }

  /// 测量内容宽度（横向滚动内容总宽），用于替代昂贵的 [IntrinsicWidth]。
  ///
  /// 所有文本均为等宽 Consolas 13，故宽度 = 字符数 × 单字符宽度；缩进与
  /// 徽标按固定像素叠加。只测最宽一行，远超递归布局的成本。
  void _measureContentWidth() {
    final painter = TextPainter(
      text: const TextSpan(
        text: 'M',
        style: TextStyle(fontFamily: 'Consolas', fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _charWidth = painter.width;

    final badgePainter = TextPainter(
      text: const TextSpan(
        text: 'boolean', // 最长的类型名
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // margin-left 8 + padding 8 + 文本宽度，另加少量安全余量。
    _badgeWidth = 16 + badgePainter.width + 4;

    var maxWidth = 0.0;
    // 内层滚动 padding.left 8 + 根对象 border 1。
    _measureObject(_parsed, 9, (w) {
      if (w > maxWidth) maxWidth = w;
    });
    // 右侧 padding 8 + 少量安全余量，避免搜索高亮边框等被裁切。
    _contentWidth = maxWidth + 12;
  }

  void _measureObject(
    Map<String, dynamic> map,
    double left,
    void Function(double) update,
  ) {
    final entries = map.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      _measureField(
        entries[i].key,
        entries[i].value,
        left,
        i == entries.length - 1,
        update,
      );
    }
  }

  void _measureField(
    String key,
    dynamic value,
    double left,
    bool isLast,
    void Function(double) update,
  ) {
    if (value is Map) {
      // 折叠头部行（对象）也可能是最宽一行，一并测量。
      update(left + 8 + 14 + (key.length + 5) * _charWidth + _badgeWidth);
      _measureObject(Map<String, dynamic>.from(value), left + 17, update);
    } else if (value is List) {
      update(
        left +
            8 +
            14 +
            (key.length + 5) * _charWidth +
            _measureBadgeWidth(_arrayTypeLabel(value)),
      );
      for (var i = 0; i < value.length; i++) {
        final item = value[i];
        if (item is Map) {
          _measureObject(Map<String, dynamic>.from(item), left + 41, update);
        } else {
          _measureLeaf(null, item, left + 24, i == value.length - 1, update);
        }
      }
    } else {
      _measureLeaf(key, value, left + 8, isLast, update);
    }
  }

  void _measureLeaf(
    String? key,
    dynamic value,
    double left,
    bool isLast,
    void Function(double) update,
  ) {
    final valueText = value == null ? 'null' : jsonEncode(value);
    // key 显示为 "key"，另有 ': ' 两字符；末尾逗号占 1 字符。
    final keyChars = key == null ? 0 : key.length + 2 + 2;
    final trailing = isLast ? 0 : 1;
    final chars = keyChars + valueText.length + trailing;
    update(left + chars * _charWidth + _badgeWidth);
  }

  double _measureBadgeWidth(String label) {
    const baselineLength = 'boolean'.length;
    final extraCharacters = label.length - baselineLength;
    return _badgeWidth +
        (extraCharacters > 0 ? extraCharacters * _charWidth : 0);
  }

  String _arrayTypeLabel(List<dynamic> value) => 'Array[${value.length}]';

  Widget _buildTree(ThemeData theme) {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('JSON 解析失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(_errorMessage!, style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    if (_parsed.isEmpty && widget.content.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schema,
              size: 48,
              color: Color(CommonConstants.textSecondaryColorValue),
            ),
            const SizedBox(height: 12),
            Text(
              '暂无数据',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Color(CommonConstants.textSecondaryColorValue),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 用缓存的测量宽度替代 IntrinsicWidth，避免每次切换/布局都做
              // 一次昂贵的整树 speculative layout。
              final width = _contentWidth < constraints.maxWidth
                  ? constraints.maxWidth
                  : _contentWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                    minHeight: constraints.maxHeight,
                  ),
                  child: SizedBox(
                    width: width,
                    child: SingleChildScrollView(
                      controller: _treeScrollController,
                      padding: const EdgeInsets.all(8),
                      child: _buildObjectNode(
                        _parsed,
                        0,
                        isRoot: true,
                        path: 'root',
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildObjectNode(
    Map<String, dynamic> map,
    int depth, {
    bool isRoot = false,
    required String path,
  }) {
    final entries = map.entries.toList();
    final collapsed = _collapsedPaths.contains(path);

    return Container(
      margin: EdgeInsets.only(left: isRoot ? 0 : 16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Color(CommonConstants.borderColorValue),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text('{', style: _punctStyle()),
          ),
          if (collapsed)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Text(
                '{...}  ${entries.length} 项',
                style: TextStyle(
                  color: Color(CommonConstants.textSecondaryColorValue),
                  fontSize: 12,
                ),
              ),
            )
          else
            ...entries.asMap().entries.map((entry) {
              final index = entry.key;
              final key = entry.value.key;
              final value = entry.value.value;
              final isLast = index == entries.length - 1;
              return _buildFieldRow(key, value, depth, isLast, '$path.$key');
            }),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('}', style: _punctStyle()),
            ),
        ],
      ),
    );
  }

  Widget _buildFieldRow(
    String key,
    dynamic value,
    int depth,
    bool isLast,
    String path,
  ) {
    final trailing = isLast ? '' : ',';

    if (value is Map) {
      final typedMap = Map<String, dynamic>.from(value);
      final collapsed = _collapsedPaths.contains(path);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCollapsibleHeader(
            key: key,
            collapsed: collapsed,
            openToken: '{',
            typeLabel: 'object',
            typeColor: Colors.purple,
            path: path,
          ),
          if (!collapsed) ...[
            _buildObjectNode(typedMap, depth + 1, path: path),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('}$trailing', style: _punctStyle()),
            ),
          ],
        ],
      );
    } else if (value is List) {
      final collapsed = _collapsedPaths.contains(path);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCollapsibleHeader(
            key: key,
            collapsed: collapsed,
            openToken: '[',
            typeLabel: _arrayTypeLabel(value),
            typeColor: Colors.teal,
            path: path,
          ),
          if (!collapsed) ...[
            ...value.asMap().entries.map((item) {
              final idx = item.key;
              final itemValue = item.value;
              final isLastItem = idx == value.length - 1;
              if (itemValue is Map) {
                return Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: _buildObjectNode(
                    Map<String, dynamic>.from(itemValue),
                    depth + 1,
                    path: '$path[$idx]',
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(left: 24, top: 2),
                child: Row(
                  children: [
                    _buildPrimitiveValue(itemValue, path: '$path[$idx]'),
                    if (!isLastItem) Text(',', style: _punctStyle()),
                  ],
                ),
              );
            }),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(']$trailing', style: _punctStyle()),
            ),
          ],
        ],
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(left: 8, top: 2),
        child: Row(
          children: [
            _highlightedText(
              '"$key"',
              _keyStyle(),
              lookupKey: '$path:key',
              rawSource: key,
            ),
            Text(': ', style: _punctStyle()),
            _buildPrimitiveValue(value, path: path),
            Text(trailing, style: _punctStyle()),
            _buildTypeBadge(_getTypeName(value), _getTypeColor(value)),
          ],
        ),
      );
    }
  }

  /// object/array 节点的可折叠头部（带展开/收起箭头）。
  Widget _buildCollapsibleHeader({
    required String key,
    required bool collapsed,
    required String openToken,
    required String typeLabel,
    required Color typeColor,
    required String path,
  }) {
    return InkWell(
      onTap: () => _toggleCollapse(path),
      child: Padding(
        padding: const EdgeInsets.only(left: 8, top: 4),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.keyboard_arrow_down,
              size: 14,
              color: Color(CommonConstants.textSecondaryColorValue),
            ),
            _highlightedText(
              '"$key"',
              _keyStyle(),
              lookupKey: '$path:key',
              rawSource: key,
            ),
            Text(': $openToken', style: _punctStyle()),
            if (collapsed)
              Text(
                ' ...',
                style: TextStyle(
                  color: Color(CommonConstants.textSecondaryColorValue),
                  fontSize: 12,
                ),
              ),
            _buildTypeBadge(typeLabel, typeColor),
          ],
        ),
      ),
    );
  }

  void _toggleCollapse(String path) {
    setState(() {
      if (!_collapsedPaths.remove(path)) {
        _collapsedPaths.add(path);
      }
    });
  }

  Widget _buildPrimitiveValue(dynamic value, {required String path}) {
    final color = _getTypeColor(value);
    final text = value == null ? 'null' : jsonEncode(value);
    return _highlightedText(
      text,
      TextStyle(color: color, fontFamily: 'Consolas', fontSize: 13),
      lookupKey: '$path:value',
      rawSource: text,
    );
  }

  /// 搜索高亮：命中关键字时用背景色标注；当前命中用主题色突出。
  ///
  /// [rawSource] 用于匹配的原始文本（不含外层包装字符，如无则同 text）
  /// [lookupKey]  唯一标识 "$path:$kind"，用于查询命中索引
  Widget _highlightedText(
    String text,
    TextStyle style, {
    required String lookupKey,
    required String rawSource,
  }) {
    final q = _searchQuery.trim();
    final matchIndex = _matchIndexByKey[lookupKey];
    final isCurrent = matchIndex != null && matchIndex == _currentMatchIndex;
    final gk = matchIndex != null ? _matchKeys[matchIndex] : null;

    Widget child;
    if (q.isEmpty || matchIndex == null) {
      child = Text(text, style: style);
    } else {
      child = _buildHighlightedRich(text, rawSource, q, style, isCurrent);
    }

    if (isCurrent && gk != null) {
      return Container(
        key: gk,
        decoration: BoxDecoration(
          color: SearchHighlight.currentFrameBackground,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: SearchHighlight.currentFrameColor,
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
        child: child,
      );
    }
    if (gk != null) {
      return Container(key: gk, child: child);
    }
    return child;
  }

  Widget _buildHighlightedRich(
    String display,
    String source,
    String query,
    TextStyle style,
    bool isCurrent,
  ) {
    final bg = isCurrent
        ? SearchHighlight.currentBackground
        : SearchHighlight.matchBackground;

    List<Match> findMatches(String src) {
      if (_isRegex) {
        try {
          return RegExp(
            query,
            caseSensitive: _caseSensitive,
          ).allMatches(src).toList();
        } catch (_) {
          return const [];
        }
      }
      final q = query;
      final result = <Match>[];
      int idx = 0;
      if (_caseSensitive) {
        while ((idx = src.indexOf(q, idx)) != -1) {
          result.add(src.substring(idx, idx + q.length).allMatches(src).first);
          idx += q.length;
        }
      } else {
        final lower = src.toLowerCase();
        final ql = q.toLowerCase();
        while ((idx = lower.indexOf(ql, idx)) != -1) {
          result.add(MatchImpl(idx, idx + q.length, src));
          idx += q.length;
        }
      }
      return result;
    }

    // 直接在 display 上找命中；对于 key 这种 display='"xxx"' 而 source='xxx' 的情况，
    // display 是包含 source 的，所以统一在 display 上匹配效果最直观。
    final matches = findMatches(display);
    if (matches.isEmpty) return Text(display, style: style);

    final spans = <TextSpan>[];
    int cursor = 0;
    for (final m in matches) {
      final s = m.start;
      final e = m.end;
      if (s > cursor) {
        spans.add(TextSpan(text: display.substring(cursor, s), style: style));
      }
      spans.add(
        TextSpan(
          text: display.substring(s, e),
          style: style.copyWith(backgroundColor: bg),
        ),
      );
      cursor = e;
    }
    if (cursor < display.length) {
      spans.add(TextSpan(text: display.substring(cursor), style: style));
    }
    return Text.rich(TextSpan(children: spans));
  }

  Widget _buildTypeBadge(String type, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  TextStyle _keyStyle() => TextStyle(
    color: Color(CommonConstants.jsonKeyColorValue),
    fontFamily: 'Consolas',
    fontSize: 13,
  );

  TextStyle _punctStyle() => TextStyle(
    color: Color(CommonConstants.jsonPunctuationColorValue),
    fontFamily: 'Consolas',
    fontSize: 13,
  );

  String _getTypeName(dynamic value) {
    if (value == null) return 'null';
    if (value is bool) return 'boolean';
    if (value is int) return 'integer';
    if (value is double) return 'float';
    if (value is num) return 'number';
    if (value is String) return 'string';
    return value.runtimeType.toString();
  }

  Color _getTypeColor(dynamic value) {
    if (value == null) return Color(CommonConstants.jsonNullColorValue);
    if (value is bool) return Color(CommonConstants.jsonBooleanColorValue);
    if (value is num) return Color(CommonConstants.jsonNumberColorValue);
    if (value is String) return Color(CommonConstants.jsonStringColorValue);
    return Colors.grey;
  }

  void _addField() {
    final controller = TextEditingController();
    final valueController = TextEditingController(text: '""');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          '新增字段',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: '字段名',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Color(CommonConstants.borderColorValue),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Color(CommonConstants.borderColorValue),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valueController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) =>
                  _confirmAddField(controller, valueController, ctx),
              decoration: InputDecoration(
                labelText: '默认值 (JSON 格式)',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Color(CommonConstants.borderColorValue),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Color(CommonConstants.borderColorValue),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              foregroundColor: Color(CommonConstants.textPrimaryColorValue),
              side: BorderSide(color: Color(CommonConstants.borderColorValue)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _confirmAddField(controller, valueController, ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _confirmAddField(
    TextEditingController controller,
    TextEditingController valueController,
    BuildContext ctx,
  ) {
    final key = controller.text.trim();
    if (key.isEmpty) return;
    dynamic defaultValue = '';
    try {
      defaultValue = jsonDecode(valueController.text.trim());
    } catch (_) {
      defaultValue = valueController.text;
    }
    setState(() {
      _parsed[key] = defaultValue;
      widget.onChanged(const JsonEncoder.withIndent('  ').convert(_parsed));
    });
    Navigator.pop(ctx);
  }
}

class MatchInfo {
  final String text;
  final String kind; // 'key' | 'value'
  final String path;
  final GlobalKey key;

  MatchInfo({
    required this.text,
    required this.kind,
    required this.path,
    required this.key,
  });
}

class MatchImpl implements Match {
  @override
  final int start;
  @override
  final int end;
  final String _input;

  MatchImpl(this.start, this.end, this._input);

  @override
  String? group(int groupNum) =>
      groupNum == 0 ? _input.substring(start, end) : null;

  @override
  String? operator [](int groupNum) => group(groupNum);

  @override
  int get groupCount => 0;

  @override
  List<String?> groups(List<int> groupIndices) =>
      groupIndices.map((i) => group(i)).toList();

  @override
  Pattern get pattern => RegExp('');

  @override
  String get input => _input;
}
