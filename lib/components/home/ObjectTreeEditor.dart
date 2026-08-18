import 'dart:convert';

import 'package:flutter/material.dart';

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

  final Set<String> _collapsedPaths = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _parsed = _parseContent(widget.content);
  }

  @override
  void didUpdateWidget(ObjectTreeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != oldWidget.content) {
      _parsed = _parseContent(widget.content);
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(theme),
        Expanded(child: _buildTree(theme)),
      ],
    );
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
          Text(widget.title, style: theme.textTheme.titleSmall),
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
          _buildSearchField(theme),
          if (!widget.readOnly) ...[
            const SizedBox(width: 4),
            _buildActionButton(
              theme,
              icon: Icons.add,
              tooltip: '新增字段',
              onTap: _addField,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return SizedBox(
      width: 180,
      height: 22,
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
        style: const TextStyle(fontSize: 11),
        decoration: InputDecoration(
          hintText: '搜索 key / value',
          prefixIcon: const Icon(Icons.search, size: 13),
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: BorderSide(color: Color(CommonConstants.borderColorValue)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: BorderSide(color: Color(CommonConstants.borderColorValue)),
          ),
        ),
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
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: Color(CommonConstants.textSecondaryColorValue)),
        ),
      ),
    );
  }

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
            Icon(Icons.schema, size: 48, color: Color(CommonConstants.textSecondaryColorValue)),
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

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _buildObjectNode(_parsed, 0, isRoot: true, path: 'root'),
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
          if (!isRoot)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '{',
                style: _punctStyle(),
              ),
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
          if (!isRoot && !collapsed)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '}',
                style: _punctStyle(),
              ),
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
            typeLabel: 'array',
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
                    _buildPrimitiveValue(itemValue),
                    if (!isLastItem)
                      Text(',', style: _punctStyle()),
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
            _highlightedText('"$key"', _keyStyle()),
            Text(': ', style: _punctStyle()),
            _buildPrimitiveValue(value),
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
            _highlightedText('"$key"', _keyStyle()),
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

  Widget _buildPrimitiveValue(dynamic value) {
    final color = _getTypeColor(value);
    final text = value == null ? 'null' : jsonEncode(value);
    return _highlightedText(text, TextStyle(color: color, fontFamily: 'Consolas', fontSize: 13));
  }

  /// 搜索高亮：命中关键字时用背景色标注。
  Widget _highlightedText(String text, TextStyle style) {
    final q = _searchQuery;
    if (q.isEmpty) return Text(text, style: style);
    final lower = text.toLowerCase();
    final ql = q.toLowerCase();
    if (!lower.contains(ql)) return Text(text, style: style);

    final spans = <TextSpan>[];
    int i = 0;
    while (i < text.length) {
      final idx = lower.indexOf(ql, i);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(i), style: style));
        break;
      }
      if (idx > i) {
        spans.add(TextSpan(text: text.substring(i, idx), style: style));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: style.copyWith(
          backgroundColor: Colors.amber.withValues(alpha: 0.5),
        ),
      ));
      i = idx + q.length;
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
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
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
        title: const Text('新增字段'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: '字段名'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: valueController,
              decoration: const InputDecoration(labelText: '默认值 (JSON 格式)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
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
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
