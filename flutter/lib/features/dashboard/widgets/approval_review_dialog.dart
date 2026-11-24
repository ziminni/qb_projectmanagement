import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/category.dart';
import '../../../data/models/equipment_borrow.dart';
import '../../../data/models/project.dart';
import '../../../data/models/project_worker_request.dart';
import '../../../data/models/todo.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/models/worker.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/repositories/labor_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/approval_inbox.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_history_list.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_pdf_button.dart';
import '../../../shared/widgets/app_photo_tile.dart';
import '../../../shared/widgets/app_reason_dialog.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_status_chip.dart';
import '../../../shared/widgets/app_vo_status_chip.dart';
import '../../../shared/widgets/app_workflow_steps.dart';
import '../../billing/viewmodels/variation_order_detail_viewmodel.dart';
import '../../billing/widgets/vo_photo_attachments.dart';
import '../../billing/widgets/vo_revised_schedule_section.dart';
import '../../daily_reports/viewmodels/daily_report_detail_viewmodel.dart';
import '../../daily_reports/widgets/daily_reports_return_dialog.dart';
import '../../daily_reports/widgets/daily_reports_status_chip.dart';
import '../../labor/viewmodels/payroll_period_detail_viewmodel.dart';
import '../../labor/widgets/labor_payroll_table.dart';
import '../../labor/widgets/labor_period_status_chip.dart';
import '../../procurement/viewmodels/material_request_detail_viewmodel.dart';
import '../../procurement/viewmodels/procurement_lookups.dart';
import '../../procurement/views/other_store_purchase_form.dart';
import '../../procurement/views/own_store_order_form.dart';
import '../../procurement/widgets/procurement_po_tile.dart';
import '../../procurement/widgets/procurement_request_status_chip.dart';
import '../../procurement/widgets/procurement_request_summary.dart';
import 'dashboard_waiting_row.dart';

/// Dedicated in-place review & decision modal for any [ApprovalItem] in the PM
/// Approvals queue. Keeps the PM inside `/approvals` instead of redirecting out
/// to project tabs or separate module routes.
class ApprovalReviewDialog extends StatefulWidget {
  const ApprovalReviewDialog({
    super.key,
    required this.item,
    this.onChanged,
  });

  final ApprovalItem item;
  final VoidCallback? onChanged;

  static Future<bool> show(
    BuildContext context, {
    required ApprovalItem item,
    VoidCallback? onChanged,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ApprovalReviewDialog(item: item, onChanged: onChanged),
    );
    return result ?? false;
  }

  @override
  State<ApprovalReviewDialog> createState() => _ApprovalReviewDialogState();
}

class _ApprovalReviewDialogState extends State<ApprovalReviewDialog> {
  bool _didChange = false;
  VoidCallback? _subBackOverride;
  String? _subTitleOverride;

  void _markChanged() {
    _didChange = true;
    if (getIt.isRegistered<NotificationService>()) {
      getIt<NotificationService>().refresh();
    }
    widget.onChanged?.call();
  }

  void _handleBack() {
    if (_subBackOverride != null) {
      _subBackOverride!();
      return;
    }
    Navigator.of(context).pop(_didChange);
  }

