import 'package:flutter/material.dart';

import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/order_form_viewmodel.dart';

/// The budget category the owner charges an order to.
class ProcurementCategoryField extends StatelessWidget {
  const ProcurementCategoryField({super.key, required this.vm});

  final OrderFormViewModel vm;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Budget category',
      child: DropdownButtonFormField<int>(
        initialValue: vm.categoryId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Charge to category'),
        items: [
          for (final c in vm.categoryOptions)
            DropdownMenuItem(value: c.id, child: Text(c.name)),
        ],
        validator: (v) => v == null ? 'Choose the category.' : null,
        onChanged: vm.setCategory,
      ),
    );
  }
}
