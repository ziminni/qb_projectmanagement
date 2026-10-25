import '../models/app_role.dart';
import '../models/category.dart';
import '../models/project.dart';
import '../models/project_assignment.dart';
import '../models/todo.dart';
import '../models/user.dart';
import '../models/user_role.dart';

/// Seed data for the mock repositories. Project 1 reproduces the sample in
/// the design document: ₱2,000,000 contract, 37% budget-weighted progress.
abstract final class MockData {
  static const companyId = 1;

  /// Every mock account signs in with this password.
  static const demoPassword = 'password123';

  static const users = [
    User(
      id: 1,
      companyId: companyId,
      fullName: 'Maria Santos',
      email: 'maria@example.ph',
      phone: '0917 555 0101',
    ),
    User(
      id: 2,
      companyId: companyId,
      fullName: 'Ramon Dela Cruz',
      email: 'ramon@example.ph',
      phone: '0917 555 0102',
    ),
    User(
      id: 3,
      companyId: companyId,
      fullName: 'Jose Reyes',
      email: 'jose@example.ph',
      phone: '0917 555 0103',
    ),
    User(
      id: 4,
      companyId: companyId,
      fullName: 'Ana Bautista',
      email: 'ana@example.ph',
      phone: '0917 555 0104',
    ),
    User(
      id: 5,
      companyId: companyId,
      fullName: 'Carlo Mendoza',
      email: 'carlo@example.ph',
      phone: '0917 555 0105',
    ),
    User(
      id: 6,
      companyId: companyId,
      fullName: 'Liza Garcia',
      email: 'liza@example.ph',
      phone: '0917 555 0106',
    ),
    User(
      id: 7,
      companyId: companyId,
      fullName: 'Mark Villanueva',
      email: 'mark@example.ph',
      phone: '0917 555 0107',
    ),
    User(
      id: 8,
      companyId: companyId,
      fullName: 'Elena Torres',
      email: 'elena@example.ph',
      phone: '0917 555 0108',
    ),
  ];

  static const userRoles = [
    UserRole(id: 1, userId: 1, role: AppRole.admin),
    UserRole(id: 2, userId: 2, role: AppRole.owner),
    UserRole(id: 3, userId: 3, role: AppRole.pm),
    UserRole(id: 4, userId: 4, role: AppRole.siteEngineer),
    UserRole(id: 5, userId: 5, role: AppRole.purchasing),
    UserRole(id: 6, userId: 6, role: AppRole.accountant),
    UserRole(id: 7, userId: 7, role: AppRole.client),
    // A small-firm user who wears two hats.
    UserRole(id: 8, userId: 8, role: AppRole.pm),
    UserRole(id: 9, userId: 8, role: AppRole.siteEngineer),
  ];

  static final projects = [
    Project(
      id: 1,
      code: 'QB-2026-014',
      name: 'Two-storey residence, Villanueva',
      location: 'Lipa City, Batangas',
      clientId: 1,
      contractAmount: 2000000,
      downPaymentPct: 15,
      retentionPct: 10,
      startDate: DateTime(2026, 8, 3),
      targetEndDate: DateTime(2027, 1, 29),
      status: ProjectStatus.ongoing,
    ),
    Project(
      id: 2,
      code: 'QB-2026-018',
      name: 'Warehouse extension',
      location: 'Sto. Tomas, Batangas',
      clientId: 2,
      contractAmount: 3500000,
      downPaymentPct: 20,
      retentionPct: 10,
      startDate: DateTime(2026, 9, 7),
      targetEndDate: DateTime(2027, 3, 26),
      status: ProjectStatus.ongoing,
    ),
    Project(
      id: 3,
      code: 'QB-2026-021',
      name: 'Clinic renovation',
      location: 'Tanauan City, Batangas',
      clientId: 3,
      contractAmount: 1250000,
      downPaymentPct: 15,
      retentionPct: 10,
      startDate: DateTime(2026, 11, 9),
      targetEndDate: DateTime(2027, 2, 26),
      status: ProjectStatus.awarded,
    ),
    // Waiting for the owner's bid approval.
    Project(
      id: 4,
      code: 'QB-2026-025',
      name: 'Townhouse row, Malvar',
      location: 'Malvar, Batangas',
      clientId: 2,
      contractAmount: 6800000,
      downPaymentPct: 15,
      retentionPct: 10,
      startDate: DateTime(2027, 1, 11),
      targetEndDate: DateTime(2027, 9, 30),
      status: ProjectStatus.draft,
      createdAt: DateTime(2026, 10, 20, 9),
    ),
  ];

