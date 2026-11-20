import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/material_request_item.dart';
import '../../../data/models/store_product.dart';
import 'store_product_subtitle.dart';

/// Lets the owner choose the store product that answers one requested item.
///
/// The search starts with the engineer's own words, so the closest products
/// are already on top; [rank] orders the catalogue for any text typed.
class StoreProductPicker extends StatefulWidget {
  const StoreProductPicker({
    super.key,
    required this.item,
    required this.rank,
  });

  final MaterialRequestItem item;
  final List<StoreProduct> Function(String text) rank;

  static Future<StoreProduct?> show(
    BuildContext context, {
    required MaterialRequestItem item,
    required List<StoreProduct> Function(String text) rank,
  }) => showDialog<StoreProduct>(
    context: context,
    builder: (_) => StoreProductPicker(item: item, rank: rank),
  );

  @override
  State<StoreProductPicker> createState() => _StoreProductPickerState();
}

class _StoreProductPickerState extends State<StoreProductPicker> {
  late final _search = TextEditingController(text: widget.item.description);
  late List<StoreProduct> _results = widget.rank(_search.text);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asked =
        '${InputParsers.amountText(widget.item.quantity)} ${widget.item.unit}'
            .trim();
    return AlertDialog(
      title: const Text('Choose store product'),
      content: SizedBox(
        width: 520,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Requested: ${widget.item.description} · $asked',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search name or code',
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Show all products',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _search.clear();
                          _results = widget.rank('');
                        }),
                      ),
              ),
              onChanged: (v) => setState(() => _results = widget.rank(v)),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text('The store has no products.'))
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = _results[i];
                        final out = p.stockStatus == StoreStock.out;
                        return ListTile(
                          leading: Icon(
                            i == 0 && _search.text.trim().isNotEmpty
                                ? Icons.star_outline
                                : Icons.inventory_2_outlined,
                          ),
                          title: Text(p.name),
                          subtitle: Text(storeProductSubtitle(p)),
                          trailing: out
                              ? Text(
                                  'Out of stock',
                                  style: TextStyle(color: theme.colorScheme.error),
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).pop(p),
                        );
                      },
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
      ],
    );
  }
}
