import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/di/service_locator.dart';
import '../../data/repositories/company_repository.dart';
import '../pdf/pdf_renderer.dart';
import '../pdf/pdf_report.dart';

/// "Export PDF": renders [build]'s report and opens the system print
/// dialog, where it can be saved as a PDF, printed or shared.
class AppPdfButton extends StatefulWidget {
  const AppPdfButton({
    super.key,
    required this.build,
    this.label = 'Export PDF',
  });

  final PdfReport Function() build;
  final String label;

  @override
  State<AppPdfButton> createState() => _AppPdfButtonState();
}

class _AppPdfButtonState extends State<AppPdfButton> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final report = widget.build();
      final company = (await getIt<CompanyRepository>().getCompany()).name;
      final bytes = await PdfRenderer.render(report, company: company);
      await Printing.layoutPdf(
        name: '${report.fileName}.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not export the PDF. $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _export,
      icon: _busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.picture_as_pdf_outlined),
      label: Text(widget.label),
    );
  }
}
