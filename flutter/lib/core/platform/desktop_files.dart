import 'dart:io';
import 'dart:typed_data';

import '../../data/services/business_rule_exception.dart';

/// The OS command that hands [path] to its default program.
///
/// Windows gets `explorer.exe` with the path as its one argument: no `cmd.exe`
/// re-parses it, so spaces, `&` and quotes stay literal. `start` through a
/// shell reads a quoted first token as the window title, which is why a temp
/// path under `C:\Users\John Doe\...` opened a console instead of the file.
({String executable, List<String> args}) openFileCommand(
  String path, {
  bool? isWindows,
  bool? isMacOS,
}) {
  if (isWindows ?? Platform.isWindows) {
    return (executable: 'explorer.exe', args: [path]);
  }
  return (
    executable: (isMacOS ?? Platform.isMacOS) ? 'open' : 'xdg-open',
    args: [path],
  );
}

/// Writes a downloaded private file to a temp folder and hands it to the
/// desktop's own file handler (`xdg-open` / `open` / `start`). The app never
/// needs to render these formats itself; the OS chooses the program.
Future<File> saveAndOpenFile(
  String fileName,
  Uint8List bytes, {
  Future<ProcessResult> Function(String executable, List<String> args)? run,
}) async {
  final dir = await Directory.systemTemp.createTemp('cpms_');
  final file = File(
    '${dir.path}${Platform.pathSeparator}${safeFileName(fileName)}',
  );
  await file.writeAsBytes(bytes, flush: true);
  final command = openFileCommand(file.path);
  await (run ?? Process.run)(command.executable, command.args);
  return file;
}

/// The last path segment, so a stored name can never climb out of the temp
/// folder (`../../x.pdf`).
String safeFileName(String fileName) =>
    fileName.split(RegExp(r'[\\/]')).last.trim();

/// Reads a file the person named on this machine. The server still checks the
/// type and the size; this only turns a path into bytes.
Future<Uint8List> readFileBytes(String path) async {
  try {
    return await File(path.trim()).readAsBytes();
  } on FileSystemException {
    throw const BusinessRuleException(
      'Cannot read that file. Check the path and try again.',
    );
  }
}
