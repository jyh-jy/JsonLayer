import 'dart:convert';

import 'package:json_layer/contants/CommonConstant.dart';

/// JSON 处理工具类（基础设施层，无业务依赖）。
///
/// 依据 ARCHITECTURE.md「utils/」规范：
/// - 与业务无关的通用能力。
/// - 顶层单例 `JsonUtil` 暴露能力。
class JsonUtil {
  JsonUtil._();

  /// 将任意 JSON 字符串格式化为带缩进的易读形式。
  ///
  /// - 自动去除前后空白与 BOM。
  /// - 解析失败抛出 [FormatException]，由调用方 catch 提示用户。
  /// - [indentSpaces] 缩进空格数，默认 2。
  static String format(String raw, {int indentSpaces = CommonConstants.defaultIndentSpaces}) {
    final cleaned = _stripBomAndWhitespace(raw);
    if (cleaned.isEmpty) {
      throw const FormatException('输入为空');
    }
    final Object? decoded = jsonDecode(cleaned);
    if (decoded == null) {
      throw const FormatException('输入为 null');
    }
    return JsonEncoder.withIndent(' ' * indentSpaces).convert(decoded);
  }

  /// 压缩 JSON 为单行（去除所有多余空白）。
  static String compress(String raw) {
    final cleaned = _stripBomAndWhitespace(raw);
    if (cleaned.isEmpty) return '';
    final Object? decoded = jsonDecode(cleaned);
    return jsonEncode(decoded);
  }

  /// 校验是否为合法 JSON，返回错误信息（合法时返回 null）。
  static String? validate(String raw) {
    try {
      format(raw);
      return null;
    } on FormatException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  static String _stripBomAndWhitespace(String raw) {
    var text = raw.trim();
    // 去除 UTF-8 BOM
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }
    return text.trim();
  }
}

/// 文件底部导出工具单例（按规范沿用单例风格）
final jsonUtil = JsonUtil._();
