/// 文档类型枚举（扩展点：外部可注册新类型）。
enum DocumentType {
  json('JSON', '.json'),
  log('LOG', '.log');

  final String label;
  final String extension;

  const DocumentType(this.label, this.extension);

  static DocumentType fromExtension(String path) {
    final lower = path.toLowerCase();
    for (final type in values) {
      if (lower.endsWith(type.extension)) return type;
    }
    return json;
  }
}

/// 编辑器模式枚举。
enum EditorMode {
  jsonMode('JSON 模式'),
  objectMode('对象模式');

  final String label;
  const EditorMode(this.label);
}

/// 工作空间中的条目类型。
enum DocumentItemType {
  folder,
  document,
}

/// 工作空间条目模型（文件树节点）。
///
/// 注意：这里**不持有展开状态**。展开与否属于「用户视图偏好」而非「磁盘事实」，
/// 由 `WorkspaceStore` 统一持有并持久化。曾经在这里放过一个 `isExpanded`，
/// 与 WorkspaceTree 的局部集合形成双数据源，两者永远反相导致文件夹收不起来。
class DocumentItem {
  final String id;
  final String name;
  final String path;
  final DocumentItemType itemType;
  final DocumentType? documentType; // 仅 document 类型有值
  final List<DocumentItem> children;

  const DocumentItem({
    required this.id,
    required this.name,
    required this.path,
    required this.itemType,
    this.documentType,
    this.children = const [],
  });

  DocumentItem copyWith({
    String? name,
    List<DocumentItem>? children,
  }) {
    return DocumentItem(
      id: id,
      name: name ?? this.name,
      path: path,
      itemType: itemType,
      documentType: documentType,
      children: children ?? this.children,
    );
  }

  bool get isFolder => itemType == DocumentItemType.folder;
  bool get isDocument => itemType == DocumentItemType.document;
}

/// 打开的标签页模型。
class DocumentTab {
  final String id;
  final String itemId; // 对应 DocumentItem.id
  final String path; // 绑定文件路径（空字符串表示尚未绑定磁盘文件）
  final String title;
  final DocumentType documentType;
  final String requestBody;
  final String responseBody;
  final EditorMode editorMode;
  final bool isDirty;

  const DocumentTab({
    required this.id,
    required this.itemId,
    this.path = '',
    required this.title,
    required this.documentType,
    this.requestBody = '',
    this.responseBody = '',
    this.editorMode = EditorMode.jsonMode,
    this.isDirty = false,
  });

  /// 是否已绑定磁盘文件（可保存）。
  bool get isBound => path.isNotEmpty;

  DocumentTab copyWith({
    String? itemId,
    String? path,
    String? title,
    String? requestBody,
    String? responseBody,
    EditorMode? editorMode,
    bool? isDirty,
  }) {
    return DocumentTab(
      id: id,
      itemId: itemId ?? this.itemId,
      path: path ?? this.path,
      title: title ?? this.title,
      documentType: documentType,
      requestBody: requestBody ?? this.requestBody,
      responseBody: responseBody ?? this.responseBody,
      editorMode: editorMode ?? this.editorMode,
      isDirty: isDirty ?? this.isDirty,
    );
  }
}
