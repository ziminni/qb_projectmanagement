import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/category.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/equipment_borrow.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/repositories/master_data_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/widgets/app_date_field.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_reason_dialog.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_status_chip.dart';
import '../../dashboard/widgets/dashboard_stat_tile.dart';

class _DupaEquipmentRow {
  const _DupaEquipmentRow({
    required this.categoryId,
    required this.categoryName,
    required this.name,
    required this.units,
    required this.hours,
    this.ratePerHr,
    this.amount,
  });

  final int categoryId;
  final String categoryName;
  final String name;
  final double units;
  final double hours;
  final double? ratePerHr;
  final double? amount;
}

/// Project "Equipment" tab (DUPA Section B + Queen Builders borrowed equipment
/// & external rentals, with PM approval and return condition tracking).
class ProjectEquipmentPage extends StatefulWidget {
  const ProjectEquipmentPage({super.key, required this.projectId});

  final int projectId;

  @override
  State<ProjectEquipmentPage> createState() => _ProjectEquipmentPageState();
}

class _ProjectEquipmentPageState extends State<ProjectEquipmentPage> {
  final _equipmentRepo = getIt<EquipmentRepository>();
  final _masterDataRepo = getIt<MasterDataRepository>();
  final _scheduleRepo = getIt<ScheduleRepository>();
  final _session = getIt<SessionService>();

  bool _loading = true;
  bool _busy = false;
  String? _error;

  List<EquipmentBorrow> _borrows = const [];
  List<Equipment> _catalog = const [];
  List<Category> _categories = const [];
  EquipmentBorrowStatus? _statusFilter;
  EquipmentBorrowSource? _sourceFilter;

