import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:json_layer/components/common/EditorContextMenu.dart';

const Size _screen = Size(800, 600);

Widget _wrap(EditorContextMenu menu) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(size: _screen),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: menu,
    ),
  ),
);

void main() {
  testWidgets('渲染条目、快捷键与分割线', (tester) async {
    await tester.pumpWidget(
      _wrap(
        EditorContextMenu(
          anchor: const Offset(20, 20),
          entries: [
            EditorMenuEntry(
              label: '复制',
              icon: Icons.content_copy,
              shortcut: 'Ctrl+C',
              onTap: () {},
            ),
            const EditorMenuDivider(),
            EditorMenuEntry(
              label: '格式化',
              icon: Icons.format_align_left,
              shortcut: 'Ctrl+L',
              onTap: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('Ctrl+C'), findsOneWidget);
    expect(find.text('格式化'), findsOneWidget);
    expect(find.byIcon(Icons.content_copy), findsOneWidget);
  });

  testWidgets('onTap 为 null 的条目不可点击', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        EditorContextMenu(
          anchor: const Offset(20, 20),
          entries: [
            const EditorMenuEntry(
              label: '粘贴',
              icon: Icons.content_paste,
              onTap: null, // 剪贴板为空 → 置灰
            ),
            EditorMenuEntry(
              label: '全选',
              icon: Icons.select_all,
              onTap: () => taps++,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('粘贴'));
    await tester.pump();
    expect(taps, 0);

    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('锚点贴近右下角时菜单翻转，不溢出屏幕', (tester) async {
    await tester.pumpWidget(
      _wrap(
        EditorContextMenu(
          // 右下角：向右向下都放不下，必须往左上翻
          anchor: const Offset(795, 595),
          entries: [
            EditorMenuEntry(label: '复制', icon: Icons.content_copy, onTap: () {}),
            const EditorMenuDivider(),
            EditorMenuEntry(label: '全选', icon: Icons.select_all, onTap: () {}),
            EditorMenuEntry(label: '搜索', icon: Icons.search, onTap: () {}),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['复制', '全选', '搜索']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0), reason: '$label 左侧溢出');
      expect(rect.right, lessThanOrEqualTo(_screen.width), reason: '$label 右侧溢出');
      expect(rect.top, greaterThanOrEqualTo(0), reason: '$label 顶部溢出');
      expect(
        rect.bottom,
        lessThanOrEqualTo(_screen.height),
        reason: '$label 底部溢出',
      );
    }
  });
}
