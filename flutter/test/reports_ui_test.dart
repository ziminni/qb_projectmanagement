import 'package:buildpro_frontend/core/constants/app_colors.dart';
import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/core/theme/app_theme.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/category.dart';
import 'package:buildpro_frontend/data/models/payroll_line.dart';
import 'package:buildpro_frontend/data/repositories/mock_data.dart';
import 'package:buildpro_frontend/data/repositories/user_repository.dart';
import 'package:buildpro_frontend/data/services/progress_calculator.dart';
import 'package:buildpro_frontend/data/services/project_cost_service.dart';
import 'package:buildpro_frontend/data/services/session_service.dart';
import 'package:buildpro_frontend/features/billing/viewmodels/expense_reports_viewmodel.dart';
import 'package:buildpro_frontend/features/billing/views/expense_reports_page.dart';
import 'package:buildpro_frontend/features/billing/views/project_financials_page.dart';
import 'package:buildpro_frontend/features/billing/widgets/billing_cost_table.dart';
import 'package:buildpro_frontend/features/dashboard/views/dashboard_page.dart';
import 'package:buildpro_frontend/features/dashboard/widgets/dashboard_stat_tile.dart';
import 'package:buildpro_frontend/features/labor/views/project_labor_page.dart';
import 'package:buildpro_frontend/features/labor/widgets/labor_payroll_table.dart';
import 'package:buildpro_frontend/features/procurement/views/project_materials_page.dart';
import 'package:buildpro_frontend/shared/widgets/app_budget_bar.dart';
import 'package:buildpro_frontend/shared/widgets/app_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  Future<void> signInDirect(int userId, AppRole role) async {
    final user = (await getIt<UserRepository>().getUser(userId))!;
    getIt<SessionService>().signIn(user, [role], activeRole: role);
  }

  Future<void> pumpWidgetHost(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1100, 900),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<SessionService>.value(
        value: getIt<SessionService>(),
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, w) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: w!,
          ),
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AppBudgetBar', () {
    testWidgets('shows within-budget progress and peso summary', (
      tester,
    ) async {
      await signInDirect(3, AppRole.owner);
      await pumpWidgetHost(
        tester,
        const Padding(
          padding: EdgeInsets.all(24),
          child: AppBudgetBar(
            label: 'Foundation',
            budget: 500000,
            actual: 250000,
            showAmounts: true,
          ),
        ),
      );

      expect(find.text('Foundation'), findsOneWidget);
      expect(find.text('₱250,000 of ₱500,000 (50%)'), findsOneWidget);

      final fill = tester.widgetList<Container>(find.byType(Container)).where((
        c,
      ) {
        final d = c.decoration;
        return d is BoxDecoration && d.color == AppColors.progressFill;
      });
      expect(fill, isNotEmpty);
    });

    testWidgets('highlights over-budget spend in error colour', (tester) async {
      await signInDirect(3, AppRole.owner);
      await pumpWidgetHost(
        tester,
        const Padding(
          padding: EdgeInsets.all(24),
          child: AppBudgetBar(
            label: 'Site preparation',
            budget: 100000,
            actual: 125000,
            showAmounts: true,
          ),
        ),
      );

      expect(find.text('Over by ₱25,000 · 125%'), findsOneWidget);
      final overText = tester.widget<Text>(find.text('Over by ₱25,000 · 125%'));
      expect(overText.style?.color, AppColors.error);

      final errorBars = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final d = c.decoration;
            return d is BoxDecoration && d.color == AppColors.error;
          });
      expect(errorBars, isNotEmpty);

      final track = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.color == AppColors.errorContainer);
      expect(track, isNotEmpty);
    });

    testWidgets('renders empty state when budget is null or zero', (
      tester,
    ) async {
      await signInDirect(3, AppRole.owner);
      await pumpWidgetHost(
        tester,
        const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              AppBudgetBar(
                label: 'Roofing',
                budget: null,
                actual: 12000,
                showAmounts: true,
              ),
              SizedBox(height: 16),
              AppBudgetBar(budget: 0, actual: 5000),
            ],
          ),
        ),
      );

      expect(find.text('No budget set'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('hides itself completely for non-finance roles', (
      tester,
    ) async {
      for (final (userId, role) in [
        (4, AppRole.siteEngineer),
        (1, AppRole.admin),
        (7, AppRole.client),
      ]) {
        await signInDirect(userId, role);
        await pumpWidgetHost(
          tester,
          const AppBudgetBar(
            label: 'Foundation',
            budget: 500000,
            actual: 600000,
            showAmounts: true,
          ),
        );
        expect(find.textContaining('₱'), findsNothing, reason: role.name);
        expect(find.text('Foundation'), findsNothing, reason: role.name);
      }
    });
  });

  group('Report tables and stat tiles', () {
    testWidgets('BillingCostTable renders utilization bars and totals', (
      tester,
    ) async {
      await signInDirect(6, AppRole.accountant);
      final project = MockData.projects.first;
      const cat1 = Category(
        id: 1,
        projectId: 1,
        name: 'Foundation',
        budget: 100000,
        sortOrder: 1,
      );
      const cat2 = Category(
        id: 2,
        projectId: 1,
        name: 'Roofing',
        budget: null,
        sortOrder: 2,
      );
      final report = CostReport(
        project: project,
        costs: const ProjectCosts(
          materialsByCategory: {1: 120000, 2: 20000},
          storeMaterials: 0,
          labor: 50000,
          equipment: 10000,
        ),
        categories: const [
          CategoryCost(cat1, 120000),
          CategoryCost(cat2, 20000),
        ],
        progress: ProjectProgress(
          categories: const [],
          progress: 0.4,
          plannedProgress: 0.45,
          usesBudgetWeights: false,
          contractAmount: project.contractAmount,
          totalBudget: 100000,
          asOf: DateTime(2026, 10, 25),
        ),
      );

      await pumpWidgetHost(tester, BillingCostTable(report: report));

      expect(find.text('Utilization'), findsOneWidget);
      expect(find.text('120%'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('₱200,000'), findsWidgets);
    });

    testWidgets('LaborPayrollTable shows empty state and total row', (
      tester,
    ) async {
      await signInDirect(6, AppRole.accountant);
      await pumpWidgetHost(
        tester,
        LaborPayrollTable(lines: const [], workerName: (id) => 'Worker $id'),
      );
      expect(find.byType(AppEmptyState), findsOneWidget);

      await pumpWidgetHost(
        tester,
        LaborPayrollTable(
          lines: const [
            PayrollLine(
              id: 1,
              payrollPeriodId: 1,
              workerId: 1,
              daysWorked: 5,
              overtimePay: 500,
              grossPay: 4250,
              sss: 200,
              philhealth: 100,
              pagibig: 100,
              cashAdvance: 300,
              netPay: 3550,
            ),
            PayrollLine(
              id: 2,
              payrollPeriodId: 1,
              workerId: 2,
              daysWorked: 4,
              overtimePay: 0,
              grossPay: 3000,
              sss: 150,
              philhealth: 75,
              pagibig: 60,
              cashAdvance: 0,
              netPay: 2715,
            ),
          ],
          workerName: (id) => 'Worker $id',
        ),
      );
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('₱7,250.00'), findsOneWidget);
      expect(find.text('₱6,265.00'), findsOneWidget);
    });

    testWidgets('DashboardStatTile displays optional progress bar', (
      tester,
    ) async {
      await pumpWidgetHost(
        tester,
        const SizedBox(
          width: 240,
          child: DashboardStatTile(
            label: 'Earned value',
            value: '₱740,000',
            detail: 'of ₱2,000,000 contract',
            icon: Icons.trending_up_rounded,
            progress: 0.37,
          ),
        ),
      );
      expect(find.text('Earned value'), findsOneWidget);
      expect(find.text('₱740,000'), findsOneWidget);
      expect(find.text('of ₱2,000,000 contract'), findsOneWidget);
    });
  });

  group('Finance gating across changed screens', () {
    for (final (userId, role) in [(4, AppRole.siteEngineer)]) {
      testWidgets('${role.name} sees no peso amounts on changed report pages', (
        tester,
      ) async {
        await signInDirect(userId, role);

        await pumpWidgetHost(tester, const DashboardPage());
        expect(find.textContaining('₱'), findsNothing);
        expect(find.text('Billed vs. collected'), findsNothing);
        expect(find.text('Earned value (active)'), findsNothing);

        await pumpWidgetHost(tester, const ExpenseReportsPage());
        expect(find.textContaining('₱'), findsNothing);

        await pumpWidgetHost(tester, const ProjectFinancialsPage(projectId: 1));
        expect(find.textContaining('₱'), findsNothing);

        await pumpWidgetHost(tester, const ProjectLaborPage(projectId: 1));
        expect(find.textContaining('₱'), findsNothing);

        await pumpWidgetHost(tester, const ProjectMaterialsPage(projectId: 1));
        expect(find.textContaining('₱'), findsNothing);
      });
    }

    testWidgets('admin sees project finances but cannot record money', (
      tester,
    ) async {
      await signInDirect(1, AppRole.admin);
      await pumpWidgetHost(tester, const ProjectFinancialsPage(projectId: 1));
      expect(find.textContaining('₱'), findsWidgets);
      expect(find.text('Submit payment receipt'), findsNothing);
      expect(find.text('Record payment'), findsNothing);
    });

    testWidgets('client sees no internal budgets or actual costs', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(1200, 900));
      await signInAs(tester, 'mark@example.ph');
      await goTo(tester, '/client/progress/1');
      expect(find.textContaining('₱'), findsNothing);
      expect(find.textContaining('Budget'), findsNothing);
      expect(find.textContaining('Actual cost'), findsNothing);
    });
  });

  group('Desktop responsiveness at 1100px and 1440px with 1.3x text scale', () {
    for (final width in const [1100.0, 1440.0]) {
      testWidgets('owner screens at ${width.toInt()}px and 1.3x text scale', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpApp(tester, size: Size(width, 900));
        await signInAs(tester, 'ramon@example.ph');
        expect(tester.takeException(), isNull, reason: 'dashboard at $width');

        for (final path in [
          '/projects/1/financials',
          '/expense-reports',
          '/billings',
          '/projects/1/labor',
        ]) {
          await goTo(tester, path);
          expect(tester.takeException(), isNull, reason: '$path at $width');
        }
      });

      testWidgets(
        'accountant payroll & reports at ${width.toInt()}px and 1.3x scale',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await pumpApp(tester, size: Size(width, 900));
          await signInAs(tester, 'liza@example.ph');
          expect(tester.takeException(), isNull, reason: 'payroll at $width');

          for (final path in [
            '/expense-reports',
            '/projects/1/financials',
            '/payroll/2',
            '/billings',
          ]) {
            await goTo(tester, path);
            expect(tester.takeException(), isNull, reason: '$path at $width');
          }
        },
      );

      testWidgets('admin overview at ${width.toInt()}px and 1.3x text scale', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpApp(tester, size: Size(width, 900));
        await signInAs(tester, 'maria@example.ph');
        expect(
          tester.takeException(),
          isNull,
          reason: 'admin overview at $width',
        );
      });
    }
  });
}
