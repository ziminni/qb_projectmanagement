/// A printable report described as plain data, so view models can build
/// one without depending on the PDF library. [AppPdfButton] renders it.
class PdfReport {
  const PdfReport({
    required this.title,
    required this.fileName,
    this.subtitle,
    this.info = const [],
    this.tables = const [],
    this.notes = const [],
    this.photoSections = const [],
    this.signatures = const [],
  });

  final String title;

  /// Suggested file name, without extension.
  final String fileName;
  final String? subtitle;

  /// Label–value pairs shown under the title.
  final List<(String, String)> info;
  final List<PdfTable> tables;

  /// Titled paragraphs, e.g. remarks.
  final List<(String, String)> notes;

  /// Optional titled groups of attached photos to embed in the PDF.
  final List<PdfPhotoSection> photoSections;

  /// Signature lines at the bottom, e.g. "Prepared by".
  final List<String> signatures;
}

class PdfPhotoSection {
  const PdfPhotoSection({required this.title, required this.paths});

  final String title;
  final List<String> paths;
}

class PdfTable {
  const PdfTable({
    required this.title,
    required this.headers,
    required this.rows,
    this.numeric = const {},
    this.totals,
    this.empty = 'None.',
  });

  final String title;
  final List<String> headers;
  final List<List<String>> rows;

  /// Column indexes aligned right.
  final Set<int> numeric;

  /// An optional bold last row.
  final List<String>? totals;
  final String empty;
}
