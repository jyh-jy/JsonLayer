import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:json_layer/components/home/JsonEditor.dart';

Widget _host(String content, ValueChanged<String> onChanged) {
  return MaterialApp(
    home: Scaffold(
      body: JsonEditor(content: content, onChanged: onChanged),
    ),
  );
}

Finder _searchField() {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == '搜索',
  );
}

void main() {
  testWidgets('JSON 搜索连续输入时保持搜索框焦点且不修改正文', (tester) async {
    final changedContents = <String>[];
    const content = '{"apple":"apricot"}';

    await tester.pumpWidget(_host(content, changedContents.add));
    await tester.tap(find.byTooltip('搜索 (Ctrl+F)'));
    await tester.pump();

    final searchField = tester.widget<TextField>(_searchField());
    expect(searchField.focusNode?.hasFocus, isTrue);
    final focusChanges = <bool>[];
    searchField.focusNode?.addListener(
      () => focusChanges.add(searchField.focusNode!.hasFocus),
    );

    tester.testTextInput.enterText('a');
    await tester.pump();

    expect(searchField.focusNode?.hasFocus, isTrue);
    expect(focusChanges, isEmpty, reason: '收集命中期间搜索框不能短暂失焦，否则桌面端会全选旧查询');
    expect(
      searchField.controller?.selection,
      const TextSelection.collapsed(offset: 1),
      reason: '搜索框重新获得焦点会全选旧查询，下一次输入将覆盖而不是追加',
    );

    tester.testTextInput.enterText('ap');
    await tester.pump();

    expect(searchField.controller?.text, 'ap');
    expect(find.text('1/2'), findsOneWidget);
    expect(changedContents, isEmpty, reason: '搜索输入不能覆盖 JSON 正文');
  });

  testWidgets('JSON 搜索定位远处命中时滚动正文但不抢焦点', (tester) async {
    final entries = List.generate(
      80,
      (index) => '"key$index":"value$index"',
    ).join(',\n');

    await tester.pumpWidget(_host('{\n$entries\n}', (_) {}));
    await tester.tap(find.byTooltip('搜索 (Ctrl+F)'));
    await tester.pump();

    final searchField = tester.widget<TextField>(_searchField());
    tester.testTextInput.enterText('value79');
    await tester.pumpAndSettle();

    final verticalEditor = tester.widget<SingleChildScrollView>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.vertical &&
            widget.controller != null,
      ),
    );
    expect(verticalEditor.controller?.offset, greaterThan(0));
    expect(searchField.focusNode?.hasFocus, isTrue);
  });
}
