import 'package:flutter_test/flutter_test.dart';
import 'package:json_layer/model/DocumentItem.dart';
import 'package:json_layer/stores/TabStore.dart';
import 'package:path/path.dart' as p;

void main() {
  test('文件夹重命名时更新子标签路径', () {
    final store = TabStore();
    final oldFolder = p.join('workspace', 'old-folder');
    final oldPath = p.join(oldFolder, 'entry.json');
    final newFolder = p.join('workspace', 'new-folder');
    final tab = store.openDocument(DocumentItem(
      id: oldPath,
      name: 'entry.json',
      path: oldPath,
      itemType: DocumentItemType.document,
      documentType: DocumentType.json,
    ));

    store.updateTabPath(oldFolder, newFolder, 'new-folder');

    expect(store.activeTab?.path, p.join(newFolder, 'entry.json'));
    expect(store.activeTab?.title, 'entry.json');
    expect(tab.path, oldPath);
  });
}
