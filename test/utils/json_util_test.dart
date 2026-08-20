import 'package:flutter_test/flutter_test.dart';
import 'package:json_layer/utils/JsonUtil.dart';

void main() {
  group('JsonUtil', () {
    test('全空白输入按空内容处理', () {
      expect(() => JsonUtil.format(' \n\t '), throwsA(isA<FormatException>()));
      expect(JsonUtil.compress(' \n\t '), isEmpty);
      expect(JsonUtil.validate(' \n\t '), '输入为空');
    });
  });
}
