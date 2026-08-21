import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:json_layer/components/home/JsonEditor.dart';

/// 取出 JsonEditor 内部 TextField 正在用的 controller。
/// TextField.controller 是公开字段，无需触碰私有 State。
TextEditingController _controllerOf(WidgetTester tester) {
  return tester.widget<TextField>(find.byType(TextField)).controller!;
}

Widget _host(String content, ValueChanged<String> onChanged) {
  return MaterialApp(
    home: Scaffold(
      body: JsonEditor(content: content, onChanged: onChanged),
    ),
  );
}

void main() {
  testWidgets('输入法拼字途中，外部内容回传不得打断 composing', (tester) async {
    // 复现真实链路：onChanged → TabStore → Consumer 重建 → didUpdateWidget，
    // 回传落地时用户往往还在拼字。曾经这里用 `_controller.text = x`，
    // 其 setter 会清空 composing 并把光标设为 offset -1，导致中文输入时
    // 「汉字出现两次 + 光标跳回第一行」。
    await tester.pumpWidget(_host('', (_) {}));
    await tester.tap(find.byType(TextField));
    await tester.pump();

    // 输入法拼字中：文本已有「中」，但仍处于未敲定的组合态
    const composing = TextEditingValue(
      text: '中',
      selection: TextSelection.collapsed(offset: 1),
      composing: TextRange(start: 0, end: 1),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();

    // 父组件带着「旧内容」重建（回传还没追上用户的击键）
    await tester.pumpWidget(_host('', (_) {}));
    await tester.pump();

    final controller = _controllerOf(tester);
    expect(
      controller.value.composing,
      const TextRange(start: 0, end: 1),
      reason: 'composing 被清空 → 输入法会把这个字再提交一次',
    );
    expect(controller.selection.baseOffset, 1, reason: '光标被重置 → 跳回第一行');
    expect(controller.text, '中', reason: '拼字中的文本不能被外部内容覆盖');
  });

  testWidgets('输入法确认候选时，必须接收只清空 composing 的更新', (tester) async {
    await tester.pumpWidget(_host('', (_) {}));
    await tester.tap(find.byType(TextField));
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '中文',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();

    // Windows 输入法确认候选时，文本和光标可能都不变，只清空 composing。
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '中文',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();

    final controller = _controllerOf(tester);
    expect(controller.text, '中文', reason: '候选文字只能提交一次');
    expect(
      controller.value.composing,
      TextRange.empty,
      reason: '必须通知 Windows 输入法本轮拼字已经结束',
    );
    expect(controller.selection.baseOffset, 2);
  });

  testWidgets('非拼字状态下，外部内容正常同步且光标不跳到开头', (tester) async {
    await tester.pumpWidget(_host('{"a":1}', (_) {}));
    await tester.tap(find.byType(TextField));
    await tester.pump();

    // 把光标放到中间，模拟用户正在某处编辑
    _controllerOf(tester).selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();

    // 外部推入新内容（如另一处触发了格式化）
    await tester.pumpWidget(_host('{"abc":123}', (_) {}));
    await tester.pump();

    final controller = _controllerOf(tester);
    expect(controller.text, '{"abc":123}', reason: '非拼字状态要正常同步');
    expect(
      controller.selection.baseOffset,
      5,
      reason: '光标应保持原位，而不是被 text setter 弹回开头',
    );
  });

  testWidgets('格式化后光标不弹回开头', (tester) async {
    await tester.pumpWidget(_host('{"a":1}', (_) {}));
    await tester.tap(find.byType(TextField));
    await tester.pump();

    _controllerOf(tester).selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();

    await tester.tap(find.byTooltip('格式化 (Ctrl+L)'));
    await tester.pump();

    final controller = _controllerOf(tester);
    expect(controller.text, contains('\n'), reason: '应已格式化');
    expect(controller.selection.baseOffset, 6);
  });
}
