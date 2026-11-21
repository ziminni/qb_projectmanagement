import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/di/service_locator.dart';
import '../../core/network/private_file_loader.dart';
import '../../core/utils/formatters.dart';
import 'pdf_report.dart';

/// Renders a [PdfReport] on A4 with the company name as letterhead, in the
/// app's Open Sans. Open Sans has no peso sign, so the bundled Roboto fills
/// in for that glyph.
abstract final class PdfRenderer {
  static Future<Uint8List> render(
    PdfReport report, {
    required String company,
    DateTime? printedAt,
  }) async {
    Future<pw.Font> font(String file) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/$file.ttf'));
    final regular = await font('OpenSans-Regular');
    final bold = await font('OpenSans-Bold');
    final pesoRegular = await font('Roboto-Regular');
    final pesoBold = await font('Roboto-Bold');
    final doc = pw.Document(
      title: report.title,
      author: company,
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        fontFallback: [pesoRegular, pesoBold],
      ),
    );
    const accent = PdfColor.fromInt(0xFFAC934F);
    const ink = PdfColor.fromInt(0xFF1A1814);
    const muted = PdfColor.fromInt(0xFF686257);
    const line = PdfColor.fromInt(0xFFDED5C0);
    const surface = PdfColor.fromInt(0xFFF8F6F0);
    const headerFill = PdfColor.fromInt(0xFFF3EFE5);
    final printed = printedAt ?? DateTime.now();

    final loadedPhotos = <({String title, List<_LoadedPhoto> items})>[];
    for (final section in report.photoSections) {
      if (section.paths.isEmpty) continue;
      final items = <_LoadedPhoto>[];
      for (final path in section.paths) {
        items.add(
          _LoadedPhoto(
            name: _fileName(path),
            image: await _loadPdfImage(path),
          ),
        );
      }
      loadedPhotos.add((title: section.title, items: items));
    }

