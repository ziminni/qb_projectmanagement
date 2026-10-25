import '../../core/layout/project_tabs.dart';
import '../../core/utils/formatters.dart';
import '../../routes/routes.dart';
import '../models/app_role.dart';
import '../models/daily_report.dart';
import '../models/material_request.dart';
import '../models/payroll_period.dart';
import '../models/progress_billing.dart';
import '../models/project.dart';
import '../models/variation_order.dart';
import '../models/purchase_order.dart';
import '../repositories/billing_repository.dart';
import '../repositories/daily_report_repository.dart';
import '../repositories/labor_repository.dart';
import '../repositories/procurement_repository.dart';
import '../repositories/project_repository.dart';
import '../repositories/schedule_repository.dart';
import 'approval_inbox.dart';

/// Owner: draft projects waiting for bid approval.
class BidApprovalSource implements ApprovalSource {
  BidApprovalSource({required ProjectRepository projects})
    : _projects = projects;

  final ProjectRepository _projects;

  @override
  Future<List<ApprovalItem>> pendingFor(int userId, AppRole role) async {
    if (role != AppRole.owner) return const [];
    return [
      for (final p in await _projects.getProjects())
        if (p.status == ProjectStatus.draft)
          ApprovalItem(
            kind: ApprovalKind.bid,
            title: p.name,
            subtitle: '${p.code} · approve the bid by moving it to Bidding',
            route: AppRoutes.projectTab(p.id, ProjectTab.overview),
            amount: p.contractAmount,
            date: p.createdAt,
          ),
    ];
  }
}

/// PM: to-dos marked done on site and waiting for verification.
class TodoVerificationSource implements ApprovalSource {
  TodoVerificationSource({
    required ProjectRepository projects,
    required ScheduleRepository schedule,
  }) : _projects = projects,
       _schedule = schedule;

  final ProjectRepository _projects;
  final ScheduleRepository _schedule;

  @override
  Future<List<ApprovalItem>> pendingFor(int userId, AppRole role) async {
    if (role != AppRole.pm) return const [];
    final items = <ApprovalItem>[];
    for (final p in await _projects.getProjectsFor(userId, AppRole.pm)) {
      final categories = {
        for (final c in await _schedule.getCategories(p.id)) c.id: c.name,
      };
      for (final t in await _schedule.getTodos(p.id)) {
        if (t.isAwaitingVerification) {
          items.add(
            ApprovalItem(
              kind: ApprovalKind.todoVerification,
              title: t.title,
              subtitle: '${p.code} · ${categories[t.categoryId] ?? ''}',
              route: AppRoutes.todoVerification,
              date: t.doneAt,
            ),
          );
        }
      }
    }
    return items;
  }
}

/// PM: submitted daily reports on the PM's projects.
class DailyReportApprovalSource implements ApprovalSource {
  DailyReportApprovalSource({
    required ProjectRepository projects,
    required DailyReportRepository reports,
  }) : _projects = projects,
       _reports = reports;

  final ProjectRepository _projects;
  final DailyReportRepository _reports;

  @override
  Future<List<ApprovalItem>> pendingFor(int userId, AppRole role) async {
    if (role != AppRole.pm) return const [];
    final projects = {
      for (final p in await _projects.getProjectsFor(userId, AppRole.pm))
        p.id: p,
    };
    final reports = await _reports.getReports(
      projectIds: projects.keys.toList(),
      status: DailyReportStatus.submitted,
    );
    return [
      for (final r in reports)
        ApprovalItem(
          kind: ApprovalKind.dailyReport,
          title: 'Daily report · ${projects[r.projectId]!.code}',
          subtitle: projects[r.projectId]!.name,
          route: AppRoutes.dailyReport(r.id),
          date: r.reportDate,
        ),
    ];
  }
}

/// PM: new material requests on the PM's projects. Owner: requests over
/// their category budget.
class MaterialRequestApprovalSource implements ApprovalSource {
  MaterialRequestApprovalSource({
    required ProjectRepository projects,
    required ProcurementRepository procurement,
  }) : _projects = projects,
       _procurement = procurement;

  final ProjectRepository _projects;
  final ProcurementRepository _procurement;

  @override
  Future<List<ApprovalItem>> pendingFor(int userId, AppRole role) async {
    final MaterialRequestStatus status;
    if (role == AppRole.pm) {
      status = MaterialRequestStatus.pending;
    } else if (role == AppRole.owner) {
      status = MaterialRequestStatus.pendingOwner;
    } else {
      return const [];
    }
    final projects = {
      for (final p in await _projects.getProjectsFor(userId, role)) p.id: p,
    };
    final requests = await _procurement.getRequests(
      projectIds: projects.keys.toList(),
      statuses: [status],
    );
    return [
      for (final r in requests)
        ApprovalItem(
          kind: ApprovalKind.materialRequest,
          title: '${r.number} · ${projects[r.projectId]!.code}',
          subtitle: role == AppRole.owner
              ? 'Over the category budget'
              : 'Needed by ${Formatters.date(r.neededBy)}',
          route: AppRoutes.materialRequest(r.id),
          date: r.createdAt,
        ),
    ];
  }
}

