import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/store_product.dart';

/// One catalogue line: SKU, the store's price, and how much the store has.
///
/// The store's price is the real price, so an unavailable one is said so and
/// never shown as ₱0.00. A store that could not be reached is stated rather
/// than papered over with a CPMS figure, and an unknown stock status is not
/// claimed to be "in stock".
String storeProductSubtitle(StoreProduct p) => [
  if (p.sku.isNotEmpty) p.sku,
  if (p.price != null) '${Formatters.peso(p.price!)} / ${p.unit}',
  if (p.price == null && !p.fromStore)
    'Store offline: price and stock unavailable'
  else if (p.price == null)
    'Price unavailable',
  if (p.stockStatus != null) p.stockStatus!.label,
  // The offline demo's catalogue still carries a shelf count.
  if (p.stock != null) '${InputParsers.amountText(p.stock!)} in stock',
].join(' · ');
