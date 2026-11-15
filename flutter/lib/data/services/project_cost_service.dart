import '../models/store_balance.dart';
import '../repositories/daily_report_repository.dart';
import 'business_rule_exception.dart';
import '../repositories/labor_repository.dart';
import '../repositories/master_data_repository.dart';
import '../repositories/procurement_repository.dart';

/// A project's actual cost so far.
class ProjectCosts {
  const ProjectCosts({
    required this.materialsByCategory,
    required this.storeMaterials,
    this.storeMaterialsByCategory = const {},
    required this.labor,
    required this.equipment,
  });

  /// Delivered (undamaged) material value per category, including own-store
  /// costs attributed to a category via [storeMaterialsByCategory].
  final Map<int, double> materialsByCategory;

  /// Uncategorized portion of what the company store charged the project
  /// (after attributing [storeMaterialsByCategory]).
  final double storeMaterials;

  /// Own-store material charges attributed to specific project categories.
  final Map<int, double> storeMaterialsByCategory;

  double get materials =>
      materialsByCategory.values.fold(0.0, (a, b) => a + b) + storeMaterials;

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
    final byCategory = Map<int, double>.of(
      await _procurement.deliveredValueByCategory(projectId),
    );
    final store = await _storeBalance(projectId);
    final storeByCat = store?.byCategory ?? const <int, double>{};
    var allocatedStore = 0.0;
    for (final entry in storeByCat.entries) {
      byCategory[entry.key] = (byCategory[entry.key] ?? 0) + entry.value;
      allocatedStore += entry.value;
    }
    final unallocatedStore = store == null
        ? 0.0
        : (store.total - allocatedStore).clamp(0.0, double.infinity);
    final equipment = {
      for (final e in await _masterData.getEquipment()) e.id: e,
    };
    final logs = await _reports.getApprovedEquipmentLogs(projectId);
    return ProjectCosts(
      materialsByCategory: byCategory,
      storeMaterials: unallocatedStore,
      storeMaterialsByCategory: storeByCat,
      labor: await _labor.laborCost(projectId),
      equipment: logs.fold(
        0,
        (s, l) => s + (equipment[l.equipmentId]?.costFor(l.hoursUsed) ?? 0),
      ),
    );
  }

  /// The store's charged balance. A store that cannot be answered stops the
  /// report: a total without the store's charges would look lower than it is.
  Future<StoreBalance?> _storeBalance(int projectId) async {
    try {
      return await _procurement.getStoreBalance(projectId);
    } on BusinessRuleException catch (e) {
      throw BusinessRuleException(
        "Actual cost needs the store's charges, which could not be read: "
        '${e.message}',
      );
    } on FormatException {
      throw const BusinessRuleException(
        "Actual cost needs the store's charges, which could not be read: the "
        'store sent an answer CPMS could not read.',
      );
    }
  }
}
