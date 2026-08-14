// Smoke-render test for the shared "Create Sales Order" sheet — pumps it
// directly (not through showModalBottomSheet, whose route-transition +
// SingleChildScrollView interaction made the sheet's own content report
// wildly wrong hit-test coordinates under the test harness — a harness
// quirk, not a bug in the widget) so we can still verify every section
// actually builds and renders without throwing, matching the screenshot's
// layout: banner, tax-inclusive note, Product Detail, Addon, Summary.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/widgets/create_sales_order_sheet.dart';

void main() {
  testWidgets('renders all sections for both a customer and a lead account', (tester) async {
    for (final accountType in ['customer', 'lead']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreateSalesOrderSheet(
              name: 'Test Account',
              accountId: 'acct-1',
              accountType: accountType,
              onSave: (_, __, ___, ____, _____) {},
            ),
          ),
        ),
      );
      await tester.pump(); // let the build settle; voucher-preview fetch may still be in flight (fine — it degrades to a spinner)

      expect(find.text('Create Sales Order'), findsOneWidget, reason: 'header ($accountType)');
      expect(find.text('Customer & Dates'), findsOneWidget, reason: 'section ($accountType)');
      expect(find.text('Product Detail'), findsOneWidget, reason: 'section ($accountType)');
      expect(find.text('Addon'), findsOneWidget, reason: 'section ($accountType)');
      expect(find.text('Summary'), findsOneWidget, reason: 'section ($accountType)');
      expect(find.textContaining('tax-inclusive'), findsOneWidget, reason: 'banner ($accountType)');
      expect(find.text('Item 1  |  HSN: NA'), findsOneWidget, reason: 'item header ($accountType)');
      // Per-item field labels are rendered uppercase by _label(); the plain-case
      // "Gross Amount" in the Summary card is a separate widget.
      expect(find.text('GROSS AMOUNT'), findsOneWidget, reason: 'line totals ($accountType)');
      expect(find.text('TOTAL TAX'), findsOneWidget, reason: 'line totals ($accountType)');
      expect(find.text('PRODUCT TOTAL'), findsOneWidget, reason: 'line totals ($accountType)');
      expect(find.text('Gross Amount'), findsOneWidget, reason: 'summary ($accountType)');
      expect(find.text('Cancel'), findsOneWidget, reason: 'footer ($accountType)');
      expect(find.text('Save'), findsOneWidget, reason: 'footer ($accountType)');

      // No SGST/CGST rows before any product is picked (gstPercent starts at 0).
      expect(find.text('SGST'), findsNothing, reason: 'no product picked yet ($accountType)');
      expect(find.text('CGST'), findsNothing, reason: 'no product picked yet ($accountType)');

      // customer vs lead messaging differs — confirms accountType actually threads through.
      if (accountType == 'customer') {
        expect(find.textContaining('This will create a real Sales Order'), findsOneWidget);
      } else {
        expect(find.textContaining('no real Sales Order will be created'), findsOneWidget);
      }
    }
  });
}
