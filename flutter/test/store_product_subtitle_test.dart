import 'package:buildpro_frontend/data/models/store_product.dart';
import 'package:buildpro_frontend/features/procurement/widgets/store_product_subtitle.dart';
import 'package:flutter_test/flutter_test.dart';

StoreProduct product({
  double? price = 275,
  StoreStock? stock,
  bool fromStore = true,
  double? shelf,
}) => StoreProduct(
  sku: 'QB000001-7',
  name: 'Portland cement 40 kg',
  unit: 'bag',
  price: price,
  stockStatus: stock,
  fromStore: fromStore,
  stock: shelf,
);

void main() {
  test('shows the store price and its stock status', () {
    final text = storeProductSubtitle(product(stock: StoreStock.low));

    expect(text, contains('QB000001-7'));
    expect(text, contains('275'));
    expect(text, contains('/ bag'));
    expect(text, endsWith('Low stock'));
  });

  test('each status has its own plain words', () {
    expect(
      storeProductSubtitle(product(stock: StoreStock.inStock)),
      endsWith('In stock'),
    );
    expect(
      storeProductSubtitle(product(stock: StoreStock.out)),
      endsWith('Out of stock'),
    );
  });

  test('an unknown status is not claimed to be in stock', () {
    final text = storeProductSubtitle(product());

    expect(text, isNot(contains('stock')));
  });

  test('an unavailable price says so, never zero', () {
    final text = storeProductSubtitle(product(price: null));

    expect(text, contains('Price unavailable'));
    expect(text, isNot(contains('₱0')));
  });

  test('a store that could not be reached says so instead of guessing', () {
    final text = storeProductSubtitle(product(price: null, fromStore: false));

    expect(text, contains('Store offline'));
    expect(text, contains('price and stock unavailable'));
  });

  test('a mock shelf count is still shown in the offline demo', () {
    expect(storeProductSubtitle(product(shelf: 540)), contains('540 in stock'));
  });
}
