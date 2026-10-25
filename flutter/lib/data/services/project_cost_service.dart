import '../repositories/daily_report_repository.dart';
import '../repositories/labor_repository.dart';
import '../repositories/master_data_repository.dart';
import '../repositories/procurement_repository.dart';

/// A project's actual cost so far.
class ProjectCosts {
  const ProjectCosts({
    required this.materials,
    required this.materialsByCategory,
    required this.labor,
    required this.equipment,
  });

  /// Delivered (undamaged) material value.
  final double materials;
  final Map<int, double> materialsByCategory;

  /// Gross pay of processed payroll.
  final double labor;

  /// Equipment hours on approved daily reports × rate.
  final double equipment;

  double get total => materials + labor + equipment;
}

/// Gathers actual cost from procurement, payroll and equipment logs so the
/// Financials tab and expense reports agree.
class ProjectCostService {
  ProjectCostService({
    required ProcurementRepository procurement,
    required LaborRepository labor,
    required DailyReportRepository reports,
    required MasterDataRepository masterData,
  }) : _procurement = procurement,
       _labor = labor,
       _reports = reports,
       _masterData = masterData;

  final ProcurementRepository _procurement;
  final LaborRepository _labor;
  final DailyReportRepository _reports;
  final MasterDataRepository _masterData;

  Future<ProjectCosts> costsFor(int projectId) async {
    final byCategory = await _procurement.deliveredValueByCategory(projectId);
    final equipment = {
      for (final e in await _masterData.getEquipment()) e.id: e,
    };
    final logs = await _reports.getApprovedEquipmentLogs(projectId);
    return ProjectCosts(
      materials: byCategory.values.fold(0, (a, b) => a + b),
      materialsByCategory: byCategory,
      labor: await _labor.laborCost(projectId),
      equipment: logs.fold(
        0,
        (s, l) => s + (equipment[l.equipmentId]?.costFor(l.hoursUsed) ?? 0),
      ),
    );
  }
}
