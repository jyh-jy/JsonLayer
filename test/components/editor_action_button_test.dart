import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:json_layer/components/common/EditorActionButton.dart';
import 'package:json_layer/contants/CommonConstant.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('默认展示原图标，成功态切换为对勾', (tester) async {
    await tester.pumpWidget(
      _wrap(
        EditorActionButton(
          icon: Icons.format_align_left,
          tooltip: '格式化 (Ctrl+L)',
          color: Color(CommonConstants.actionFormatColorValue),
          onTap: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.format_align_left), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    await tester.pumpWidget(
      _wrap(
        EditorActionButton(
          icon: Icons.format_align_left,
          tooltip: '格式化 (Ctrl+L)',
          color: Color(CommonConstants.actionFormatColorValue),
          succeeded: true,
          onTap: () {},
        ),
      ),
    );
    // AnimatedSwitcher 交叉淡入，跑完动画后只剩对勾
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.format_align_left), findsNothing);
  });

  testWidgets('点击触发回调', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        EditorActionButton(
          icon: Icons.search,
          tooltip: '搜索 (Ctrl+F)',
          color: Color(CommonConstants.actionSearchColorValue),
          onTap: () => taps++,
        ),
      ),
    );

    await tester.tap(find.byType(EditorActionButton));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('激活态给按钮铺上语义色淡底', (tester) async {
    const accent = Color(CommonConstants.actionSearchColorValue);

    Color? backgroundOf(WidgetTester tester) {
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(EditorActionButton),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (container.decoration as BoxDecoration?)?.color;
    }

    await tester.pumpWidget(
      _wrap(
        EditorActionButton(
          icon: Icons.search,
          tooltip: '搜索',
          color: accent,
          onTap: () {},
        ),
      ),
    );
    expect(backgroundOf(tester)?.a, 0);

    await tester.pumpWidget(
      _wrap(
        EditorActionButton(
          icon: Icons.search,
          tooltip: '搜索',
          color: accent,
          active: true,
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      backgroundOf(tester)?.a,
      closeTo(CommonConstants.actionButtonActiveAlpha, 0.001),
    );
  });
}
