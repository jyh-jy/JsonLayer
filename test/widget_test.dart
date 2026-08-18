import 'package:flutter_test/flutter_test.dart';

import 'package:json_layer/main.dart';

void main() {
  testWidgets('JsonLayerApp 根组件可正常构建', (WidgetTester tester) async {
    await tester.pumpWidget(const JsonLayerApp());
    // 等待 FutureBuilder 完成一帧
    await tester.pump();

    // 验证应用可构建（不抛异常即通过）
    expect(find.byType(JsonLayerApp), findsOneWidget);
  });
}