  static const assignments = [
    ProjectAssignment(
      id: 1,
      projectId: 1,
      userId: 3,
      roleOnProject: AppRole.pm,
    ),
    ProjectAssignment(
      id: 2,
      projectId: 2,
      userId: 3,
      roleOnProject: AppRole.pm,
    ),
    ProjectAssignment(
      id: 3,
      projectId: 1,
      userId: 4,
      roleOnProject: AppRole.siteEngineer,
    ),
    ProjectAssignment(
      id: 4,
      projectId: 1,
      userId: 7,
      roleOnProject: AppRole.client,
    ),
    ProjectAssignment(
      id: 5,
      projectId: 3,
      userId: 8,
      roleOnProject: AppRole.pm,
    ),
    ProjectAssignment(
      id: 6,
      projectId: 3,
      userId: 8,
      roleOnProject: AppRole.siteEngineer,
    ),
    ProjectAssignment(
      id: 8,
      projectId: 4,
      userId: 3,
      roleOnProject: AppRole.pm,
    ),
    ProjectAssignment(
      id: 7,
      projectId: 2,
      userId: 8,
      roleOnProject: AppRole.siteEngineer,
    ),
  ];

  static const categories = [
    Category(
      id: 1,
      projectId: 1,
      name: 'Foundation',
      budget: 500000,
      sortOrder: 1,
    ),
    Category(
      id: 2,
      projectId: 1,
      name: 'Pillars',
      budget: 400000,
      sortOrder: 2,
    ),
    Category(
      id: 3,
      projectId: 1,
      name: 'Roofing',
      budget: 600000,
      sortOrder: 3,
    ),
    Category(id: 4, projectId: 1, name: 'Tiling', budget: 500000, sortOrder: 4),
    Category(
      id: 5,
      projectId: 2,
      name: 'Site preparation',
      budget: 400000,
      sortOrder: 1,
    ),
    Category(
      id: 6,
      projectId: 2,
      name: 'Steel frame',
      budget: 1800000,
      sortOrder: 2,
    ),
    // No budget yet, so project 2 falls back to equal weights.
    Category(id: 7, projectId: 2, name: 'Roofing', sortOrder: 3),
    Category(
      id: 8,
      projectId: 2,
      name: 'Electrical',
      budget: 300000,
      sortOrder: 4,
    ),
  ];

