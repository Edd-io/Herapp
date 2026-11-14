import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Opens a save dialog on desktop, or downloads the bytes in a browser.
Future<void> saveBytes(Uint8List bytes, String name) async {
  final to = await getSaveLocation(suggestedName: name);
  if (to != null) await XFile.fromData(bytes, name: name).saveTo(to.path);
}
