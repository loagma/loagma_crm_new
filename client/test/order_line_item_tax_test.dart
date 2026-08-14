// Unit tests for the tax math introduced into OrderLineItem
// (client/lib/widgets/create_sales_order_sheet.dart) — the shared "Create
// Sales Order" sheet used by both the salesman and telecaller flows. The
// unit price is entered tax-inclusive; tax is extracted back out of it
// using the selected product's real gst_percent, split evenly into
// SGST/CGST (matching the existing intra-state-only precedent documented
// in docs/SALES_MODULE.md).

import 'package:flutter_test/flutter_test.dart';

import 'package:client/widgets/create_sales_order_sheet.dart';

void main() {
  group('OrderLineItem tax math', () {
    test('zero gst_percent → zero tax, gross == product total', () {
      final item = OrderLineItem();
      item.qty.text = '3';
      item.unitPrice.text = '2784';
      item.gstPercent = 0;

      expect(item.productTotal, 8352);
      expect(item.taxNum, 0);
      expect(item.sgstAmount, 0);
      expect(item.cgstAmount, 0);
      expect(item.grossAmount, 8352);
    });

    test('18% gst_percent, tax-inclusive price → exact SGST/CGST split (matches production round-trip test)', () {
      final item = OrderLineItem();
      item.qty.text = '3';
      item.unitPrice.text = '118'; // tax-inclusive
      item.gstPercent = 18;

      expect(item.productTotal, 354); // 3 * 118
      expect(item.sgstPercent, 9);
      expect(item.cgstPercent, 9);
      expect(item.grossAmount, closeTo(300, 0.001)); // taxable amount
      expect(item.taxNum, closeTo(54, 0.001));
      expect(item.sgstAmount, closeTo(27, 0.001));
      expect(item.cgstAmount, closeTo(27, 0.001));
    });

    test('5% gst_percent matches the screenshot scenario (Qty 3, unit price 2784)', () {
      final item = OrderLineItem();
      item.qty.text = '3';
      item.unitPrice.text = '2784';
      item.gstPercent = 5;

      expect(item.productTotal, 8352);
      expect(item.grossAmount, closeTo(7954.29, 0.01));
      expect(item.taxNum, closeTo(397.71, 0.01));
      expect(item.sgstAmount, closeTo(198.86, 0.01));
      expect(item.cgstAmount, closeTo(198.86, 0.01));
    });

    test('unset/invalid qty or price falls back to 0, never throws', () {
      final item = OrderLineItem();
      item.qty.text = '';
      item.unitPrice.text = 'not a number';
      item.gstPercent = 18;

      expect(item.qtyNum, 0);
      expect(item.priceNum, 0);
      expect(item.productTotal, 0);
      expect(item.taxNum, 0);
      expect(item.grossAmount, 0);
    });
  });

  group('OrderAddon', () {
    test('amount parses cleanly and defaults to 0 on bad input', () {
      final addon = OrderAddon('Hamali');
      expect(addon.amountNum, 0);
      addon.amount.text = '1000';
      expect(addon.amountNum, 1000);
      addon.amount.text = 'garbage';
      expect(addon.amountNum, 0);
    });
  });
}