  static final todos = [
    // Project 1 · Foundation: 4 of 4 verified.
    _verified(1, 1, 'Excavation', DateTime(2026, 8, 3), DateTime(2026, 8, 8)),
    _verified(
      2,
      1,
      'Rebar installation',
      DateTime(2026, 8, 10),
      DateTime(2026, 8, 19),
    ),
    _verified(3, 1, 'Formworks', DateTime(2026, 8, 17), DateTime(2026, 8, 26)),
    _verified(
      4,
      1,
      'Concrete pouring',
      DateTime(2026, 8, 27),
      DateTime(2026, 9, 2),
    ),
    // Pillars: 3 of 5 verified, 1 awaiting verification.
    _verified(
      5,
      2,
      'Ground-floor column rebar',
      DateTime(2026, 9, 3),
      DateTime(2026, 9, 12),
    ),
    _verified(
      6,
      2,
      'Ground-floor column formworks',
      DateTime(2026, 9, 10),
      DateTime(2026, 9, 19),
    ),
    _verified(
      7,
      2,
      'Ground-floor column pouring',
      DateTime(2026, 9, 21),
      DateTime(2026, 9, 26),
    ),
    _done(
      8,
      2,
      'Second-floor column rebar',
      DateTime(2026, 9, 28),
      DateTime(2026, 10, 14),
    ),
    _open(
      9,
      2,
      'Second-floor column pouring',
      DateTime(2026, 10, 19),
      DateTime(2026, 10, 31),
    ),
    // Roofing: 0 of 6.
    _open(10, 3, 'Roof beams', DateTime(2026, 11, 2), DateTime(2026, 11, 14)),
    _open(
      11,
      3,
      'Truss fabrication',
      DateTime(2026, 11, 9),
      DateTime(2026, 11, 21),
    ),
    _open(
      12,
      3,
      'Truss installation',
      DateTime(2026, 11, 23),
      DateTime(2026, 12, 5),
    ),
    _open(13, 3, 'Purlins', DateTime(2026, 12, 7), DateTime(2026, 12, 12)),
    _open(14, 3, 'Roof sheets', DateTime(2026, 12, 14), DateTime(2026, 12, 23)),
    _open(
      15,
      3,
      'Flashing and gutters',
      DateTime(2027, 1, 4),
      DateTime(2027, 1, 9),
    ),
    // Tiling: 0 of 3.
    _open(
      16,
      4,
      'Floor screeding',
      DateTime(2027, 1, 4),
      DateTime(2027, 1, 12),
    ),
    _open(17, 4, 'Floor tiling', DateTime(2027, 1, 11), DateTime(2027, 1, 22)),
    _open(18, 4, 'Wall tiling', DateTime(2027, 1, 18), DateTime(2027, 1, 28)),
    // Project 2.
    _verified(
      19,
      5,
      'Clearing and grubbing',
      DateTime(2026, 9, 7),
      DateTime(2026, 9, 11),
    ),
    _verified(
      20,
      5,
      'Layout and batter boards',
      DateTime(2026, 9, 14),
      DateTime(2026, 9, 16),
    ),
    _verified(21, 6, 'Footings', DateTime(2026, 9, 17), DateTime(2026, 10, 2)),
    _done(
      22,
      6,
      'Column erection',
      DateTime(2026, 10, 5),
      DateTime(2026, 10, 23),
    ),
    _open(
      23,
      6,
      'Beam erection',
      DateTime(2026, 10, 26),
      DateTime(2026, 11, 20),
    ),
    _open(24, 7, 'Purlins', DateTime(2026, 11, 23), DateTime(2026, 12, 4)),
    _open(25, 7, 'Roof sheets', DateTime(2026, 12, 7), DateTime(2026, 12, 23)),
    _open(26, 8, 'Rough-in', DateTime(2027, 1, 4), DateTime(2027, 2, 5)),
    _open(27, 8, 'Fixtures', DateTime(2027, 2, 8), DateTime(2027, 3, 12)),
  ];

  static Todo _open(
    int id,
    int categoryId,
    String title,
    DateTime start,
    DateTime end,
  ) => Todo(
    id: id,
    categoryId: categoryId,
    title: title,
    startDate: start,
    endDate: end,
  );

  static Todo _done(
    int id,
    int categoryId,
    String title,
    DateTime start,
    DateTime end,
  ) => _open(id, categoryId, title, start, end).copyWith(
    isDone: true,
    doneBy: () => 4,
    doneAt: () => end.add(const Duration(hours: 17)),
  );

  static Todo _verified(
    int id,
    int categoryId,
    String title,
    DateTime start,
    DateTime end,
  ) => _done(id, categoryId, title, start, end).copyWith(
    isVerified: true,
    verifiedBy: () => 3,
    verifiedAt: () => end.add(const Duration(days: 1, hours: 9)),
  );
}
