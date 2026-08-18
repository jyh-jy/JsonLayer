import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/json.dart' as json_highlight;

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
  late CodeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CodeController(
      text: widget.content,
      language: json_highlight.json,
    );
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
    _controller.dispose();
    super.dispose();
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

    return Focus(
      onKeyEvent: _onKeyEvent,
      child: CodeTheme(
        data: CodeThemeData(styles: _buildHighlightStyles()),
        child: CodeField(
          controller: _controller,
          readOnly: widget.readOnly,
          expands: true,
          textStyle: baseStyle,
          background: Color(CommonConstants.surfaceColorValue),
          gutterStyle: GutterStyle(
            showLineNumbers: true,
            showFoldingHandles: true,
            showErrors: false,
            width: 64,
            background: Color(CommonConstants.sidebarColorValue),
            textStyle: TextStyle(
              color: Color(CommonConstants.textSecondaryColorValue),
            ),
          ),
          onChanged: widget.onChanged,
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

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (shift && event.logicalKey == LogicalKeyboardKey.keyL) {
        _formatJson();
        return KeyEventResult.handled;
      }
      if (!shift && event.logicalKey == LogicalKeyboardKey.keyS) {
        widget.onSave?.call();
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