  void _setSubNavigation({VoidCallback? onBack, String? title}) {
    setState(() {
      _subBackOverride = onBack;
      _subTitleOverride = title;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final item = widget.item;
    final size = MediaQuery.sizeOf(context);

    final projectLabel = [
      if (item.projectCode != null && item.projectCode!.isNotEmpty)
        item.projectCode!,
      if (item.projectName != null && item.projectName!.isNotEmpty)
        item.projectName!,
    ].join(' · ');

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width >= 720 ? 32 : 14,
        vertical: size.height >= 700 ? 28 : 14,
      ),
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.lgAll,
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 840),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal top navigation bar
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? cs.surfaceContainer
                    : AppColors.tableHeader,
                border: Border(bottom: BorderSide(color: cs.outlineVariant)),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _handleBack,
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Back'),
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    width: 1,
                    height: 20,
                    color: cs.outlineVariant,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Icon(
                    DashboardWaitingRow.iconFor(item.kind),
                    size: 18,
                    color: isDark ? cs.secondary : AppColors.brandGoldText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _subTitleOverride ?? item.kind.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        if (projectLabel.isNotEmpty)
                          Text(
                            projectLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(_didChange),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            // Modal body per approval kind
            Expanded(
              child: _buildPane(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPane(ApprovalItem item) {
    final id = item.entityId;
    if (id == null) {
      return const AppEmptyState(
        message: 'Details are unavailable for this approval item.',
      );
    }
    return switch (item.kind) {
      ApprovalKind.laborerRequest => _LaborerRequestReviewPane(
        requestIds: item.effectiveIds,
        projectId: item.projectId,
        projectCode: item.projectCode,
        projectName: item.projectName,
        onChanged: _markChanged,
        onClose: () => Navigator.of(context).pop(_didChange),
      ),
      ApprovalKind.todoVerification => _TodoVerificationReviewPane(
        todoId: id,
        projectId: item.projectId,
        onChanged: _markChanged,
        onClose: () => Navigator.of(context).pop(_didChange),
      ),
      ApprovalKind.dailyReport => _DailyReportReviewPane(
        reportId: id,
        onChanged: _markChanged,
        onClose: () => Navigator.of(context).pop(_didChange),
      ),
      ApprovalKind.materialRequest => _MaterialRequestReviewPane(
        requestId: id,
        onChanged: _markChanged,
        onSubNavigation: _setSubNavigation,
        onClose: () => Navigator.of(context).pop(_didChange),
      ),
      ApprovalKind.equipmentRequest => _EquipmentRequestReviewPane(
        requestIds: item.effectiveIds,
        projectId: item.projectId,
        projectCode: item.projectCode,
        projectName: item.projectName,
        onChanged: _markChanged,
        onClose: () => Navigator.of(context).pop(_didChange),
      ),
      ApprovalKind.variationOrder => _VariationOrderReviewPane(
        voId: id,
        onChanged: _markChanged,
        onClose: () => Navigator.of(context).pop(_didChange),
      ),
      ApprovalKind.payroll => _PayrollVerificationReviewPane(
        periodId: id,
        onChanged: _markChanged,
        onClose: () => Navigator.of(context).pop(_didChange),
      ),
    };
  }
}

class _ModalFooterBar extends StatelessWidget {
  const _ModalFooterBar({
    required this.hint,
    required this.actions,
  });

  final String hint;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainer : AppColors.surfaceSunken,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              hint,
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: actions,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 1. LABORER REQUEST REVIEW PANE
// ============================================================================

class _LaborerRequestReviewPane extends StatefulWidget {
  const _LaborerRequestReviewPane({
    required this.requestIds,
    required this.projectId,
    required this.projectCode,
    required this.projectName,
    required this.onChanged,
    required this.onClose,
  });

  final List<int> requestIds;
  final int? projectId;
  final String? projectCode;
  final String? projectName;
  final VoidCallback onChanged;
  final VoidCallback onClose;

  @override
  State<_LaborerRequestReviewPane> createState() =>
      _LaborerRequestReviewPaneState();
}

class _LaborerRequestReviewPaneState extends State<_LaborerRequestReviewPane> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<ProjectWorkerRequest> _requests = const [];
  Map<int, Worker> _workersById = const {};
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load(selectAllPending: true);
  }

  List<ProjectWorkerRequest> get _pendingRequests => _requests
      .where((r) => r.status == ProjectWorkerRequestStatus.pending)
      .toList();

  Future<void> _load({bool selectAllPending = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final labor = getIt<LaborRepository>();
      final allRequests = await labor.getWorkerRequests(
        projectId: widget.projectId,
      );
      final targetSet = widget.requestIds.toSet();
      final matched = allRequests
          .where((r) => targetSet.contains(r.id))
          .toList();
      final workers = await labor.getWorkers();
      final workersById = {for (final w in workers) w.id: w};
      if (!mounted) return;
      setState(() {
        _requests = matched;
        _workersById = workersById;
        if (matched.isEmpty) {
          _error = 'Laborer request not found.';
        } else {
          final pendingIds = {
            for (final r in matched)
              if (r.status == ProjectWorkerRequestStatus.pending) r.id,
          };
          _selectedIds.removeWhere((id) => !pendingIds.contains(id));
          if (selectAllPending || _selectedIds.isEmpty) {
            _selectedIds.addAll(pendingIds);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load laborer request. $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSelectAll(bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedIds.addAll(_pendingRequests.map((r) => r.id));
      } else {
        _selectedIds.clear();
      }
    });
  }

  void _toggleOne(int id) {
    setState(() {
      if (!_selectedIds.remove(id)) {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _approveIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final singleName = ids.length == 1
        ? _requests.where((r) => r.id == ids.first).firstOrNull?.fullName
        : null;
    setState(() => _busy = true);
    try {
      final uid = getIt<SessionService>().user!.id;
      final labor = getIt<LaborRepository>();
      for (final id in ids) {
        await labor.approveWorkerRequest(id, userId: uid);
      }
      widget.onChanged();
      await _load(selectAllPending: true);
      if (!mounted) return;
      showSuccessAlert(
        context,
        singleName != null
            ? '$singleName approved and added to project.'
            : '${ids.length} laborers approved and added to project.',
      );
      if (_pendingRequests.isEmpty) {
        widget.onClose();
      }
    } on BusinessRuleException catch (e) {
      if (mounted) showAppMessage(context, e.message);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not approve request. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rejectIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final singleName = ids.length == 1
        ? _requests.where((r) => r.id == ids.first).firstOrNull?.fullName
        : null;
    final reason = await AppReasonDialog.show(
      context,
      title: singleName != null
          ? 'Reject $singleName'
          : 'Reject ${ids.length} laborer requests',
      confirmLabel: 'Reject',
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final uid = getIt<SessionService>().user!.id;
      final labor = getIt<LaborRepository>();
      for (final id in ids) {
        await labor.rejectWorkerRequest(id, userId: uid, reason: reason);
      }
      widget.onChanged();
      await _load(selectAllPending: true);
      if (!mounted) return;
      showSuccessAlert(
        context,
        ids.length == 1
            ? 'Laborer request rejected.'
            : '${ids.length} laborer requests rejected.',
      );
      if (_pendingRequests.isEmpty) {
        widget.onClose();
      }
    } on BusinessRuleException catch (e) {
      if (mounted) showAppMessage(context, e.message);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not reject request. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppEmptyState(message: _error!);

    if (_requests.length == 1) {
      return _buildSingleView(context, _requests.first);
    }
    return _buildBulkView(context);
  }

  Widget _buildSingleView(BuildContext context, ProjectWorkerRequest req) {
    final cs = Theme.of(context).colorScheme;
    final linkedWorker = req.workerId != null
        ? _workersById[req.workerId!]
        : null;
    final isPending = req.status == ProjectWorkerRequestStatus.pending;
    final isApproved = req.status == ProjectWorkerRequestStatus.approved;

    final statusChip = _workerRequestChip(req.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.selected,
                    child: Text(
                      _initials(req.fullName),
                      style: const TextStyle(
                        color: AppColors.brandGoldText,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              req.fullName,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            statusChip,
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          linkedWorker != null
                              ? 'Existing company worker · ${linkedWorker.trade} · ${Formatters.peso(linkedWorker.dailyRate)}/day'
                              : 'New laborer request · Will be added to active site crew on approval',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (req.rejectionReason != null &&
                  req.rejectionReason!.trim().isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: AppRadii.mdAll,
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'Rejection reason: ${req.rejectionReason}',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              AppSectionCard(
                title: 'Laborer & site assignment details',
                icon: Icons.badge_outlined,
                child: Column(
                  children: [
                    AppInfoRow(
                      label: 'Project',
                      value: [
                        if (widget.projectCode != null) widget.projectCode!,
                        if (widget.projectName != null) widget.projectName!,
                      ].join(' · '),
                    ),
                    if (linkedWorker != null) ...[
                      AppInfoRow(label: 'Trade', value: linkedWorker.trade),
                      AppInfoRow(
                        label: 'Daily rate',
                        value: Formatters.peso(linkedWorker.dailyRate),
                      ),
                    ],
                    AppInfoRow(
                      label: 'Phone number',
                      value: req.phone.trim().isEmpty ? '—' : req.phone,
                    ),
                    AppInfoRow(
                      label: 'Address',
                      value: req.address.trim().isEmpty ? '—' : req.address,
                    ),
                    AppInfoRow(
                      label: 'Requested by',
                      value: req.requestedByName ?? 'Site Engineer',
                    ),
                    if (req.createdAt != null)
                      AppInfoRow(
                        label: 'Requested on',
                        value: Formatters.dateTime(req.createdAt!.toLocal()),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _ModalFooterBar(
          hint: isPending
              ? 'Approving adds this laborer to the project roster and daily attendance sheet.'
              : isApproved
                  ? 'This laborer is now active on the project.'
                  : 'This laborer request was rejected.',
          actions: [
            if (isPending) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _rejectIds([req.id]),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Reject'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _approveIds([req.id]),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Approve'),
              ),
            ] else
              FilledButton(
                onPressed: widget.onClose,
                child: const Text('Done'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildBulkView(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final pending = _pendingRequests;
    final selectedPending = [
      for (final r in pending)
        if (_selectedIds.contains(r.id)) r.id,
    ];
    final allSelected =
        pending.isNotEmpty && selectedPending.length == pending.length;
    final someSelected = selectedPending.isNotEmpty && !allSelected;
    final existingCount = _requests.where((r) => r.workerId != null).length;
    final newCount = _requests.length - existingCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_requests.length} laborers requested',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (existingCount > 0) '$existingCount existing crew',
                          if (newCount > 0) '$newCount new laborer(s)',
                          '${pending.length} awaiting decision',
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (pending.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? cs.surfaceContainerHighest
                            : AppColors.surfaceSunken,
                        borderRadius: AppRadii.mdAll,
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            tristate: true,
                            value: allSelected
                                ? true
                                : (someSelected ? null : false),
                            onChanged: _busy
                                ? null
                                : (_) => _toggleSelectAll(!allSelected),
                          ),
                          GestureDetector(
                            onTap: _busy
                                ? null
                                : () => _toggleSelectAll(!allSelected),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                'Select all (${selectedPending.length}/${pending.length})',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Material(
                color: cs.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.lgAll,
                  side: BorderSide(color: cs.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < _requests.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: cs.outlineVariant),
                      _buildBulkRow(context, _requests[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        _ModalFooterBar(
          hint: pending.isNotEmpty
              ? 'Select all or untick specific workers to approve or reject in bulk.'
              : 'All laborer requests in this batch have been decided.',
          actions: [
            if (pending.isNotEmpty) ...[
              OutlinedButton.icon(
                onPressed: _busy || selectedPending.isEmpty
                    ? null
                    : () => _rejectIds(selectedPending),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text('Reject selected (${selectedPending.length})'),
              ),
              FilledButton.icon(
                onPressed: _busy || selectedPending.isEmpty
                    ? null
                    : () => _approveIds(selectedPending),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text('Approve selected (${selectedPending.length})'),
              ),
            ] else
              FilledButton(
                onPressed: widget.onClose,
                child: const Text('Done'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildBulkRow(BuildContext context, ProjectWorkerRequest req) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPending = req.status == ProjectWorkerRequestStatus.pending;
    final isSelected = isPending && _selectedIds.contains(req.id);
    final linked = req.workerId != null ? _workersById[req.workerId!] : null;

    final detailParts = <String>[
      if (linked != null)
        '${linked.trade} · ${Formatters.peso(linked.dailyRate)}/day'
      else
        'New laborer',
      if (req.phone.trim().isNotEmpty) req.phone,
      if (req.address.trim().isNotEmpty) req.address,
      if (req.requestedByName != null &&
          req.requestedByName!.trim().isNotEmpty)
        'Req. by ${req.requestedByName}',
    ];

    return InkWell(
      onTap: isPending && !_busy ? () => _toggleOne(req.id) : null,
      child: Container(
        color: isSelected
            ? cs.primary.withValues(alpha: isDark ? 0.08 : 0.05)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (isPending)
              Checkbox(
                value: isSelected,
                onChanged: _busy ? null : (_) => _toggleOne(req.id),
              )
            else
              const SizedBox(width: 12),
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.selected,
              child: Text(
                _initials(req.fullName),
                style: const TextStyle(
                  color: AppColors.brandGoldText,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    req.fullName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detailParts.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _workerRequestChip(req.status),
          ],
        ),
      ),
    );
  }

  static AppStatusChip _workerRequestChip(ProjectWorkerRequestStatus status) =>
      switch (status) {
        ProjectWorkerRequestStatus.pending => const AppStatusChip(
          label: 'Pending',
          foreground: AppColors.warning,
          background: AppColors.warningContainer,
        ),
        ProjectWorkerRequestStatus.approved => const AppStatusChip(
          label: 'Approved',
          foreground: AppColors.success,
          background: AppColors.successContainer,
        ),
        ProjectWorkerRequestStatus.rejected => const AppStatusChip(
          label: 'Rejected',
          foreground: AppColors.error,
          background: AppColors.errorContainer,
        ),
      };
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

// ============================================================================
// 2. TO-DO VERIFICATION REVIEW PANE
// ============================================================================

class _TodoVerificationReviewPane extends StatefulWidget {
  const _TodoVerificationReviewPane({
    required this.todoId,
    required this.projectId,
    required this.onChanged,
    required this.onClose,
  });

  final int todoId;
  final int? projectId;
  final VoidCallback onChanged;
  final VoidCallback onClose;

  @override
  State<_TodoVerificationReviewPane> createState() =>
      _TodoVerificationReviewPaneState();
}

class _TodoVerificationReviewPaneState
    extends State<_TodoVerificationReviewPane> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Todo? _todo;
  Category? _category;
  Project? _project;
  String? _doneByName;

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
      final schedule = getIt<ScheduleRepository>();
      final projects = getIt<ProjectRepository>();
      final session = getIt<SessionService>();

      Project? project;
      if (widget.projectId != null) {
        project = await projects.getProject(widget.projectId!);
      } else {
        for (final p in await projects.getProjectsFor(
          session.user!.id,
          session.activeRole!,
        )) {
          final todos = await schedule.getTodos(p.id);
          if (todos.any((t) => t.id == widget.todoId)) {
            project = p;
            break;
          }
        }
      }
      if (project == null) {
        if (mounted) setState(() => _error = 'Project not found.');
        return;
      }
      final todos = await schedule.getTodos(project.id);
      final todo = todos.where((t) => t.id == widget.todoId).firstOrNull;
      if (todo == null) {
        if (mounted) setState(() => _error = 'Task not found.');
        return;
      }
      final categories = await schedule.getCategories(project.id);
      final category = categories
          .where((c) => c.id == todo.categoryId)
          .firstOrNull;
      String? doneByName;
      if (todo.doneBy != null && getIt.isRegistered<UserRepository>()) {
        final users = await getIt<UserRepository>().getUsers();
        doneByName = users
            .where((u) => u.id == todo.doneBy)
            .firstOrNull
            ?.fullName;
      }
      if (!mounted) return;
      setState(() {
        _project = project;
        _todo = todo;
        _category = category;
        _doneByName = doneByName;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load task details. $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    final todo = _todo;
    if (todo == null) return;
    setState(() => _busy = true);
    try {
      final uid = getIt<SessionService>().user!.id;
      await getIt<ScheduleRepository>().verify(todo.id, userId: uid);
      widget.onChanged();
      if (mounted) {
        showSuccessAlert(context, 'Task verified.');
        widget.onClose();
      }
    } on BusinessRuleException catch (e) {
      if (mounted) showAppMessage(context, e.message);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not verify task. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppEmptyState(message: _error!);
    final todo = _todo!;
    final awaiting = todo.isAwaitingVerification;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    todo.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  AppStatusChip(
                    label: todo.isVerified
                        ? 'Verified'
                        : 'Awaiting verification',
                    foreground: todo.isVerified
                        ? AppColors.success
                        : AppColors.warning,
                    background: todo.isVerified
                        ? AppColors.successContainer
                        : AppColors.warningContainer,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: 'Schedule & site completion',
                icon: Icons.fact_check_outlined,
                child: Column(
                  children: [
                    if (_project != null)
                      AppInfoRow(
                        label: 'Project',
                        value: '${_project!.code} · ${_project!.name}',
                      ),
                    if (_category != null)
                      AppInfoRow(
                        label: 'Item of work',
                        value: _category!.name,
                      ),
                    AppInfoRow(
                      label: 'Scheduled window',
                      value: Formatters.dateRange(todo.startDate, todo.endDate),
                    ),
                    if (todo.doneAt != null)
                      AppInfoRow(
                        label: 'Marked done on',
                        value: Formatters.dateTime(todo.doneAt!.toLocal()),
                      ),
                    AppInfoRow(
                      label: 'Completed on site by',
                      value: _doneByName ?? 'Site Engineer',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _ModalFooterBar(
          hint: awaiting
              ? 'Only verified tasks count toward Item of Work completion and progress billing.'
              : 'This task has been verified and credited toward project progress.',
          actions: [
            if (awaiting)
              FilledButton.icon(
                onPressed: _busy ? null : _verify,
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('Verify task'),
              )
            else
              FilledButton(
                onPressed: widget.onClose,
                child: const Text('Done'),
              ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// 3. DAILY SITE REPORT REVIEW PANE
// ============================================================================

class _DailyReportReviewPane extends StatelessWidget {
  const _DailyReportReviewPane({
    required this.reportId,
    required this.onChanged,
    required this.onClose,
  });

  final int reportId;
  final VoidCallback onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey('modal-dr-$reportId'),
      create: (_) => DailyReportDetailViewModel(
        reportId: reportId,
        session: getIt(),
        projects: getIt(),
        reports: getIt(),
        masterData: getIt(),
        users: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<DailyReportDetailViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final d = vm.detail!;
        final r = d.report;
        const gap = SizedBox(height: AppSpacing.lg);
        String none(String what) => 'No $what recorded.';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Daily report · ${Formatters.date(r.reportDate)}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      DailyReportsStatusChip(status: r.status),
                      AppPdfButton(build: vm.pdfReport),
                    ],
                  ),
                  gap,
                  AppWorkflowSteps.dailyReport(r.status),
                  gap,
                  if (r.remarks != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.warningContainer,
                        borderRadius: AppRadii.mdAll,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.undo, color: AppColors.warning),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Returned by ${vm.userName(r.reviewedBy) ?? 'the owner'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.warning,
                                  ),
                                ),
                                Text(r.remarks!),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    gap,
                  ],
                  AppSectionCard(
                    title: 'Conditions',
                    child: Column(
                      children: [
                        AppInfoRow(label: 'Weather', value: r.weather.label),
                        AppInfoRow(
                          label: 'Toolbox meeting',
                          value: r.toolboxMeetingHeld ? 'Held' : 'Not held',
                        ),
                        AppInfoRow(
                          label: 'Submitted by',
                          value: vm.userName(r.submittedBy) ?? '—',
                        ),
                        if (r.reviewedBy != null)
                          AppInfoRow(
                            label: 'Reviewed by',
                            value: vm.userName(r.reviewedBy) ?? '—',
                          ),
                      ],
                    ),
                  ),
                  gap,
                  AppSectionCard(
                    title: 'Manpower (${d.totalHeadcount})',
                    child: d.manpower.isEmpty
                        ? Text(none('manpower'))
                        : Column(
                            children: [
                              for (final m in d.manpower)
                                AppInfoRow(
                                  label: m.trade,
                                  value: '${m.headcount}',
                                ),
                            ],
                          ),
                  ),
                  gap,
                  AppSectionCard(
                    title: 'To-dos accomplished',
                    child: d.todos.isEmpty
                        ? Text(none('to-dos'))
                        : Column(
                            children: [
                              for (final t in d.todos)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: Icon(
                                    t.isVerified
                                        ? Icons.verified
                                        : Icons.check_circle_outline,
                                    color: t.isVerified
                                        ? AppColors.success
                                        : null,
                                  ),
                                  title: Text(t.title),
                                  subtitle: Text(
                                    t.isVerified
                                        ? 'Verified'
                                        : t.isDone
                                            ? 'Awaiting verification'
                                            : 'Marked done on submit',
                                  ),
                                ),
                            ],
                          ),
                  ),
                  gap,
                  AppSectionCard(
                    title: 'Materials used',
                    child: d.materials.isEmpty
                        ? Text(none('materials'))
                        : Column(
                            children: [
                              for (final m in d.materials)
                                AppInfoRow(
                                  label: vm.materialName(m.materialId),
                                  value: InputParsers.amountText(m.quantity),
                                ),
                            ],
                          ),
                  ),
                  gap,
                  AppSectionCard(
                    title: 'Equipment',
                    child: d.equipment.isEmpty
                        ? Text(none('equipment'))
                        : Column(
                            children: [
                              for (final e in d.equipment)
                                AppInfoRow(
                                  label: vm.equipmentName(e.equipmentId),
                                  value:
                                      '${InputParsers.amountText(e.hoursUsed)} h',
                                ),
                            ],
                          ),
                  ),
                  gap,
                  AppSectionCard(
                    title: 'Issues and delays',
                    child: d.issues.isEmpty
                        ? Text(none('issues'))
                        : Column(
                            children: [
                              for (final x in d.issues)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${x.type.label} · ${x.reason.label}',
                                  ),
                                  subtitle: Text(
                                    '${x.description}'
                                    '${x.daysLost > 0 ? ' · ${InputParsers.amountText(x.daysLost)} day(s) lost' : ''}',
                                  ),
                                ),
                            ],
                          ),
                  ),
                  gap,
                  AppSectionCard(
                    title: 'Photos',
                    child: d.photos.isEmpty
                        ? Text(none('photos'))
                        : Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              for (final p in d.photos)
                                AppPhotoTile(
                                  fileUrl: p.fileUrl,
                                  caption: p.caption,
                                  subtitle: p.takenAt == null
                                      ? null
                                      : Formatters.dateTime(
                                          p.takenAt!.toLocal(),
                                        ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            _ModalFooterBar(
              hint: vm.canReview
                  ? 'Approving verifies accomplished tasks on this report.'
                  : 'Decision recorded for this daily site report.',
              actions: [
                if (vm.canReview) ...[
                  OutlinedButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () async {
                            final remarks =
                                await DailyReportsReturnDialog.show(context);
                            if (remarks != null && context.mounted) {
                              final ok = await reportAction(
                                context,
                                vm.returnReport(remarks),
                                success: 'Report returned.',
                              );
                              if (ok) onChanged();
                            }
                          },
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Return with remarks'),
                  ),
                  FilledButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () async {
                            final ok = await reportAction(
                              context,
                              vm.approve(),
                              success:
                                  'Report approved. Its to-dos are verified.',
                            );
                            if (ok) onChanged();
                          },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Approve'),
                  ),
                ] else
                  FilledButton(
                    onPressed: onClose,
                    child: const Text('Done'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// 4. MATERIAL REQUEST REVIEW PANE (WITH IN-MODAL OWN STORE & OTHER STORE FORMS)
// ============================================================================

enum _OrderSubMode { overview, ownStore, otherStore }

class _MaterialRequestReviewPane extends StatefulWidget {
  const _MaterialRequestReviewPane({
    required this.requestId,
    required this.onChanged,
    required this.onSubNavigation,
    required this.onClose,
  });

  final int requestId;
  final VoidCallback onChanged;
  final void Function({VoidCallback? onBack, String? title}) onSubNavigation;
  final VoidCallback onClose;

  @override
  State<_MaterialRequestReviewPane> createState() =>
      _MaterialRequestReviewPaneState();
}

class _MaterialRequestReviewPaneState
    extends State<_MaterialRequestReviewPane> {
  _OrderSubMode _mode = _OrderSubMode.overview;

  void _enterMode(_OrderSubMode next, MaterialRequestDetailViewModel vm) {
    setState(() => _mode = next);
    if (next == _OrderSubMode.overview) {
      widget.onSubNavigation(onBack: null, title: null);
    } else {
      widget.onSubNavigation(
        onBack: () => _enterMode(_OrderSubMode.overview, vm),
        title: next == _OrderSubMode.ownStore
            ? 'Order from own hardware store'
            : 'Bought from other store',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey('modal-mr-${widget.requestId}'),
      create: (_) => MaterialRequestDetailViewModel(
        requestId: widget.requestId,
        session: getIt(),
        procurement: getIt(),
        lookups: ProcurementLookups.fromServices(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<MaterialRequestDetailViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);

        if (_mode == _OrderSubMode.ownStore) {
          return OwnStoreOrderForm(
            requestId: widget.requestId,
            onSaved: () async {
              widget.onChanged();
              _enterMode(_OrderSubMode.overview, vm);
              await vm.load();
            },
          );
        }
        if (_mode == _OrderSubMode.otherStore) {
          return OtherStorePurchaseForm(
            requestId: widget.requestId,
            onSaved: () async {
              widget.onChanged();
              _enterMode(_OrderSubMode.overview, vm);
              await vm.load();
            },
          );
        }

        final r = vm.request!;
        final l = vm.lookups;
        const gap = SizedBox(height: AppSpacing.lg);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${r.number} · ${l.projectCode(r.projectId)}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      ProcurementRequestStatusChip(status: r.status),
                    ],
                  ),
                  gap,
                  AppWorkflowSteps.materialRequest(r.status),
                  gap,
                  AppSectionCard(
                    title: 'Details',
                    child: Column(
                      children: [
                        if (r.categoryId != null)
                          AppInfoRow(
                            label: 'Item of work',
                            value: l.categoryName(r.categoryId),
                          ),
                        AppInfoRow(
                          label: 'Needed by',
                          value: Formatters.date(r.neededBy),
                        ),
                        AppInfoRow(
                          label: 'Requested by',
                          value: l.userName(r.requestedBy),
                        ),
                        if (r.approvedBy != null)
                          AppInfoRow(
                            label: 'Approved by',
                            value: l.userName(r.approvedBy),
                          ),
                      ],
                    ),
                  ),
                  gap,
                  ProcurementRequestedItems(
                    items: vm.detail!.items,
                    orderNo: (id) =>
                        vm.orders.where((o) => o.id == id).firstOrNull?.poNo ??
                        'PO #$id',
                  ),
                  gap,
                  ProcurementSiteCounts(counts: vm.detail!.counts),
                  if (vm.orders.isNotEmpty) ...[
                    gap,
                    AppSectionCard(
                      title: 'Orders and purchases',
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final o in vm.orders)
                            ProcurementPoTile(
                              order: o,
                              projectCode: l.projectCode(o.projectId),
                              supplierName: l.storeName(o),
                              onTap: () {},
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _ModalFooterBar(
              hint: vm.canOrder
                  ? 'Fulfill from your own hardware store, log a purchase from another store, or reject.'
                  : 'This material request has been answered.',
              actions: [
                if (vm.canReject)
                  OutlinedButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () async {
                            final reason = await AppReasonDialog.show(
                              context,
                              title: 'Reject ${r.number}',
                              confirmLabel: 'Reject',
                            );
                            if (reason != null && context.mounted) {
                              final ok = await reportAction(
                                context,
                                vm.reject(reason),
                                success: 'Request rejected.',
                              );
                              if (ok) widget.onChanged();
                            }
                          },
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                  ),
                if (vm.canOrder) ...[
                  FilledButton.tonalIcon(
                    onPressed: () => _enterMode(_OrderSubMode.otherStore, vm),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Other store'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _enterMode(_OrderSubMode.ownStore, vm),
                    icon: const Icon(Icons.storefront_outlined, size: 18),
                    label: const Text('Own hardware store'),
                  ),
                ] else
                  FilledButton(
                    onPressed: widget.onClose,
                    child: const Text('Done'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// 5. VARIATION ORDER REVIEW PANE
// ============================================================================

class _VariationOrderReviewPane extends StatelessWidget {
  const _VariationOrderReviewPane({
    required this.voId,
    required this.onChanged,
    required this.onClose,
  });

  final int voId;
  final VoidCallback onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey('modal-vo-$voId'),
      create: (_) => VariationOrderDetailViewModel(
        voId: voId,
        session: getIt(),
        projects: getIt(),
        billing: getIt(),
        users: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<VariationOrderDetailViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final v = vm.vo!;
        final project = vm.project!;
        final showFinance = vm.role.seesFinance;
        const gap = SizedBox(height: AppSpacing.lg);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${v.voNo} · ${project.code}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      AppVoStatusChip(status: v.status),
                      if (v.status != VariationOrderStatus.proposed)
                        AppPdfButton(build: vm.pdfReport, label: 'Export VO'),
                    ],
                  ),
                  gap,
                  AppWorkflowSteps.variationOrder(
                    v,
                    proposedBy: vm.proposedByRole,
                  ),
                  gap,
                  AppSectionCard(
                    title: 'Scope & impact summary',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppInfoRow(label: 'Change type', value: v.type.label),
                        if (showFinance)
                          AppInfoRow(
                            label: 'Cost impact',
                            value:
                                '${v.amount >= 0 ? '+' : '−'}${Formatters.peso(v.amount.abs())}',
                          ),
                        AppInfoRow(
                          label: 'Schedule impact',
                          value: '${v.daysImpact} day(s)',
                        ),
                        if (v.description.trim().isNotEmpty) ...[
                          const Divider(height: AppSpacing.xl),
                          Text(
                            v.description,
                            style: AppTextStyles.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (v.hasRevisedSchedule) ...[
                    gap,
                    AppSectionCard(
                      title: 'Revised Bar Chart & DUPA (A–J)',
                      icon: Icons.table_chart_outlined,
                      child: VoRevisedScheduleSection(
                        projectId: v.projectId,
                        revisedSchedule: v.revisedSchedule,
                        showCosts: showFinance,
                        editable: false,
                      ),
                    ),
                  ],
                  if (v.hasAttachments) ...[
                    gap,
                    VoPhotoAttachmentsCard(vo: v),
                  ],
                  gap,
                  AppSectionCard(
                    title: 'History',
                    icon: Icons.history_rounded,
                    padding: EdgeInsets.zero,
                    child: AppHistoryList(
                      entries: vm.detail!.history,
                      userName: vm.userName,
                    ),
                  ),
                ],
              ),
            ),
            _ModalFooterBar(
              hint: vm.canPrepare
                  ? 'Approve and forward this variation order to the client, or reject with a reason.'
                  : 'Decision recorded for this variation order.',
              actions: [
                if (vm.canPrepare) ...[
                  OutlinedButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () async {
                            final reason = await AppReasonDialog.show(
                              context,
                              title: 'Reject ${v.voNo}',
                              confirmLabel: 'Reject',
                            );
                            if (reason != null && context.mounted) {
                              final ok = await reportAction(
                                context,
                                vm.reject(reason),
                              );
                              if (ok) onChanged();
                            }
                          },
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                  ),
                  FilledButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () async {
                            final ok = await reportAction(
                              context,
                              vm.submit(),
                              success: 'Sent to the client.',
                            );
                            if (ok) onChanged();
                          },
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Send to client'),
                  ),
                ] else
                  FilledButton(
                    onPressed: onClose,
                    child: const Text('Done'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// 6. ATTENDANCE / PAYROLL VERIFICATION REVIEW PANE
// ============================================================================

class _PayrollVerificationReviewPane extends StatelessWidget {
  const _PayrollVerificationReviewPane({
    required this.periodId,
    required this.onChanged,
    required this.onClose,
  });

  final int periodId;
  final VoidCallback onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey('modal-pay-$periodId'),
      create: (_) => PayrollPeriodDetailViewModel(
        periodId: periodId,
        session: getIt(),
        projects: getIt(),
        labor: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<PayrollPeriodDetailViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final p = vm.period!;
        final totalDays = vm.lines.fold<double>(0, (s, l) => s + l.daysWorked);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Payroll · ${Formatters.dateRange(p.periodStart, p.periodEnd)}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      LaborPeriodStatusChip(status: p.status),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${vm.project!.code} · ${vm.project!.name} · ${vm.lines.length} worker(s) · ${InputParsers.amountText(totalDays)} total day(s)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppWorkflowSteps.payroll(p.status),
                  const SizedBox(height: AppSpacing.lg),
                  AppSectionCard(
                    title: 'Attendance & pay summary',
                    padding: EdgeInsets.zero,
                    child: LaborPayrollTable(
                      lines: vm.lines,
                      workerName: vm.workerName,
                    ),
                  ),
                ],
              ),
            ),
            _ModalFooterBar(
              hint: vm.canVerify
                  ? (vm.verifyBlocker ??
                        'Verifying locks site attendance and forwards the cut-off to the Accountant for payout.')
                  : 'Attendance has been verified for this cut-off.',
              actions: [
                if (vm.canVerify)
                  FilledButton.icon(
                    onPressed: vm.isBusy || vm.verifyBlocker != null
                        ? null
                        : () async {
                            final ok = await reportAction(context, vm.verify());
                            if (ok && context.mounted) {
                              onChanged();
                              showSuccessAlert(
                                context,
                                'Attendance verified.',
                              );
                              onClose();
                            }
                          },
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Verify attendance'),
                  )
                else
                  FilledButton(
                    onPressed: onClose,
                    child: const Text('Done'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// 7. EQUIPMENT BORROW / RENTAL REQUEST REVIEW PANE (SINGLE & BULK)
// ============================================================================

class _EquipmentRequestReviewPane extends StatefulWidget {
  const _EquipmentRequestReviewPane({
    required this.requestIds,
    required this.projectId,
    required this.projectCode,
    required this.projectName,
    required this.onChanged,
    required this.onClose,
  });

  final List<int> requestIds;
  final int? projectId;
  final String? projectCode;
  final String? projectName;
  final VoidCallback onChanged;
  final VoidCallback onClose;

  @override
  State<_EquipmentRequestReviewPane> createState() =>
      _EquipmentRequestReviewPaneState();
}

class _EquipmentRequestReviewPaneState
    extends State<_EquipmentRequestReviewPane> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<EquipmentBorrow> _requests = const [];
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load(selectAllPending: true);
  }

  List<EquipmentBorrow> get _pendingRequests => _requests
      .where((r) => r.status == EquipmentBorrowStatus.pending)
      .toList();

  Future<void> _load({bool selectAllPending = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await getIt<EquipmentRepository>().getBorrows(
        projectId: widget.projectId,
      );
      final target = widget.requestIds.toSet();
      final matched = all.where((r) => target.contains(r.id)).toList();
      if (!mounted) return;
      setState(() {
        _requests = matched;
        if (matched.isEmpty) {
          _error = 'Equipment request not found.';
        } else {
          final pendingIds = {
            for (final r in matched)
              if (r.status == EquipmentBorrowStatus.pending) r.id,
          };
          _selectedIds.removeWhere((id) => !pendingIds.contains(id));
          if (selectAllPending || _selectedIds.isEmpty) {
            _selectedIds.addAll(pendingIds);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load equipment request. $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSelectAll(bool select) {
    setState(() {
      if (select) {
        _selectedIds.addAll(_pendingRequests.map((r) => r.id));
      } else {
        _selectedIds.clear();
      }
    });
  }

  void _toggleOne(int id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  Future<void> _approveIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final singleName = ids.length == 1
        ? _requests.where((r) => r.id == ids.first).firstOrNull?.equipmentName
        : null;
    setState(() => _busy = true);
    try {
      final uid = getIt<SessionService>().user!.id;
      final repo = getIt<EquipmentRepository>();
      for (final id in ids) {
        await repo.approveBorrow(id, userId: uid);
      }
      widget.onChanged();
      await _load(selectAllPending: true);
      if (!mounted) return;
      showSuccessAlert(
        context,
        singleName != null
            ? '$singleName approved and marked on site.'
            : '${ids.length} equipment requests approved.',
      );
      if (_pendingRequests.isEmpty) widget.onClose();
    } on BusinessRuleException catch (e) {
      if (mounted) showAppMessage(context, e.message);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not approve request. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rejectIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final singleName = ids.length == 1
        ? _requests.where((r) => r.id == ids.first).firstOrNull?.equipmentName
        : null;
    final reason = await AppReasonDialog.show(
      context,
      title: singleName != null
          ? 'Reject $singleName'
          : 'Reject ${ids.length} equipment requests',
      confirmLabel: 'Reject',
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final uid = getIt<SessionService>().user!.id;
      final repo = getIt<EquipmentRepository>();
      for (final id in ids) {
        await repo.rejectBorrow(id, userId: uid, reason: reason);
      }
      widget.onChanged();
      await _load(selectAllPending: true);
      if (!mounted) return;
      showSuccessAlert(
        context,
        ids.length == 1
            ? 'Equipment request rejected.'
            : '${ids.length} equipment requests rejected.',
      );
      if (_pendingRequests.isEmpty) widget.onClose();
    } on BusinessRuleException catch (e) {
      if (mounted) showAppMessage(context, e.message);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not reject request. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppEmptyState(message: _error!);

    if (_requests.length == 1) {
      return _buildSingle(context, _requests.first);
    }
    return _buildBulk(context);
  }

  Widget _buildSingle(BuildContext context, EquipmentBorrow req) {
    final isPending = req.status == EquipmentBorrowStatus.pending;
    final isOwned = req.source == EquipmentBorrowSource.owned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${req.equipmentName} × ${req.quantity}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  _statusChip(req.status),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: 'Equipment & borrower details',
                icon: Icons.handyman_outlined,
                child: Column(
                  children: [
                    AppInfoRow(
                      label: 'Source',
                      value: isOwned
                          ? 'Queen Builders owned equipment'
                          : 'External rental',
                    ),
                    if (!isOwned && req.rentalSupplier.isNotEmpty)
                      AppInfoRow(
                        label: 'Rental lessor',
                        value: req.rentalSupplier,
                      ),
                    AppInfoRow(
                      label: 'Borrowed by',
                      value: req.hasBorrower
                          ? '${req.borrowerName}${req.borrowerTrade != null ? ' (${req.borrowerTrade})' : ''}'
                          : 'General site crew',
                    ),
                    if (req.categoryName != null &&
                        req.categoryName!.isNotEmpty)
                      AppInfoRow(
                        label: 'Item of work',
                        value: req.categoryName!,
                      ),
                    AppInfoRow(
                      label: 'Date needed',
                      value: Formatters.date(req.neededDate),
                    ),
                    if (req.expectedReturnDate != null)
                      AppInfoRow(
                        label: 'Expected return',
                        value: Formatters.date(req.expectedReturnDate!),
                      ),
                    AppInfoRow(
                      label: 'Requested by',
                      value: req.requestedByName ?? 'Site Engineer',
                    ),
                    if (req.notes.isNotEmpty)
                      AppInfoRow(label: 'Purpose / notes', value: req.notes),
                  ],
                ),
              ),
            ],
          ),
        ),
        _ModalFooterBar(
          hint: isPending
              ? 'Approving marks this equipment as active on site under the borrower.'
              : 'Decision recorded for this equipment request.',
          actions: [
            if (isPending) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _rejectIds([req.id]),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Reject'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _approveIds([req.id]),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Approve'),
              ),
            ] else
              FilledButton(
                onPressed: widget.onClose,
                child: const Text('Done'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildBulk(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pending = _pendingRequests;
    final selectedPending = [
      for (final r in pending)
        if (_selectedIds.contains(r.id)) r.id,
    ];
    final allSelected =
        pending.isNotEmpty && selectedPending.length == pending.length;
    final someSelected = selectedPending.isNotEmpty && !allSelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${_requests.length} equipment requests',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (pending.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? cs.surfaceContainerHighest
                            : AppColors.surfaceSunken,
                        borderRadius: AppRadii.mdAll,
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            tristate: true,
                            value: allSelected
                                ? true
                                : (someSelected ? null : false),
                            onChanged: _busy
                                ? null
                                : (_) => _toggleSelectAll(!allSelected),
                          ),
                          Text(
                            'Select all (${selectedPending.length}/${pending.length})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Material(
                color: cs.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.lgAll,
                  side: BorderSide(color: cs.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < _requests.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: cs.outlineVariant),
                      Builder(
                        builder: (context) {
                          final req = _requests[i];
                          final isPending =
                              req.status == EquipmentBorrowStatus.pending;
                          final isSelected =
                              isPending && _selectedIds.contains(req.id);
                          return InkWell(
                            onTap: isPending && !_busy
                                ? () => _toggleOne(req.id)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  if (isPending)
                                    Checkbox(
                                      value: isSelected,
                                      onChanged: _busy
                                          ? null
                                          : (_) => _toggleOne(req.id),
                                    ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${req.equipmentName} × ${req.quantity}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          [
                                            req.source.label,
                                            if (req.hasBorrower)
                                              'Borrower: ${req.borrowerName}'
                                            else
                                              'Site crew',
                                            'Needed ${Formatters.date(req.neededDate)}',
                                          ].join(' · '),
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _statusChip(req.status),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        _ModalFooterBar(
          hint: pending.isNotEmpty
              ? 'Select all or untick items to approve or reject in bulk.'
              : 'All equipment requests in this batch have been decided.',
          actions: [
            if (pending.isNotEmpty) ...[
              OutlinedButton.icon(
                onPressed: _busy || selectedPending.isEmpty
                    ? null
                    : () => _rejectIds(selectedPending),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text('Reject selected (${selectedPending.length})'),
              ),
              FilledButton.icon(
                onPressed: _busy || selectedPending.isEmpty
                    ? null
                    : () => _approveIds(selectedPending),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text('Approve selected (${selectedPending.length})'),
              ),
            ] else
              FilledButton(
                onPressed: widget.onClose,
                child: const Text('Done'),
              ),
          ],
        ),
      ],
    );
  }

  static AppStatusChip _statusChip(EquipmentBorrowStatus status) =>
      switch (status) {
        EquipmentBorrowStatus.pending => const AppStatusChip(
          label: 'Pending',
          foreground: AppColors.warning,
          background: AppColors.warningContainer,
        ),
        EquipmentBorrowStatus.borrowed => const AppStatusChip(
          label: 'On site',
          foreground: AppColors.success,
          background: AppColors.successContainer,
        ),
        EquipmentBorrowStatus.returned => const AppStatusChip(
          label: 'Returned',
          foreground: AppColors.textSecondary,
          background: AppColors.surfaceSunken,
        ),
        EquipmentBorrowStatus.rejected => const AppStatusChip(
          label: 'Rejected',
          foreground: AppColors.error,
          background: AppColors.errorContainer,
        ),
      };
}