    /// The title and table as separate page children, so a long table can
    /// continue on the next page.
    List<pw.Widget> table(PdfTable t) {
      pw.Alignment align(int i) => t.numeric.contains(i)
          ? pw.Alignment.centerRight
          : pw.Alignment.centerLeft;
      return [
        pw.SizedBox(height: 14),
        pw.Text(
          t.title,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),
        pw.SizedBox(height: 5),
        if (t.rows.isEmpty)
          pw.Text(t.empty, style: const pw.TextStyle(color: muted))
        else
          pw.TableHelper.fromTextArray(
            headers: t.headers,
            data: [...t.rows, ?t.totals],
            headerStyle: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: ink,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8.5, color: ink),
            headerDecoration: const pw.BoxDecoration(color: headerFill),
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: line, width: 0.5),
              bottom: pw.BorderSide(color: line, width: 0.5),
              top: pw.BorderSide(color: line, width: 0.5),
            ),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 4,
            ),
            cellAlignments: {
              for (var i = 0; i < t.headers.length; i++) i: align(i),
            },
            headerAlignments: {
              for (var i = 0; i < t.headers.length; i++) i: align(i),
            },
            headerCount: 1,
            cellDecoration: t.totals == null
                ? null
                : (index, data, rowNum) => rowNum == t.rows.length + 1
                      ? const pw.BoxDecoration(color: headerFill)
                      : const pw.BoxDecoration(),
          ),
      ];
    }

    pw.Widget infoCard(List<(String, String)> entries) {
      final rows = <pw.Widget>[];
      for (var i = 0; i < entries.length; i += 2) {
        final left = entries[i];
        final right = i + 1 < entries.length ? entries[i + 1] : null;
        rows.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: _infoCell(left.$1, left.$2, ink, muted)),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: right == null
                      ? pw.SizedBox()
                      : _infoCell(right.$1, right.$2, ink, muted),
                ),
              ],
            ),
          ),
        );
      }
      return pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: surface,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: line, width: 0.8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: rows,
        ),
      );
    }

    List<pw.Widget> photoSectionWidgets(
      ({String title, List<_LoadedPhoto> items}) section,
    ) {
      final widgets = <pw.Widget>[
        pw.SizedBox(height: 16),
        pw.Text(
          section.title,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),
        pw.SizedBox(height: 6),
      ];
      for (var i = 0; i < section.items.length; i += 2) {
        final left = section.items[i];
        final right = i + 1 < section.items.length
            ? section.items[i + 1]
            : null;
        widgets.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _photoBox(left, ink: ink, muted: muted, line: line, surface: surface),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: right == null
                      ? pw.SizedBox()
                      : _photoBox(right, ink: ink, muted: muted, line: line, surface: surface),
                ),
              ],
            ),
          ),
        );
      }
      return widgets;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(height: 2.5, color: accent),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  company,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: ink,
                  ),
                ),
                pw.Text(
                  'BuildPro CPMS',
                  style: const pw.TextStyle(color: muted, fontSize: 8.5),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: line, height: 1, thickness: 0.6),
            pw.SizedBox(height: 12),
          ],
        ),
        footer: (context) => pw.Column(
          children: [
            pw.Divider(color: line, height: 1, thickness: 0.5),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Printed ${Formatters.dateTime(printed)}',
                  style: const pw.TextStyle(color: muted, fontSize: 8),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(color: muted, fontSize: 8),
                ),
              ],
            ),
          ],
        ),
        build: (context) => [
          pw.Text(
            report.title,
            style: pw.TextStyle(
              fontSize: 19,
              fontWeight: pw.FontWeight.bold,
              color: ink,
            ),
          ),
          if (report.subtitle != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              report.subtitle!,
              style: const pw.TextStyle(color: muted, fontSize: 10),
            ),
          ],
          if (report.info.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            infoCard(report.info),
          ],
          for (final (title, body) in report.notes) ...[
            pw.SizedBox(height: 14),
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: ink,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: line, width: 0.7),
              ),
              child: pw.Text(
                body,
                style: const pw.TextStyle(
                  fontSize: 9.5,
                  color: ink,
                  lineSpacing: 3,
                ),
              ),
            ),
          ],
          for (final t in report.tables) ...table(t),
          for (final section in loadedPhotos) ...photoSectionWidgets(section),
          if (report.signatures.isNotEmpty) ...[
            pw.SizedBox(height: 36),
            pw.Row(
              children: [
                for (final (i, s) in report.signatures.indexed)
                  pw.Expanded(
                    child: pw.Padding(
                      padding: pw.EdgeInsets.only(
                        right: i == report.signatures.length - 1 ? 0 : 28,
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.SizedBox(height: 18),
                          pw.Container(height: 0.7, color: ink),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            s,
                            style: const pw.TextStyle(
                              fontSize: 8.5,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _infoCell(
    String label,
    String value,
    PdfColor ink,
    PdfColor muted,
  ) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
          color: muted,
          letterSpacing: 0.4,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: ink,
        ),
      ),
    ],
  );

  static pw.Widget _photoBox(
    _LoadedPhoto photo, {
    required PdfColor ink,
    required PdfColor muted,
    required PdfColor line,
    required PdfColor surface,
  }) => pw.Container(
    decoration: pw.BoxDecoration(
      borderRadius: pw.BorderRadius.circular(6),
      border: pw.Border.all(color: line, width: 0.7),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          height: 165,
          color: surface,
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.all(4),
          child: photo.image != null
              ? pw.Image(photo.image!, fit: pw.BoxFit.contain)
              : pw.Text(
                  'Photo unavailable',
                  style: pw.TextStyle(fontSize: 8.5, color: muted),
                ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: line, width: 0.5)),
          ),
          child: pw.Text(
            photo.name,
            style: pw.TextStyle(fontSize: 8, color: ink),
            maxLines: 1,
          ),
        ),
      ],
    ),
  );

  static Future<pw.MemoryImage?> _loadPdfImage(String path) async {
    if (path.isEmpty || path.startsWith('mock://')) return null;
    try {
      Uint8List? raw;
      if (path.startsWith('http://') ||
          path.startsWith('https://') ||
          path.startsWith('/api/')) {
        if (getIt.isRegistered<PrivateFileLoader>()) {
          raw = await getIt<PrivateFileLoader>().bytes(path);
        }
      } else if (!kIsWeb) {
        final file = File(path);
        if (await file.exists()) {
          raw = await file.readAsBytes();
        }
      }
      if (raw == null || raw.isEmpty) return null;

      final lower = _fileName(path).toLowerCase();
      if (lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png')) {
        return pw.MemoryImage(raw);
      }
      // Convert WebP / BMP / TIFF / other formats to JPEG so pdf embeds them cleanly.
      final decoded = img.decodeImage(raw);
      if (decoded == null) return null;
      return pw.MemoryImage(
        Uint8List.fromList(img.encodeJpg(decoded, quality: 85)),
      );
    } catch (_) {
      return null;
    }
  }

  static String _fileName(String path) {
    var normalized = path.replaceAll('\\', '/');
    while (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final idx = normalized.lastIndexOf('/');
    return idx >= 0 && idx < normalized.length - 1
        ? normalized.substring(idx + 1)
        : normalized;
  }
}

class _LoadedPhoto {
  const _LoadedPhoto({required this.name, required this.image});

  final String name;
  final pw.MemoryImage? image;
}
