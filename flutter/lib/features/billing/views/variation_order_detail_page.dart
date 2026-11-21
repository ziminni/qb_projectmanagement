import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/variation_order.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_history_list.dart';
import '../../../shared/widgets/app_pdf_button.dart';
import '../../../shared/widgets/app_reason_dialog.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_vo_status_chip.dart';
import '../../../shared/widgets/app_workflow_steps.dart';
import '../viewmodels/variation_order_detail_viewmodel.dart';
import '../widgets/vo_photo_attachments.dart';

class VariationOrderDetailPage extends StatelessWidget {
  const VariationOrderDetailPage({super.key, required this.voId});

  final int voId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(voId),
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
        final wide = MediaQuery.sizeOf(context).width >= 900;

        final mainColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ScopeSummaryCard(vo: v, showFinance: vm.role.seesFinance),
            if (v.hasAttachments) ...[
              const SizedBox(height: AppSpacing.lg),
              VoPhotoAttachmentsCard(vo: v),
            ],
          ],
        );

        final sideColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SignOffCard(vm: vm),
            const SizedBox(height: AppSpacing.lg),
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
        );

        return ListView(
          padding: pagePadding(context),
          children: [
            _VoDetailHeader(
              vo: v,
              projectCode: project.code,
              projectName: project.name,
              actions: _buildActions(context, vm, v),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppWorkflowSteps.variationOrder(v, proposedBy: vm.proposedByRole),
            const SizedBox(height: AppSpacing.xl),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 13, child: mainColumn),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(flex: 7, child: sideColumn),
                ],
              )
            else ...[
              mainColumn,
              const SizedBox(height: AppSpacing.lg),
              sideColumn,
            ],
          ],
        );
      },
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    VariationOrderDetailViewModel vm,
    VariationOrder v,
  ) => [
    if (vm.canPrepare) ...[
      FilledButton.icon(
        onPressed: vm.isBusy
            ? null
            : () => reportAction(
                context,
                vm.submit(),
                success: 'Sent to the client.',
              ),
        icon: const Icon(Icons.send_rounded, size: 18),
        label: const Text('Send to client'),
      ),
      OutlinedButton.icon(
        onPressed: () =>
            context.go('${AppRoutes.variationOrders}/${v.id}/edit'),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Edit'),
      ),
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
                  await reportAction(context, vm.reject(reason));
                }
              },
        icon: const Icon(Icons.close_rounded, size: 18),
        label: const Text('Reject'),
      ),
    ],
    if (v.status != VariationOrderStatus.proposed)
      AppPdfButton(build: vm.pdfReport, label: 'Export VO'),
  ];
}

class _VoDetailHeader extends StatelessWidget {
  const _VoDetailHeader({
    required this.vo,
    required this.projectCode,
    required this.projectName,
    required this.actions,
  });

  final VariationOrder vo;
  final String projectCode;
  final String projectName;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.md,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                Text(
                  '${vo.voNo} · $projectCode',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                AppVoStatusChip(status: vo.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              projectName,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (actions.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: actions,
          ),
      ],
    );
  }
}

class _ScopeSummaryCard extends StatelessWidget {
  const _ScopeSummaryCard({required this.vo, required this.showFinance});

  final VariationOrder vo;
  final bool showFinance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final parsed = _parseScopeTag(vo.description);

    final typeColor = switch (vo.type) {
      VariationOrderType.additive => AppColors.brandGoldText,
      VariationOrderType.deductive => AppColors.success,
      VariationOrderType.change => AppColors.warning,
    };
    final typeIcon = switch (vo.type) {
      VariationOrderType.additive => Icons.add_circle_outline,
      VariationOrderType.deductive => Icons.remove_circle_outline,
      VariationOrderType.change => Icons.swap_horiz_rounded,
    };

    final costValue =
        '${vo.amount >= 0 ? '+' : '−'}${Formatters.peso(vo.amount.abs())}';
    final costColor = vo.amount > 0
        ? AppColors.brandGoldText
        : vo.amount < 0
        ? AppColors.success
        : scheme.onSurface;

