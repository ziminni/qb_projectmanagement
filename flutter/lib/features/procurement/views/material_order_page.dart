import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/material_source.dart';
import 'other_store_purchase_form.dart';
import 'own_store_order_form.dart';

/// The owner's purchase order for a material request from one [source],
/// chosen with the buttons on the request page.
class MaterialOrderPage extends StatelessWidget {
  const MaterialOrderPage({
    super.key,
    required this.requestId,
    required this.source,
  });

  final int requestId;
  final MaterialSource source;

  @override
  Widget build(BuildContext context) {
    final padding = pagePadding(context);
    final own = source == MaterialSource.ownStore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            padding.top,
            padding.right,
            AppSpacing.sm,
          ),
          child: Text(
            own ? 'Order from own hardware store' : 'Bought from other store',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        Expanded(
          child: own
              ? OwnStoreOrderForm(requestId: requestId)
              : OtherStorePurchaseForm(requestId: requestId),
        ),
      ],
    );
  }
}
