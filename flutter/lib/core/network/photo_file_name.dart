import 'dart:typed_data';

/// The file name the server's photo validator expects: it checks the
/// extension *and* the magic bytes, so the name follows the content (a WebP
/// named `.jpg` is refused as "does not look like a jpg file").
String photoFileName(Uint8List bytes) {
  if (bytes.length > 3 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'photo.png';
  }
  // WebP is a RIFF container with `WEBP` at byte 8, exactly like the server.
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'photo.webp';
  }
  return 'photo.jpg';
}
