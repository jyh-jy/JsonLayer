import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:json_layer/components/home/JsonEditor.dart';
import 'package:json_layer/contants/CommonConstant.dart';

void main() {
  testWidgets('未配置提示词时使用默认提示词生成内容', (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JsonEditor(content: '{"a":1}', onChanged: (_) {}),
        ),
      ),
    );

    await tester.tap(find.byTooltip('生成提示词'));
    await tester.pumpAndSettle();

    expect(clipboardText, '${CommonConstants.defaultPresetPrompt}\n\n{"a":1}');
  });
}
