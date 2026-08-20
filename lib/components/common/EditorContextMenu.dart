import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:json_layer/contants/CommonConstant.dart';

/// 右键菜单节点基类（条目或分割线）。
sealed class EditorMenuNode {
  const EditorMenuNode();
}

/// 分割线。
class EditorMenuDivider extends EditorMenuNode {
  const EditorMenuDivider();
}

/// 一条可点击的菜单项。
///
/// [onTap] 为 null 表示该动作当前不可用（如未选中文本时的「复制」），
/// 条目会置灰且不响应悬停与点击。
class EditorMenuEntry extends EditorMenuNode {
  final String label;
  final IconData icon;

  /// 右侧的快捷键提示，如 `Ctrl+C`。
  final String? shortcut;

  /// 该动作的语义色，用于悬停时的图标染色；为 null 时用主色。
  final Color? color;

  final VoidCallback? onTap;

  const EditorMenuEntry({
    required this.label,
    required this.icon,
    this.shortcut,
    this.color,
    this.onTap,
  });

  bool get enabled => onTap != null;
}

/// 编辑器内容区的右键菜单，风格与 `WorkspaceTree` / `DocumentTabs` 的
/// [showMenu] 保持一致（同样的圆角、描边、行高与字号），替换掉 Flutter
/// 默认的 [AdaptiveTextSelectionToolbar]。
///
/// 用作 `TextField.contextMenuBuilder` / `SelectionArea.contextMenuBuilder`
/// 的返回值：这两个回调的结果会被塞进一个覆盖全屏的 Overlay，所以这里用
/// [Stack] + [Positioned] 自行定位，并在贴近屏幕右/下边缘时自动翻转。
class EditorContextMenu extends StatelessWidget {
  /// 菜单锚点（通常取 `contextMenuAnchors.primaryAnchor`，即右键位置）。
  final Offset anchor;

  final List<EditorMenuNode> entries;

  const EditorContextMenu({
    super.key,
    required this.anchor,
    required this.entries,
  });

  /// 预估菜单高度：条目与分割线的高度都是固定的，因此可以直接算出来，
  /// 无需等待一帧测量，定位时不会出现闪跳。
  double get _estimatedHeight {
    var height = CommonConstants.contextMenuVerticalPadding * 2;
    for (final entry in entries) {
      height += switch (entry) {
        EditorMenuDivider() => CommonConstants.contextMenuDividerHeight,
        EditorMenuEntry() => CommonConstants.menuItemHeight,
      };
    }
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    const margin = CommonConstants.contextMenuScreenMargin;
    const width = CommonConstants.contextMenuWidth;
    final height = _estimatedHeight;

    // 右/下边缘放不下时向左/上翻转，再兜底 clamp 一次防止溢出屏幕。
    var left = anchor.dx;
    if (left + width + margin > screen.width) {
      left = anchor.dx - width;
    }
    var top = anchor.dy;
    if (top + height + margin > screen.height) {
      top = anchor.dy - height;
    }
    left = left.clamp(margin, math.max(margin, screen.width - width - margin));
    top = top.clamp(margin, math.max(margin, screen.height - height - margin));

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: _MenuCard(entries: entries),
        ),
      ],
    );
  }
}

/// 菜单卡片本体，附带一个从锚点方向展开的淡入 + 微缩放入场动画。
class _MenuCard extends StatelessWidget {
  final List<EditorMenuNode> entries;

  const _MenuCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: CommonConstants.contextMenuAnimation,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.96 + 0.04 * t,
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: CommonConstants.contextMenuVerticalPadding,
          ),
          decoration: BoxDecoration(
            color: Color(CommonConstants.surfaceColorValue),
            borderRadius: BorderRadius.circular(
              CommonConstants.menuBorderRadius,
            ),
            border: Border.all(color: Color(CommonConstants.borderColorValue)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in entries)
                switch (entry) {
                  EditorMenuDivider() => const _MenuDividerLine(),
                  EditorMenuEntry() => _MenuItemTile(entry: entry),
                },
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuDividerLine extends StatelessWidget {
  const _MenuDividerLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: Color(CommonConstants.borderColorValue),
    );
  }
}

/// 单条菜单项：悬停时整行铺语义色淡底并给图标与文字染色。
class _MenuItemTile extends StatefulWidget {
  final EditorMenuEntry entry;

  const _MenuItemTile({required this.entry});

  @override
  State<_MenuItemTile> createState() => _MenuItemTileState();
}

class _MenuItemTileState extends State<_MenuItemTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final accent =
        entry.color ?? Color(CommonConstants.primaryColorValue);
    final enabled = entry.enabled;
    final highlighted = enabled && _hovered;

    final labelColor = enabled
        ? (highlighted
              ? accent
              : Color(CommonConstants.textPrimaryColorValue))
        : Color(
            CommonConstants.textSecondaryColorValue,
          ).withValues(alpha: CommonConstants.disabledOpacity);
    final iconColor = enabled
        ? (highlighted
              ? accent
              : Color(CommonConstants.textSecondaryColorValue))
        : Color(
            CommonConstants.textSecondaryColorValue,
          ).withValues(alpha: CommonConstants.disabledOpacity);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: entry.onTap,
        child: AnimatedContainer(
          duration: CommonConstants.hoverAnimation,
          curve: Curves.easeOut,
          height: CommonConstants.menuItemHeight,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: accent.withValues(
              alpha: highlighted ? CommonConstants.actionButtonHoverAlpha : 0,
            ),
            borderRadius: BorderRadius.circular(
              CommonConstants.actionButtonRadius,
            ),
          ),
          child: Row(
            children: [
              Icon(entry.icon, size: 16, color: iconColor),
              const SizedBox(width: CommonConstants.menuItemPadding),
              Expanded(
                child: Text(
                  entry.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: CommonConstants.menuFontSize,
                    color: labelColor,
                  ),
                ),
              ),
              if (entry.shortcut != null)
                Text(
                  entry.shortcut!,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: CommonConstants.contextMenuShortcutFontSize,
                    color: Color(
                      CommonConstants.textSecondaryColorValue,
                    ).withValues(
                      alpha: enabled ? 0.75 : CommonConstants.disabledOpacity,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
