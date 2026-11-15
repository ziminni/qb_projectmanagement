import 'dart:io';
import 'dart:typed_data';

import 'package:buildpro_frontend/core/platform/desktop_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('desktop file opener', () {
    test('windows hands the whole path to explorer as one argument', () {
      // A real Windows profile dir: spaces, `&` and a quote in the name.
      const path =
          r'C:\Users\John Doe\AppData\Local\Temp\cpms_ab12\Q1 & Q2 "final".pdf';

      final command = openFileCommand(path, isWindows: true);

      expect(command.executable, 'explorer.exe');
      expect(command.args, [path]);
    });

    test('macos opens with open, linux with xdg-open, path untouched', () {
      const path = '/tmp/cpms_ab12/Q1 & Q2 "final".pdf';

      final mac = openFileCommand(path, isWindows: false, isMacOS: true);
      final linux = openFileCommand(path, isWindows: false, isMacOS: false);

      expect(mac.executable, 'open');
      expect(linux.executable, 'xdg-open');
      expect(mac.args, [path]);
      expect(linux.args, [path]);
    });

    test(
      'writes the file and passes its full spaced path to the runner',
      () async {
        final calls = <(String, List<String>)>[];
        final file = await saveAndOpenFile(
          'Q1 & Q2 "final".pdf',
          Uint8List.fromList([1, 2, 3]),
          run: (executable, args) async {
            calls.add((executable, args));
            return ProcessResult(0, 0, '', '');
          },
        );

        expect(file.readAsBytesSync(), [1, 2, 3]);
        expect(file.path, contains('Q1 & Q2 "final".pdf'));
        // One argument, no shell: nothing re-parses `&` or the quotes.
        expect(calls.single.$2, [file.path]);
        expect(calls.single.$1, isNot(contains('cmd')));
      },
    );
  });
}
