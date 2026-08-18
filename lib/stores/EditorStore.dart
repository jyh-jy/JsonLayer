import 'package:flutter/foundation.dart';

import 'package:json_layer/model/DocumentItem.dart';

/// 编辑器状态管理（当前文档的编辑模式与内容）。
class EditorStore extends ChangeNotifier {
  EditorMode _currentMode = EditorMode.jsonMode;
  String _requestBody = '';
  String _responseBody = '';
  DocumentType _documentType = DocumentType.json;
  String? _currentPath;

  EditorMode get currentMode => _currentMode;
  String get requestBody => _requestBody;
  String get responseBody => _responseBody;
  DocumentType get documentType => _documentType;
  String? get currentPath => _currentPath;

  void setMode(EditorMode mode) {
    _currentMode = mode;
    notifyListeners();
  }

  void setRequestBody(String content) {
    _requestBody = content;
    notifyListeners();
  }

  void setResponseBody(String content) {
    _responseBody = content;
    notifyListeners();
  }

  void setDocumentType(DocumentType type) {
    _documentType = type;
    notifyListeners();
  }

  void loadDocument({
    required String path,
    required String requestBody,
    required String responseBody,
    required DocumentType documentType,
  }) {
    _currentPath = path;
    _requestBody = requestBody;
    _responseBody = responseBody;
    _documentType = documentType;
    _currentMode = EditorMode.jsonMode;
    notifyListeners();
  }

  void clear() {
    _currentPath = null;
    _requestBody = '';
    _responseBody = '';
    _currentMode = EditorMode.jsonMode;
    notifyListeners();
  }
}
