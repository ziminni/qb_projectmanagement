import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../data/services/category_catalog_service.dart';
import '../../../data/services/schedule_rules.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_status_chip.dart';
import 'settings_section_frame.dart';

class SettingsCategoriesSection extends StatefulWidget {
  const SettingsCategoriesSection({super.key});

  @override
  State<SettingsCategoriesSection> createState() =>
      _SettingsCategoriesSectionState();
}

class _SettingsCategoriesSectionState extends State<SettingsCategoriesSection> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final CategoryCatalogService _catalog = getIt<CategoryCatalogService>();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _catalog.addListener(_onCatalogChanged);
    _catalog.loadAll().whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalogChanged);
    _name.dispose();
    super.dispose();
  }

  void _onCatalogChanged() {
    if (mounted) setState(() {});
  }

  void _addCategory() {
    if (!_formKey.currentState!.validate()) return;
    final value = _name.text.trim();
    _catalog.register(value);
    _name.clear();
    showAppMessage(context, 'Added "$value" to work categories.');
  }

  @override
  Widget build(BuildContext context) {
    final items = _catalog.suggestions;
    return SettingsSectionFrame(
      title: 'Work categories',
      description:
          'Standard WBS categories and categories added in projects (e.g. Foundation, Structural, Roofing).',
      children: [
        Form(
          key: _formKey,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'New category name',
                    hintText: 'e.g. Landscaping',
                  ),
                  validator: ScheduleRules.validateCategoryName,
                  onFieldSubmitted: (_) => _addCategory(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: _addCategory,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppSectionCard(
          title: 'Categories',
          icon: Icons.category_outlined,
          subtitle: '${items.length} total',
          padding: EdgeInsets.zero,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  children: [
                    for (final name in items)
                      ListTile(
                        dense: true,
                        title: Text(name),
                        trailing: _catalog.isCustomOnly(name)
                            ? IconButton(
                                tooltip: 'Remove custom category',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => _catalog.removeCustom(name),
                              )
                            : AppStatusChip(
                                label: _catalog.isDefault(name)
                                    ? 'Standard'
                                    : 'In project',
                                foreground: _catalog.isDefault(name)
                                    ? AppColors.textSecondary
                                    : AppColors.brandGoldText,
                                background: _catalog.isDefault(name)
                                    ? AppColors.surfaceMuted
                                    : AppColors.selected,
                              ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
