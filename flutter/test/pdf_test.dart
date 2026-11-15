import 'package:buildpro_frontend/shared/pdf/pdf_renderer.dart';
import 'package:buildpro_frontend/shared/pdf/pdf_report.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetServices);

  test('renders a report with peso amounts to a PDF', () async {
    final bytes = await PdfRenderer.render(
      PdfReport(
        title: 'Expense report',
        fileName: 'expense-report',
        info: const [('Contract amount', '₱1,250,000.00')],
        tables: [
          PdfTable(
            title: 'Actual cost',
            headers: const ['Cost', 'Amount'],
            rows: [
              for (var i = 0; i < 120; i++) ['Line $i', '₱$i.00'],
            ],
            numeric: const {1},
            totals: const ['Total', '₱7,140.00'],
          ),
        ],
        signatures: const ['Prepared by', 'Noted by'],
      ),
      company: 'Queen Builders',
      printedAt: DateTime(2026, 11, 4),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(10000));
  });

  testWidgets('order slip, daily report and payroll offer Export PDF', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    for (final path in [
      '/purchase-orders/5',
      '/daily-reports/1',
      '/payroll/2',
    ]) {
      await goTo(tester, path);
      expect(find.text('Export PDF'), findsOneWidget, reason: path);
    }
  });
}
