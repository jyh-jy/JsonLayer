import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:json_layer/components/home/ObjectTreeEditor.dart';

Widget _host(String content) {
  return MaterialApp(
    home: Scaffold(
      body: ObjectTreeEditor(content: content, onChanged: (_) {}),
    ),
  );
}

void main() {
  testWidgets('对象模式显示数组元素数量', (tester) async {
    await tester.pumpWidget(_host('{"items":[1,2,3],"empty":[]}'));

    expect(find.text('Array[3]'), findsOneWidget);
    expect(find.text('Array[0]'), findsOneWidget);
    expect(find.text('array'), findsNothing);
  });

  testWidgets('对象模式的顶层数组显示元素数量', (tester) async {
    await tester.pumpWidget(_host('[{"id":1},{"id":2}]'));

    expect(find.text('Array[2]'), findsOneWidget);
  });
}