/// Owner: purchase orders above the approval threshold.
class PurchaseOrderApprovalSource implements ApprovalSource {
  PurchaseOrderApprovalSource({
    required ProjectRepository projects,
    required ProcurementRepository procurement,
  }) : _projects = projects,
       _procurement = procurement;

  final ProjectRepository _projects;
  final ProcurementRepository _procurement;

  @override
  Future<List<ApprovalItem>> pendingFor(int userId, AppRole role) async {
    if (role != AppRole.owner) return const [];
    final projects = {for (final p in await _projects.getProjects()) p.id: p};
    final orders = await _procurement.getPurchaseOrders(
      statuses: [PurchaseOrderStatus.pendingOwner],
    );
    return [
      for (final o in orders)
        ApprovalItem(
          kind: ApprovalKind.purchaseOrder,
          title: o.poNo,
          subtitle: '${projects[o.projectId]?.code} · ${o.source.label}',
          route: AppRoutes.purchaseOrder(o.id),
          amount: o.totalAmount,
          date: o.createdAt,
        ),
    ];
  }
}

/// PM: payroll periods past cut-off whose attendance needs verifying.
class PayrollVerificationSource implements ApprovalSource {
  PayrollVerificationSource({
    required ProjectRepository projects,
    required LaborRepository labor,
    DateTime Function()? clock,
  }) : _projects = projects,
       _labor = labor,
       _clock = clock ?? DateTime.now;

  final ProjectRepository _projects;
  final LaborRepository _labor;
  final DateTime Function() _clock;

  @override
  Future<List<ApprovalItem>> pendingFor(int userId, AppRole role) async {
    if (role != AppRole.pm) return const [];
    final projects = {
      for (final p in await _projects.getProjectsFor(userId, AppRole.pm))
        p.id: p,
    };
    final today = _clock();
    return [
      for (final p in await _labor.getPeriods(
        projectIds: projects.keys.toList(),
      ))
        if (p.status == PayrollStatus.open && !today.isBefore(p.periodEnd))
          ApprovalItem(
            kind: ApprovalKind.payroll,
            title: 'Attendance · ${projects[p.projectId]!.code}',
            subtitle:
                'Cut-off ${Formatters.dateRange(p.periodStart, p.periodEnd)}',
            route: AppRoutes.payrollPeriod(p.id),
            date: p.periodEnd,
          ),
    ];
  }
}

/// Owner: progress billings to approve before they go to the client.
class BillingApprovalSource implements ApprovalSource {
  BillingApprovalSource({
    required ProjectRepository projects,
    required BillingRepository billing,
  }) : _projects = projects,
       _billing = billing;

  final ProjectRepository _projects;
  final BillingRepository _billing;

  @override
  Future<List<ApprovalItem>> pendingFor(int userId, AppRole role) async {
    if (role != AppRole.owner) return const [];
    final projects = {for (final p in await _projects.getProjects()) p.id: p};
    return [
      for (final b in await _billing.getBillings(
        statuses: [BillingStatus.pendingOwner],
      ))
        ApprovalItem(
          kind: ApprovalKind.billing,
          title: 'Billing #${b.billingNo} · ${projects[b.projectId]?.code}',
          subtitle:
              '${(b.pctAccomplished * 100).round()}% accomplished · net due',
          route: AppRoutes.billing(b.id),
          amount: b.netDue,
          date: b.createdAt,
        ),
    ];
  }
}

/// Owner: VOs to approve. PM: proposed VOs to prepare and submit.
class VariationOrderApprovalSource implements ApprovalSource {
  VariationOrderApprovalSource({
    required ProjectRepository projects,
    required BillingRepository billing,
  }) : _projects = projects,
       _billing = billing;

  final ProjectRepository _projects;
  final BillingRepository _billing;

  @override
  Future<List<ApprovalItem>> pendingFor(int userId, AppRole role) async {
    final VariationOrderStatus status;
    if (role == AppRole.owner) {
      status = VariationOrderStatus.pendingOwner;
    } else if (role == AppRole.pm) {
      status = VariationOrderStatus.proposed;
    } else {
      return const [];
    }
    final projects = {
      for (final p in await _projects.getProjectsFor(userId, role)) p.id: p,
    };
    return [
      for (final v in await _billing.getVariationOrders(
        projectIds: projects.keys.toList(),
        statuses: [status],
      ))
        ApprovalItem(
          kind: ApprovalKind.variationOrder,
          title: '${v.voNo} · ${projects[v.projectId]!.code}',
          subtitle: role == AppRole.pm
              ? 'Proposed: prepare and submit to the owner'
              : v.description,
          route: AppRoutes.variationOrder(v.id),
          amount: v.amount,
          date: v.createdAt,
        ),
    ];
  }
}
