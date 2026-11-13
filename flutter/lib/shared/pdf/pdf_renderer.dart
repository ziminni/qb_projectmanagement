import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
    const muted = PdfColor.fromInt(0xFF5B6478);
    const line = PdfColor.fromInt(0xFFCBD3E1);
    const headerFill = PdfColor.fromInt(0xFFF1F4F9);
    final printed = printedAt ?? DateTime.now();

    /// The title and table as separate page children, so a long table can
    /// continue on the next page.
    List<pw.Widget> table(PdfTable t) {
      pw.Alignment align(int i) => t.numeric.contains(i)
          ? pw.Alignment.centerRight
          : pw.Alignment.centerLeft;
      return [
        pw.SizedBox(height: 12),
        pw.Text(
          t.title,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        if (t.rows.isEmpty)
          pw.Text(t.empty, style: const pw.TextStyle(color: muted))
        else
          pw.TableHelper.fromTextArray(
            headers: t.headers,
            data: [...t.rows, ?t.totals],
            headerStyle: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            headerDecoration: const pw.BoxDecoration(color: headerFill),
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: line, width: 0.5),
              bottom: pw.BorderSide(color: line, width: 0.5),
              top: pw.BorderSide(color: line, width: 0.5),
            ),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 3,
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

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          margin: const pw.EdgeInsets.only(bottom: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: line)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                company,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'BuildPro',
                style: const pw.TextStyle(color: muted, fontSize: 9),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Row(
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
        build: (context) => [
          pw.Text(
            report.title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          if (report.subtitle != null)
            pw.Text(report.subtitle!, style: const pw.TextStyle(color: muted)),
          if (report.info.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Wrap(
              spacing: 24,
              runSpacing: 4,
              children: [
                for (final (label, value) in report.info)
                  pw.SizedBox(
                    width: 240,
                    child: pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: '$label: ',
                            style: const pw.TextStyle(
                              color: muted,
                              fontSize: 9,
                            ),
                          ),
                          pw.TextSpan(
                            text: value,
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          for (final t in report.tables) ...table(t),
          for (final (title, body) in report.notes) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(body, style: const pw.TextStyle(fontSize: 9)),
          ],
          if (report.signatures.isNotEmpty) ...[
            pw.SizedBox(height: 40),
            pw.Row(
              children: [
                for (final s in report.signatures)
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 24),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(height: 0.5, color: PdfColors.black),
                          pw.SizedBox(height: 2),
                          pw.Text(s, style: const pw.TextStyle(fontSize: 8)),
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
}
