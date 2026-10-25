import '../../../core/di/service_locator.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/category.dart';
import '../../../data/models/material_item.dart';
import '../../../data/models/project.dart';
import '../../../data/models/supplier.dart';
import '../../../data/repositories/master_data_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/user_repository.dart';

/// Names and reference data the procurement screens show next to ids.
class ProcurementLookups {
  ProcurementLookups({
    required ProjectRepository projects,
    required ScheduleRepository schedule,
    required MasterDataRepository masterData,
    required UserRepository users,
  }) : _projectRepo = projects,
       _schedule = schedule,
       _masterData = masterData,
       _users = users;

  /// Built from the registered repositories.
  factory ProcurementLookups.fromServices() => ProcurementLookups(
    projects: getIt(),
    schedule: getIt(),
    masterData: getIt(),
    users: getIt(),
  );

  final ProjectRepository _projectRepo;
  final ScheduleRepository _schedule;
  final MasterDataRepository _masterData;
  final UserRepository _users;

  Map<int, Project> projects = const {};
  Map<int, Category> categories = const {};
  Map<int, MaterialItem> materials = const {};
  Map<int, Supplier> suppliers = const {};
  Map<int, String> userNames = const {};

  /// Loads reference data for the projects [userId] can see as [role].
  Future<void> load(int userId, AppRole role) async {
    final visible = await _projectRepo.getProjectsFor(userId, role);
    projects = {for (final p in visible) p.id: p};
    categories = {
      for (final p in visible)
        for (final c in await _schedule.getCategories(p.id)) c.id: c,
    };
    materials = {for (final m in await _masterData.getMaterials()) m.id: m};
    suppliers = {for (final s in await _masterData.getSuppliers()) s.id: s};
    userNames = {for (final u in await _users.getUsers()) u.id: u.fullName};
  }

  String projectCode(int id) => projects[id]?.code ?? 'Project #$id';
  String categoryName(int id) => categories[id]?.name ?? 'Category #$id';
  String materialName(int id) => materials[id]?.name ?? 'Material #$id';
  String unit(int id) => materials[id]?.unit ?? '';
  String supplierName(int id) => suppliers[id]?.name ?? 'Supplier #$id';
  String userName(int? id) => id == null ? '—' : userNames[id] ?? 'User #$id';
}