  AppRole get _role => _session.activeRole!;
  int get _userId => _session.user!.id;
  bool get _canRequestOrDeploy =>
      _role == AppRole.siteEngineer || _role == AppRole.owner;
  bool get _isPm => _role == AppRole.owner;
  bool get _showFinance => canSeeFinance();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _equipmentRepo.getBorrows(projectId: widget.projectId),
        _masterDataRepo.getEquipment(),
        _scheduleRepo.getCategories(widget.projectId),
      ]);
      if (!mounted) return;
      setState(() {
        _borrows = results[0] as List<EquipmentBorrow>;
        _catalog = results[1] as List<Equipment>;
        _categories = results[2] as List<Category>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load project equipment. $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _refreshBadges() {
    if (getIt.isRegistered<NotificationService>()) {
      getIt<NotificationService>().refresh();
    }
  }

  List<_DupaEquipmentRow> get _dupaEquipment {
    final rows = <_DupaEquipmentRow>[];
    for (final c in _categories) {
      final list = c.dupaBreakdown?['equipment'];
      if (list is! List) continue;
      for (final raw in list) {
        if (raw is! Map) continue;
        final name = (raw['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        rows.add(
          _DupaEquipmentRow(
            categoryId: c.id,
            categoryName: c.name,
            name: name,
            units: double.tryParse('${raw['units'] ?? 0}') ?? 0,
            hours: double.tryParse('${raw['hours'] ?? 0}') ?? 0,
            ratePerHr: raw['rate_per_hr'] == null
                ? null
                : double.tryParse('${raw['rate_per_hr']}'),
            amount: raw['amount'] == null
                ? null
                : double.tryParse('${raw['amount']}'),
          ),
        );
      }
    }
    return rows;
  }

  double get _dupaEquipmentBudget => _categories.fold<double>(
    0,
    (sum, c) => sum + (c.equipmentBudget ?? 0),
  );

  List<EquipmentBorrow> get _visibleBorrows => _borrows.where((b) {
    if (_statusFilter != null && b.status != _statusFilter) return false;
    if (_sourceFilter != null && b.source != _sourceFilter) return false;
    return true;
  }).toList();

  Future<void> _openBorrowDialog({
    String? prefillName,
    int? prefillCategoryId,
  }) async {
    final draft = await _BorrowEquipmentDialog.show(
      context,
      projectId: widget.projectId,
      catalog: _catalog,
      categories: _categories,
      isPm: _isPm,
      showFinance: _showFinance,
      prefillName: prefillName,
      prefillCategoryId: prefillCategoryId,
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _equipmentRepo.createBorrow(draft, userId: _userId, role: _role);
      _refreshBadges();
      await _load();
      if (!mounted) return;
      showSuccessAlert(
        context,
        _isPm
            ? '${draft.equipmentName} deployed to project.'
            : 'Equipment request sent to the project manager for approval.',
      );
    } on BusinessRuleException catch (e) {
      if (mounted) showAppMessage(context, e.message);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not save equipment. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(EquipmentBorrow row) async {
    setState(() => _busy = true);
    try {
      await _equipmentRepo.approveBorrow(row.id, userId: _userId);
      _refreshBadges();
      await _load();
      if (mounted) {
        showSuccessAlert(
          context,
          '${row.equipmentName} approved and marked on site.',
        );
      }
    } on BusinessRuleException catch (e) {
      if (mounted) showAppMessage(context, e.message);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not approve request. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(EquipmentBorrow row) async {
    final reason = await AppReasonDialog.show(
      context,
      title: 'Reject ${row.equipmentName}',
      confirmLabel: 'Reject',
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _equipmentRepo.rejectBorrow(
        row.id,
        userId: _userId,
        reason: reason,
      );
      _refreshBadges();
      await _load();
      if (mounted) showSuccessAlert(context, 'Equipment request rejected.');
    } on BusinessRuleException catch (e) {
      if (mounted) showAppMessage(context, e.message);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not reject request. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markReturned(EquipmentBorrow row) async {
    final res = await _ReturnEquipmentDialog.show(context, borrow: row);
    if (res == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _equipmentRepo.markReturned(
        row.id,
        userId: _userId,
        condition: res.condition,
        notes: res.notes,
      );
      await _load();
      if (mounted) {
        showSuccessAlert(
          context,
          '${row.equipmentName} marked returned (${res.condition.label}).',
        );
      }
    } on BusinessRuleException catch (e) {
      if (mounted) showAppMessage(context, e.message);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not mark returned. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return AppEmptyState(
        message: _error!,
        icon: Icons.error_outline,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      );
    }

    final activeBorrows = _borrows
        .where((b) => b.status == EquipmentBorrowStatus.borrowed)
        .toList();
    final ownedActive = activeBorrows
        .where((b) => b.source == EquipmentBorrowSource.owned)
        .length;
    final rentedActive = activeBorrows.length - ownedActive;
    final pendingCount = _borrows
        .where((b) => b.status == EquipmentBorrowStatus.pending)
        .length;
    final dupaRows = _dupaEquipment;
    final visible = _visibleBorrows;

    final kpiTiles = [
      DashboardStatTile(
        label: 'On site (borrowed)',
        value: '${activeBorrows.length}',
        detail: activeBorrows.isEmpty
            ? 'No active equipment on site'
            : '$ownedActive QB owned · $rentedActive rented',
        icon: Icons.handyman_outlined,
        color: AppColors.brandGold,
        onTap: () => setState(() {
          _statusFilter = _statusFilter == EquipmentBorrowStatus.borrowed
              ? null
              : EquipmentBorrowStatus.borrowed;
        }),
      ),
      DashboardStatTile(
        label: 'Pending approval',
        value: '$pendingCount',
        detail: pendingCount == 0
            ? 'All requests reviewed'
            : 'Waiting for project manager',
        icon: Icons.pending_actions_outlined,
        color: pendingCount == 0 ? AppColors.success : AppColors.warning,
        onTap: () => setState(() {
          _statusFilter = _statusFilter == EquipmentBorrowStatus.pending
              ? null
              : EquipmentBorrowStatus.pending;
        }),
      ),
      DashboardStatTile(
        label: 'DUPA planned (Sec. B)',
        value: '${dupaRows.length}',
        detail: _showFinance && _dupaEquipmentBudget > 0
            ? 'Budget: ${Formatters.pesoWhole(_dupaEquipmentBudget)}'
            : 'Planned equipment entries',
        icon: Icons.precision_manufacturing_outlined,
      ),
    ];

    return ListView(
      padding: pagePadding(context),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 820 ? 3 : 1;
            final w =
                (constraints.maxWidth - AppSpacing.md * (cols - 1)) / cols;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final tile in kpiTiles) SizedBox(width: w, child: tile),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),

        // Unified filter & action bar
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: Text('All (${_borrows.length})'),
                  selected: _statusFilter == null && _sourceFilter == null,
                  onSelected: (_) => setState(() {
                    _statusFilter = null;
                    _sourceFilter = null;
                  }),
                ),
                ChoiceChip(
                  label: Text('On site (${activeBorrows.length})'),
                  selected: _statusFilter == EquipmentBorrowStatus.borrowed,
                  onSelected: (_) => setState(() {
                    _statusFilter =
                        _statusFilter == EquipmentBorrowStatus.borrowed
                        ? null
                        : EquipmentBorrowStatus.borrowed;
                  }),
                ),
                ChoiceChip(
                  label: Text('Pending ($pendingCount)'),
                  selected: _statusFilter == EquipmentBorrowStatus.pending,
                  onSelected: (_) => setState(() {
                    _statusFilter =
                        _statusFilter == EquipmentBorrowStatus.pending
                        ? null
                        : EquipmentBorrowStatus.pending;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Returned'),
                  selected: _statusFilter == EquipmentBorrowStatus.returned,
                  onSelected: (_) => setState(() {
                    _statusFilter =
                        _statusFilter == EquipmentBorrowStatus.returned
                        ? null
                        : EquipmentBorrowStatus.returned;
                  }),
                ),
                ChoiceChip(
                  label: const Text('QB owned'),
                  selected: _sourceFilter == EquipmentBorrowSource.owned,
                  onSelected: (_) => setState(() {
                    _sourceFilter = _sourceFilter == EquipmentBorrowSource.owned
                        ? null
                        : EquipmentBorrowSource.owned;
                  }),
                ),
                ChoiceChip(
                  label: const Text('External rental'),
                  selected: _sourceFilter == EquipmentBorrowSource.rented,
                  onSelected: (_) => setState(() {
                    _sourceFilter =
                        _sourceFilter == EquipmentBorrowSource.rented
                        ? null
                        : EquipmentBorrowSource.rented;
                  }),
                ),
              ],
            ),
            if (_canRequestOrDeploy)
              FilledButton.icon(
                onPressed: _busy ? null : () => _openBorrowDialog(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  _isPm
                      ? 'Deploy / rent equipment'
                      : 'Borrow / request equipment',
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // Borrowed & rented equipment ledger
        AppSectionCard(
          title: 'Borrowed & rented equipment (${visible.length})',
          subtitle:
              'Queen Builders equipment deployed on site and external site rentals',
          icon: Icons.construction_outlined,
          padding: EdgeInsets.zero,
          child: visible.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: AppEmptyState(
                    icon: Icons.handyman_outlined,
                    message:
                        'No borrowed or rented equipment in this view yet.',
                  ),
                )
              : Column(
                  children: [
                    for (final (i, b) in visible.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      _EquipmentBorrowRow(
                        borrow: b,
                        isPm: _isPm,
                        canAct: _canRequestOrDeploy,
                        showFinance: _showFinance,
                        busy: _busy,
                        onApprove: () => _approve(b),
                        onReject: () => _reject(b),
                        onReturn: () => _markReturned(b),
                      ),
                    ],
                  ],
                ),
        ),

        // DUPA Section B reference panel
        if (dupaRows.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(
                Icons.precision_manufacturing_outlined,
                color: AppColors.brandGoldText,
              ),
              title: Text(
                'DUPA Planned Equipment — Section B (${dupaRows.length})',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _showFinance && _dupaEquipmentBudget > 0
                    ? 'Planned equipment per Item of Work · Total budget ${Formatters.peso(_dupaEquipmentBudget)}'
                    : 'Planned equipment hours from imported DUPA sheets',
              ),
              children: [
                const Divider(height: 1),
                for (final (i, d) in dupaRows.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(
                      d.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      [
                        d.categoryName,
                        if (d.hours > 0)
                          '${InputParsers.amountText(d.hours)} hr(s)',
                        if (_showFinance && d.amount != null && d.amount! > 0)
                          Formatters.peso(d.amount!),
                      ].join(' · '),
                    ),
                    trailing: _canRequestOrDeploy
                        ? OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _openBorrowDialog(
                                    prefillName: d.name,
                                    prefillCategoryId: d.categoryId,
                                  ),
                            icon: const Icon(Icons.output_rounded, size: 16),
                            label: Text(_isPm ? 'Deploy' : 'Borrow'),
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EquipmentBorrowRow extends StatelessWidget {
  const _EquipmentBorrowRow({
    required this.borrow,
    required this.isPm,
    required this.canAct,
    required this.showFinance,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onReturn,
  });

  final EquipmentBorrow borrow;
  final bool isPm;
  final bool canAct;
  final bool showFinance;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOwned = borrow.source == EquipmentBorrowSource.owned;

    final statusChip = switch (borrow.status) {
      EquipmentBorrowStatus.pending => const AppStatusChip(
        label: 'Pending PM approval',
        foreground: AppColors.warning,
        background: AppColors.warningContainer,
      ),
      EquipmentBorrowStatus.borrowed => AppStatusChip(
        label: borrow.isOverdue ? 'Overdue on site' : 'On site',
        foreground: borrow.isOverdue ? AppColors.warning : AppColors.success,
        background: borrow.isOverdue
            ? AppColors.warningContainer
            : AppColors.successContainer,
      ),
      EquipmentBorrowStatus.returned => AppStatusChip(
        label: borrow.returnCondition == null
            ? 'Returned'
            : 'Returned · ${borrow.returnCondition!.label}',
        foreground: borrow.returnCondition == EquipmentReturnCondition.damaged
            ? AppColors.error
            : borrow.returnCondition == EquipmentReturnCondition.maintenance
            ? AppColors.warning
            : cs.onSurfaceVariant,
        background: borrow.returnCondition == EquipmentReturnCondition.damaged
            ? AppColors.errorContainer
            : borrow.returnCondition == EquipmentReturnCondition.maintenance
            ? AppColors.warningContainer
            : AppColors.surfaceSunken,
      ),
      EquipmentBorrowStatus.rejected => const AppStatusChip(
        label: 'Rejected',
        foreground: AppColors.error,
        background: AppColors.errorContainer,
      ),
    };

    final meta = <String>[
      if (borrow.categoryName != null && borrow.categoryName!.isNotEmpty)
        borrow.categoryName!,
      if (!isOwned && borrow.rentalSupplier.isNotEmpty)
        'Lessor: ${borrow.rentalSupplier}',
      if (!isOwned && showFinance && borrow.rentalRate != null)
        '${Formatters.peso(borrow.rentalRate!)}/${borrow.rateUnit}',
      'Needed ${Formatters.date(borrow.neededDate)}'
          '${borrow.expectedReturnDate != null ? ' → Return ${Formatters.date(borrow.expectedReturnDate!)}' : ''}',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isOwned
                  ? AppColors.selected
                  : (isDark
                        ? cs.surfaceContainerHighest
                        : AppColors.surfaceSunken),
              borderRadius: AppRadii.mdAll,
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Icon(
              isOwned
                  ? Icons.handyman_outlined
                  : Icons.local_shipping_outlined,
              size: 19,
              color: isOwned ? AppColors.brandGoldText : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      borrow.equipmentName,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isOwned
                            ? AppColors.selected
                            : AppColors.surfaceSunken,
                        borderRadius: AppRadii.smAll,
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        isOwned ? 'QB Owned' : 'External Rental',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isOwned
                              ? AppColors.brandGoldText
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    statusChip,
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  meta.join(' · '),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                if (borrow.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Note: ${borrow.notes}',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                if (borrow.rejectionReason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Rejected: ${borrow.rejectionReason}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                ],
                if (borrow.returnNotes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Return note: ${borrow.returnNotes}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (isPm && borrow.status == EquipmentBorrowStatus.pending) ...[
                OutlinedButton(
                  onPressed: busy ? null : onReject,
                  child: const Text('Reject'),
                ),
                FilledButton.icon(
                  onPressed: busy ? null : onApprove,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Approve'),
                ),
              ] else if (canAct &&
                  borrow.status == EquipmentBorrowStatus.borrowed)
                OutlinedButton.icon(
                  onPressed: busy ? null : onReturn,
                  icon: const Icon(Icons.assignment_return_outlined, size: 16),
                  label: const Text('Return'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// BORROW / ADD EQUIPMENT DIALOG (QUEEN BUILDERS OWN POOL + EXTERNAL RENTAL)
// ============================================================================

class _BorrowEquipmentDialog extends StatefulWidget {
  const _BorrowEquipmentDialog({
    required this.projectId,
    required this.catalog,
    required this.categories,
    required this.isPm,
    required this.showFinance,
    this.prefillName,
    this.prefillCategoryId,
  });

  final int projectId;
  final List<Equipment> catalog;
  final List<Category> categories;
  final bool isPm;
  final bool showFinance;
  final String? prefillName;
  final int? prefillCategoryId;

  static Future<EquipmentBorrowDraft?> show(
    BuildContext context, {
    required int projectId,
    required List<Equipment> catalog,
    required List<Category> categories,
    required bool isPm,
    required bool showFinance,
    String? prefillName,
    int? prefillCategoryId,
  }) => showDialog<EquipmentBorrowDraft>(
    context: context,
    builder: (_) => _BorrowEquipmentDialog(
      projectId: projectId,
      catalog: catalog,
      categories: categories,
      isPm: isPm,
      showFinance: showFinance,
      prefillName: prefillName,
      prefillCategoryId: prefillCategoryId,
    ),
  );

  @override
  State<_BorrowEquipmentDialog> createState() => _BorrowEquipmentDialogState();
}

class _BorrowEquipmentDialogState extends State<_BorrowEquipmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late EquipmentBorrowSource _source;
  int? _selectedEquipmentId;
  bool _useCustomOwnedName = false;
  late final TextEditingController _nameCtrl;
  final _supplierCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _rateUnit = 'day';
  int? _categoryId;
  DateTime _neededDate = DateTime.now();
  DateTime? _expectedReturnDate = DateTime.now().add(const Duration(days: 7));

  List<Equipment> get _ownedCatalog => widget.catalog
      .where((e) => e.ownership == EquipmentOwnership.owned)
      .toList();

  List<Equipment> get _rentedCatalog => widget.catalog
      .where((e) => e.ownership == EquipmentOwnership.rented)
      .toList();

  @override
  void initState() {
    super.initState();
    _categoryId = widget.prefillCategoryId;
    final prefill = widget.prefillName?.trim() ?? '';
    _nameCtrl = TextEditingController(text: prefill);

    if (prefill.isNotEmpty) {
      final matchedOwned = _ownedCatalog
          .where((e) => e.name.toLowerCase() == prefill.toLowerCase())
          .firstOrNull;
      final matchedRented = _rentedCatalog
          .where((e) => e.name.toLowerCase() == prefill.toLowerCase())
          .firstOrNull;
      if (matchedOwned != null) {
        _source = EquipmentBorrowSource.owned;
        _selectedEquipmentId = matchedOwned.id;
      } else if (matchedRented != null ||
          prefill.toLowerCase().contains('rental')) {
        _source = EquipmentBorrowSource.rented;
        _selectedEquipmentId = matchedRented?.id;
        if (matchedRented != null && widget.showFinance) {
          _rateCtrl.text = InputParsers.amountText(matchedRented.rate);
          _rateUnit = matchedRented.rateUnit.apiValue;
        }
      } else {
        _source = EquipmentBorrowSource.owned;
        _useCustomOwnedName = true;
      }
    } else {
      _source = EquipmentBorrowSource.owned;
      if (_ownedCatalog.isEmpty) _useCustomOwnedName = true;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _supplierCtrl.dispose();
    _rateCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Equipment? picked;
    if (_selectedEquipmentId != null) {
      picked = widget.catalog
          .where((e) => e.id == _selectedEquipmentId)
          .firstOrNull;
    }
    final name =
        (_source == EquipmentBorrowSource.owned &&
            !_useCustomOwnedName &&
            picked != null)
        ? picked.name
        : _nameCtrl.text.trim();

    Navigator.of(context).pop(
      EquipmentBorrowDraft(
        projectId: widget.projectId,
        categoryId: _categoryId,
        equipmentItemId: picked?.id,
        source: _source,
        equipmentName: name,
        rentalSupplier: _source == EquipmentBorrowSource.rented
            ? _supplierCtrl.text.trim()
            : '',
        rentalRate:
            (_source == EquipmentBorrowSource.rented && widget.showFinance)
            ? InputParsers.amount(_rateCtrl.text)
            : null,
        rateUnit: _rateUnit,
        neededDate: _neededDate,
        expectedReturnDate: _expectedReturnDate,
        notes: _notesCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwned = _source == EquipmentBorrowSource.owned;
    return AlertDialog(
      title: Text(
        widget.isPm
            ? 'Deploy or rent equipment'
            : 'Borrow or request equipment',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(
          width: 520,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<EquipmentBorrowSource>(
                    segments: const [
                      ButtonSegment(
                        value: EquipmentBorrowSource.owned,
                        icon: Icon(Icons.handyman_outlined, size: 18),
                        label: Text('Queen Builders owned'),
                      ),
                      ButtonSegment(
                        value: EquipmentBorrowSource.rented,
                        icon: Icon(Icons.local_shipping_outlined, size: 18),
                        label: Text('External rental'),
                      ),
                    ],
                    selected: {_source},
                    onSelectionChanged: (s) => setState(() {
                      _source = s.first;
                      _selectedEquipmentId = null;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  if (isOwned &&
                      _ownedCatalog.isNotEmpty &&
                      !_useCustomOwnedName) ...[
                    DropdownButtonFormField<int?>(
                      key: ValueKey('owned-eq-$_selectedEquipmentId'),
                      initialValue: _selectedEquipmentId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Queen Builders equipment / tool *',
                      ),
                      items: [
                        for (final e in _ownedCatalog)
                          DropdownMenuItem<int?>(
                            value: e.id,
                            child: Text(e.name),
                          ),
                        const DropdownMenuItem<int?>(
                          value: -1,
                          child: Text('Other company tool / equipment…'),
                        ),
                      ],
                      validator: (v) =>
                          v == null ? 'Choose an equipment item.' : null,
                      onChanged: (v) {
                        if (v == -1) {
                          setState(() {
                            _useCustomOwnedName = true;
                            _selectedEquipmentId = null;
                            _nameCtrl.clear();
                          });
                        } else {
                          setState(() => _selectedEquipmentId = v);
                        }
                      },
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: isOwned
                            ? 'Company tool / equipment name *'
                            : 'Rented equipment name *',
                        hintText: isOwned
                            ? 'e.g. Submersible Pump, Jackhammer'
                            : 'e.g. Boom Truck, Backhoe, Generator',
                        suffixIcon: isOwned && _ownedCatalog.isNotEmpty
                            ? TextButton(
                                onPressed: () => setState(
                                  () => _useCustomOwnedName = false,
                                ),
                                child: const Text('Pick from list'),
                              )
                            : null,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter the equipment name.'
                          : null,
                    ),
                    if (!isOwned && _rentedCatalog.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final r in _rentedCatalog)
                            ActionChip(
                              label: Text(
                                r.name,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () => setState(() {
                                _selectedEquipmentId = r.id;
                                _nameCtrl.text = r.name;
                                if (widget.showFinance) {
                                  _rateCtrl.text = InputParsers.amountText(
                                    r.rate,
                                  );
                                  _rateUnit = r.rateUnit.apiValue;
                                }
                              }),
                            ),
                        ],
                      ),
                    ],
                  ],

                  if (!isOwned) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _supplierCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Rental supplier / lessor',
                        hintText: 'e.g. Quezon Heavy Equipment Rental',
                      ),
                    ),
                    if (widget.showFinance) ...[
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _rateCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Rental rate (₱)',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _rateUnit,
                              decoration: const InputDecoration(
                                labelText: 'Per',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'day',
                                  child: Text('Day'),
                                ),
                                DropdownMenuItem(
                                  value: 'hour',
                                  child: Text('Hour'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _rateUnit = v);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],

                  if (widget.categories.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<int?>(
                      initialValue: widget.categories.any(
                            (c) => c.id == _categoryId,
                          )
                          ? _categoryId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Item of work (optional)',
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('General / multiple items'),
                        ),
                        for (final c in widget.categories)
                          DropdownMenuItem<int?>(
                            value: c.id,
                            child: Text(
                              c.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: AppDateField(
                          label: 'Date needed',
                          value: _neededDate,
                          hasError: false,
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2032),
                              initialDate: _neededDate,
                            );
                            if (d != null) {
                              setState(() {
                                _neededDate = d;
                                if (_expectedReturnDate != null &&
                                    _expectedReturnDate!.isBefore(d)) {
                                  _expectedReturnDate = d.add(
                                    const Duration(days: 7),
                                  );
                                }
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: AppDateField(
                          label: 'Expected return',
                          value: _expectedReturnDate,
                          hasError: false,
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              firstDate: _neededDate,
                              lastDate: DateTime(2032),
                              initialDate: _expectedReturnDate ?? _neededDate,
                            );
                            if (d != null) {
                              setState(() => _expectedReturnDate = d);
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Purpose / notes (optional)',
                      hintText: 'e.g. For column rebar cutting on 2F',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: Icon(
            widget.isPm ? Icons.check_rounded : Icons.send_rounded,
            size: 18,
          ),
          label: Text(widget.isPm ? 'Deploy to site' : 'Send request'),
        ),
      ],
    );
  }
}

// ============================================================================
// RETURN EQUIPMENT CONDITION DIALOG
// ============================================================================

class _ReturnEquipmentDialog extends StatefulWidget {
  const _ReturnEquipmentDialog({required this.borrow});

  final EquipmentBorrow borrow;

  static Future<({EquipmentReturnCondition condition, String notes})?> show(
    BuildContext context, {
    required EquipmentBorrow borrow,
  }) => showDialog<({EquipmentReturnCondition condition, String notes})>(
    context: context,
    builder: (_) => _ReturnEquipmentDialog(borrow: borrow),
  );

  @override
  State<_ReturnEquipmentDialog> createState() => _ReturnEquipmentDialogState();
}

class _ReturnEquipmentDialogState extends State<_ReturnEquipmentDialog> {
  final _formKey = GlobalKey<FormState>();
  EquipmentReturnCondition _condition = EquipmentReturnCondition.good;
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsExplanation = _condition != EquipmentReturnCondition.good;
    return AlertDialog(
      title: Text('Return ${widget.borrow.equipmentName}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.borrow.source == EquipmentBorrowSource.owned
                    ? 'Record the condition of this equipment upon return to the Queen Builders yard.'
                    : 'Record the condition upon return to the rental lessor.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<EquipmentReturnCondition>(
                segments: const [
                  ButtonSegment(
                    value: EquipmentReturnCondition.good,
                    icon: Icon(Icons.check_circle_outline, size: 16),
                    label: Text('Good'),
                  ),
                  ButtonSegment(
                    value: EquipmentReturnCondition.maintenance,
                    icon: Icon(Icons.build_outlined, size: 16),
                    label: Text('Maintenance'),
                  ),
                  ButtonSegment(
                    value: EquipmentReturnCondition.damaged,
                    icon: Icon(Icons.report_problem_outlined, size: 16),
                    label: Text('Damaged'),
                  ),
                ],
                selected: {_condition},
                onSelectionChanged: (s) => setState(() => _condition = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: needsExplanation
                      ? 'Condition remarks *'
                      : 'Return notes (optional)',
                  hintText: needsExplanation
                      ? 'Describe the issue or maintenance needed'
                      : 'e.g. Cleaned and returned to yard',
                ),
                validator: (v) =>
                    needsExplanation && (v == null || v.trim().isEmpty)
                    ? 'Please describe the damage or maintenance needed.'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop((
              condition: _condition,
              notes: _notesCtrl.text.trim(),
            ));
          },
          icon: const Icon(Icons.assignment_return_outlined, size: 18),
          label: const Text('Confirm return'),
        ),
      ],
    );
  }
}
