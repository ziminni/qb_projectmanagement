import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/project_worker_request.dart';
import '../../../data/models/worker.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_reason_dialog.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_status_chip.dart';
import '../viewmodels/project_laborers_viewmodel.dart';

/// Project "Laborers" tab: Foremen request to add workers (Full name, Address,
/// Phone number); Project Managers approve or reject them.
class ProjectLaborersPage extends StatelessWidget {
  const ProjectLaborersPage({super.key, required this.projectId});

  final int projectId;

  Future<void> _openRequestDialog(
    BuildContext context,
    ProjectLaborersViewModel vm,
  ) async {
    final result = await _RequestLaborerDialog.show(
      context,
      availableWorkers: vm.availableWorkers,
    );
    if (result == null || !context.mounted) return;
    if (result.workerIds.isNotEmpty) {
      final ok = await reportAction(
        context,
        vm.requestExistingWorkers(result.workerIds),
      );
      if (ok && context.mounted) {
        final n = result.workerIds.length;
        showSuccessAlert(
          context,
          '$n laborer request${n == 1 ? '' : 's'} sent to the project manager for approval.',
        );
      }
      return;
    }
    final ok = await reportAction(
      context,
      vm.requestWorker(
        fullName: result.fullName,
        address: result.address,
        phone: result.phone,
      ),
    );
    if (ok && context.mounted) {
      showSuccessAlert(
        context,
        'Request for ${result.fullName} sent to the project manager for approval.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey('laborers-$projectId'),
      create: (_) => ProjectLaborersViewModel(
        projectId: projectId,
        session: getIt(),
        labor: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ProjectLaborersViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) {
          return AppEmptyState(
            message: vm.error!,
            icon: Icons.error_outline,
            action: FilledButton.icon(
              onPressed: vm.load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          );
        }

        final pending = vm.pendingRequests;
        final rejected = vm.rejectedRequests;
        final workers = vm.projectWorkers;

        return ListView(
          padding: pagePadding(context),
          children: [
            AppPageHeader(
              title: 'Laborers',
              subtitle:
                  'Request workers for this project; requests go to the project manager for approval.',
              actions: [
                if (vm.canRequest)
                  FilledButton.icon(
                    onPressed: vm.isBusy
                        ? null
                        : () => _openRequestDialog(context, vm),
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                    label: const Text('Add laborer'),
                  ),
              ],
            ),
            AppSectionCard(
              title: 'Pending requests (${pending.length})',
              subtitle: vm.canReview
                  ? 'Approve to add the laborer to this project and attendance sheet'
                  : 'Waiting for project manager approval',
              icon: Icons.pending_actions_outlined,
              padding: EdgeInsets.zero,
              child: pending.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text('No pending laborer requests.'),
                    )
                  : Column(
                      children: [
                        for (final (i, req) in pending.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          _RequestRow(req: req, vm: vm),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppSectionCard(
              title: 'Approved laborers (${workers.length})',
              subtitle: 'Workers active on this project',
              icon: Icons.engineering_outlined,
              padding: EdgeInsets.zero,
              child: workers.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text('No laborers assigned to this project yet.'),
                    )
                  : Column(
                      children: [
                        for (final (i, w) in workers.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.selected,
                              child: Text(
                                _initials(w.fullName),
                                style: const TextStyle(
                                  color: AppColors.brandGoldText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(w.fullName),
                            subtitle: Text(
                              [
                                w.trade,
                                if (w.phone != null &&
                                    w.phone!.trim().isNotEmpty)
                                  w.phone!,
                                if (w.address != null &&
                                    w.address!.trim().isNotEmpty)
                                  w.address!,
                              ].join(' · '),
                            ),
                            trailing: const AppStatusChip(
                              label: 'Active',
                              foreground: AppColors.success,
                              background: AppColors.successContainer,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            if (rejected.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: 'Rejected requests (${rejected.length})',
                icon: Icons.cancel_outlined,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, req) in rejected.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      _RequestRow(req: req, vm: vm),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.req, required this.vm});

  final ProjectWorkerRequest req;
  final ProjectLaborersViewModel vm;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isPending = req.status == ProjectWorkerRequestStatus.pending;
    final isRejected = req.status == ProjectWorkerRequestStatus.rejected;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: isRejected
                ? AppColors.errorContainer
                : AppColors.warningContainer,
            child: Text(
              _initials(req.fullName),
              style: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isRejected ? AppColors.error : AppColors.warning,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  req.fullName,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (req.phone.isNotEmpty) req.phone,
                    if (req.address.isNotEmpty) req.address,
                    if (req.requestedByName != null)
                      'Requested by ${req.requestedByName}',
                    if (req.createdAt != null) Formatters.date(req.createdAt!),
                  ].join(' · '),
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (isRejected &&
                    req.rejectionReason != null &&
                    req.rejectionReason!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: AppRadii.smAll,
                    ),
                    child: Text(
                      'Reason: ${req.rejectionReason}',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (isPending && vm.canReview)
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                FilledButton.icon(
                  onPressed: vm.isBusy
                      ? null
                      : () async {
                          final ok = await reportAction(
                            context,
                            vm.approve(req.id),
                          );
                          if (ok && context.mounted) {
                            showSuccessAlert(
                              context,
                              '${req.fullName} approved and added to project laborers.',
                            );
                          }
                        },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: vm.isBusy
                      ? null
                      : () async {
                          final reason = await AppReasonDialog.show(
                            context,
                            title: 'Reject ${req.fullName}',
                            confirmLabel: 'Reject',
                          );
                          if (reason != null && context.mounted) {
                            await reportAction(
                              context,
                              vm.reject(req.id, reason),
                              success: 'Laborer request rejected.',
                            );
                          }
                        },
                  child: const Text('Reject'),
                ),
              ],
            )
          else
            AppStatusChip(
              label: req.status.label,
              foreground: isRejected ? AppColors.error : AppColors.warning,
              background: isRejected
                  ? AppColors.errorContainer
                  : AppColors.warningContainer,
            ),
        ],
      ),
    );
  }
}

enum _RequestMode { existing, newLaborer }

typedef _RequestLaborerResult = ({
  List<int> workerIds,
  String fullName,
  String address,
  String phone,
});

class _RequestLaborerDialog extends StatefulWidget {
  const _RequestLaborerDialog({required this.availableWorkers});

  final List<Worker> availableWorkers;

  static Future<_RequestLaborerResult?> show(
    BuildContext context, {
    required List<Worker> availableWorkers,
  }) => showDialog<_RequestLaborerResult>(
    context: context,
    builder: (_) => _RequestLaborerDialog(availableWorkers: availableWorkers),
  );

  @override
  State<_RequestLaborerDialog> createState() => _RequestLaborerDialogState();
}

class _RequestLaborerDialogState extends State<_RequestLaborerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _selectedIds = <int>{};
  late _RequestMode _mode = widget.availableWorkers.isNotEmpty
      ? _RequestMode.existing
      : _RequestMode.newLaborer;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  List<Worker> get _filteredWorkers {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.availableWorkers;
    return widget.availableWorkers
        .where(
          (w) =>
              w.fullName.toLowerCase().contains(q) ||
              w.trade.toLowerCase().contains(q) ||
              (w.phone?.toLowerCase().contains(q) ?? false) ||
              (w.address?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  void _submit() {
    if (_mode == _RequestMode.existing) {
      if (_selectedIds.isEmpty) return;
      Navigator.of(context).pop((
        workerIds: _selectedIds.toList(),
        fullName: '',
        address: '',
        phone: '',
      ));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((
      workerIds: const <int>[],
      fullName: _name.text.trim(),
      address: _address.text.trim(),
      phone: _phone.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final workers = _filteredWorkers;

    return AlertDialog(
      title: const Text('Request laborer'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_RequestMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _RequestMode.existing,
                  icon: Icon(Icons.search, size: 16),
                  label: Text('Choose existing'),
                ),
                ButtonSegment(
                  value: _RequestMode.newLaborer,
                  icon: Icon(Icons.person_add_alt_1_outlined, size: 16),
                  label: Text('New laborer'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_mode == _RequestMode.existing) ...[
              TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Search workers by name or trade',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(
                  borderRadius: AppRadii.mdAll,
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: workers.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          widget.availableWorkers.isEmpty
                              ? 'All active workers are already on this project or pending approval. Switch to "New laborer" to add someone new.'
                              : 'No workers match "$_query".',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: workers.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final w = workers[i];
                          final checked = _selectedIds.contains(w.id);
                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selectedIds.add(w.id);
                              } else {
                                _selectedIds.remove(w.id);
                              }
                            }),
                            title: Text(w.fullName),
                            subtitle: Text(
                              [
                                w.trade,
                                if (w.phone != null &&
                                    w.phone!.trim().isNotEmpty)
                                  w.phone!,
                                if (w.address != null &&
                                    w.address!.trim().isNotEmpty)
                                  w.address!,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
              ),
            ] else
              Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _name,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter the laborer\'s full name.'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _address,
                      decoration: const InputDecoration(labelText: 'Address'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter the laborer\'s address.'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter the laborer\'s phone number.'
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _mode == _RequestMode.existing && _selectedIds.isEmpty
                  ? null
                  : _submit,
          child: Text(
            _mode == _RequestMode.existing && _selectedIds.length > 1
                ? 'Send ${_selectedIds.length} requests'
                : 'Send request',
          ),
        ),
      ],
    );
  }
}

String _initials(String name) => name
    .split(' ')
    .where((p) => p.isNotEmpty)
    .take(2)
    .map((p) => p[0].toUpperCase())
    .join();
