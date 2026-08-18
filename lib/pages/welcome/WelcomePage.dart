import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import 'package:json_layer/contants/CommonConstant.dart';
import 'package:json_layer/stores/WorkspaceStore.dart';

/// 首次引导页：选择工作空间存储位置。
///
/// 参考 APIFOX 离线空间对话框设计。
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _nameController = TextEditingController(text: 'JsonLayer 工作空间');
  final _pathController = TextEditingController();
  final _folderController = TextEditingController(text: 'JsonLayer');

  bool _isConfiguring = false;

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    _folderController.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) {
      setState(() {
        _pathController.text = path;
      });
    }
  }

  Future<void> _configure() async {
    final basePath = _pathController.text.trim();
    if (basePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择存储位置')),
      );
      return;
    }

    setState(() => _isConfiguring = true);
    try {
      final workspacePath = '$basePath\\${_folderController.text.trim().isEmpty ? CommonConstants.workspaceDirName : _folderController.text.trim()}';
      final store = context.read<WorkspaceStore>();
      await store.configureWorkspace(workspacePath);
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建工作空间失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isConfiguring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(theme),
              const SizedBox(height: 28),
              _buildForm(theme),
              const SizedBox(height: 24),
              _buildActions(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.data_object,
                color: theme.colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
            '${CommonConstants.appName} 离线空间',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '请设置工作空间存储位置，用于保存你的 JSON 文档和日志文件。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Color(CommonConstants.textSecondaryColorValue),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildField(
          theme: theme,
          label: '名称',
          required: true,
          controller: _nameController,
          hintText: '工作空间名称',
        ),
        const SizedBox(height: 16),
        _buildPathField(theme),
        const SizedBox(height: 16),
        _buildField(
          theme: theme,
          label: '目录名称',
          required: true,
          controller: _folderController,
          hintText: 'JsonLayer',
          suffixIcon: Icons.info_outline,
          helperText: '将在存储位置下创建此文件夹',
        ),
      ],
    );
  }

  Widget _buildField({
    required ThemeData theme,
    required String label,
    required TextEditingController controller,
    required String hintText,
    bool required = false,
    IconData? suffixIcon,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$label${required ? ' *' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (suffixIcon != null) ...[
              const SizedBox(width: 4),
              Icon(suffixIcon, size: 14, color: theme.colorScheme.primary),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hintText,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            helperText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Color(CommonConstants.textSecondaryColorValue),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPathField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '存储位置 *',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pathController,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: '请选择存储位置',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 38,
              child: OutlinedButton.icon(
                onPressed: _isConfiguring ? null : _pickDirectory,
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('浏览'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActions(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _isConfiguring ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _isConfiguring ? null : _configure,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          ),
          child: _isConfiguring
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('新建'),
        ),
      ],
    );
  }
}