    final daysValue = vo.daysImpact == 0
        ? '0 day(s)'
        : '${vo.daysImpact > 0 ? '+' : '−'}${vo.daysImpact.abs()} day(s)';
    final daysColor = vo.daysImpact > 0
        ? AppColors.warning
        : vo.daysImpact < 0
        ? AppColors.success
        : scheme.onSurface;

    final metrics = <Widget>[
      _SpecItem(
        label: 'Type',
        value: vo.type.label,
        icon: typeIcon,
        accent: typeColor,
      ),
      if (showFinance)
        _SpecItem(
          label: 'Cost impact',
          value: costValue,
          numeric: true,
          accent: costColor,
        ),
      _SpecItem(
        label: 'Additional days',
        value: daysValue,
        numeric: true,
        accent: daysColor,
      ),
    ];

    return AppSectionCard(
      title: 'Scope change',
      icon: Icons.difference_outlined,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            color: scheme.surfaceContainerLowest,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 460) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, item) in metrics.indexed) ...[
                          if (i > 0)
                            VerticalDivider(
                              width: AppSpacing.xl,
                              thickness: 1,
                              color: scheme.outlineVariant,
                            ),
                          Expanded(child: item),
                        ],
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, item) in metrics.indexed) ...[
                      if (i > 0)
                        Divider(
                          height: AppSpacing.lg,
                          color: scheme.outlineVariant,
                        ),
                      item,
                    ],
                  ],
                );
              },
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Description',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (parsed.tag != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.65,
                      ),
                      borderRadius: AppRadii.smAll,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Text(
                      parsed.tag!,
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Text(
                    parsed.body,
                    style: textTheme.bodyLarge?.copyWith(height: 1.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecItem extends StatelessWidget {
  const _SpecItem({
    required this.label,
    required this.value,
    this.icon,
    this.accent,
    this.numeric = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? accent;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: accent ?? scheme.onSurface),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                value,
                style:
                    (numeric
                            ? textTheme.titleMedium?.merge(
                                AppTextStyles.numeric,
                              )
                            : textTheme.titleMedium)
                        ?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: accent ?? scheme.onSurface,
                        ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SignOffCard extends StatelessWidget {
  const _SignOffCard({required this.vm});

  final VariationOrderDetailViewModel vm;

  @override
  Widget build(BuildContext context) {
    final v = vm.vo!;
    final p = vm.project!;
    final sentBy = v.approvedByOwner == null
        ? 'Pending'
        : vm.userName(v.approvedByOwner!);
    final approvedBy = v.approvedByClient == null
        ? 'Pending'
        : vm.userName(v.approvedByClient!);

    return AppSectionCard(
      title: 'Sign-off & record',
      icon: Icons.verified_outlined,
      child: Column(
        children: [
          _MetaRow(label: 'Project', value: '${p.code} · ${p.name}'),
          if (vm.proposedByRole != null)
            _MetaRow(label: 'Proposed by', value: vm.proposedByRole!),
          _MetaRow(
            label: 'Sent to client by',
            value: sentBy,
            muted: v.approvedByOwner == null,
          ),
          _MetaRow(
            label: 'Client approval',
            value: approvedBy,
            muted: v.approvedByClient == null,
          ),
          if (v.createdAt != null)
            _MetaRow(
              label: 'Created',
              value: Formatters.date(v.createdAt!),
              last: true,
            ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    this.muted = false,
    this.last = false,
  });

  final String label;
  final String value;
  final bool muted;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
                color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

({String? tag, String body}) _parseScopeTag(String description) {
  final trimmed = description.trim();
  if (trimmed.startsWith('[')) {
    final close = trimmed.indexOf(']');
    if (close > 1) {
      final tag = trimmed.substring(1, close).trim();
      final body = trimmed.substring(close + 1).trim();
      if (body.isNotEmpty) {
        return (tag: tag, body: body);
      }
    }
  }
  return (tag: null, body: trimmed);
}
