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

/// Saves [bytes] directly into the user's Downloads folder (falling back to
/// the system temp folder if Downloads cannot be resolved) and opens it with
/// the OS default program.
Future<File> saveToDownloadsAndOpen(
  String fileName,
  Uint8List bytes, {
  Future<ProcessResult> Function(String executable, List<String> args)? run,
}) async {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  Directory targetDir;
  if (home != null && home.isNotEmpty) {
    final downloads = Directory('$home${Platform.pathSeparator}Downloads');
    if (await downloads.exists()) {
      targetDir = downloads;
    } else {
      targetDir = await Directory.systemTemp.createTemp('cpms_');
    }
  } else {
    targetDir = await Directory.systemTemp.createTemp('cpms_');
  }

  final clean = safeFileName(fileName);
  final dot = clean.lastIndexOf('.');
  final stem = dot > 0 ? clean.substring(0, dot) : clean;
  final ext = dot > 0 ? clean.substring(dot) : '';

  var candidate = File('${targetDir.path}${Platform.pathSeparator}$clean');
  var n = 1;
  while (await candidate.exists()) {
    candidate = File('${targetDir.path}${Platform.pathSeparator}$stem ($n)$ext');
    n++;
  }
  await candidate.writeAsBytes(bytes, flush: true);
  final command = openFileCommand(candidate.path);
  await (run ?? Process.run)(command.executable, command.args);
  return candidate;
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

/// Opens the native OS file picker filtered to Excel `.xlsx` workbooks.
/// Returns the selected file's `(name, bytes)`, or `null` if cancelled.
Future<({String name, Uint8List bytes})?> pickSpreadsheetFile() async {
  String? selectedPath;
  if (Platform.isMacOS) {
    final res = await Process.run('osascript', [
      '-e',
      'POSIX path of (choose file with prompt "Select DPWH DUPA Excel (.xlsx)" of type {"org.openxmlformats.spreadsheetml.sheet", "xlsx"})',
    ]);
    if (res.exitCode == 0) {
      selectedPath = (res.stdout as String).trim();
    }
  } else if (Platform.isWindows) {
    final res = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      r'Add-Type -AssemblyName System.Windows.Forms; '
          r'$d = New-Object System.Windows.Forms.OpenFileDialog; '
          r'$d.Filter = "Excel Workbook (*.xlsx)|*.xlsx"; '
          r'$d.Title = "Select DPWH DUPA Excel (.xlsx)"; '
          r'if ($d.ShowDialog() -eq "OK") { Write-Output $d.FileName }',
    ]);
    if (res.exitCode == 0) {
      selectedPath = (res.stdout as String).trim();
    }
  } else if (Platform.isLinux) {
    final res = await Process.run('zenity', [
      '--file-selection',
      '--title=Select DPWH DUPA Excel (.xlsx)',
      '--file-filter=Excel Workbook (*.xlsx) | *.xlsx',
    ]);
    if (res.exitCode == 0) {
      selectedPath = (res.stdout as String).trim();
    }
  }
  if (selectedPath == null || selectedPath.isEmpty) return null;
  final bytes = await readFileBytes(selectedPath);
  return (name: safeFileName(selectedPath), bytes: bytes);
}
