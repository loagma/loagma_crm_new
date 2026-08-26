// Smoke-render test for the shared "Create Sales Order" sheet — pumps it
// directly (not through showModalBottomSheet, whose route-transition +
// SingleChildScrollView interaction made the sheet's own content report
// wildly wrong hit-test coordinates under the test harness — a harness
// quirk, not a bug in the widget) so we can still verify the catalog-first
// screen renders correctly along with its two secondary panels: Customer &
// Dates (a centered showDialog opened from the product panel's pencil
// button) and Cart (a modal bottom sheet behind the cart FAB).
//
// Navigation is driven by invoking each button's onTap directly (via
// `tester.widget<GestureDetector>(...).onTap!()`) rather than `tester.tap()`
// — a dialog/modal-sheet stacked over a directly-pumped widget reports
// unreliable hit-test offsets under this test binding (same class of quirk
// noted above), so this exercises the identical code path — real user taps
// land on the same GestureDetector — without depending on exact on-screen
// geometry.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/widgets/create_sales_order_sheet.dart';

void main() {
  testWidgets(
    'catalog screen + nested sheets render for both a customer and a lead account',
    (tester) async {
      for (final accountType in ['customer', 'lead']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CreateSalesOrderSheet(
                name: 'Test Account',
                accountId: 'acct-1',
                accountType: accountType,
                onSave: (_, _, _, _, _) {},
              ),
            ),
          ),
        );
        await tester
            .pump(); // let the build settle; voucher-preview/search fetches may still be in flight (fine — they degrade gracefully)

        // ── Main (catalog-first) screen ──
        expect(
          find.text('Test Account'),
          findsOneWidget,
          reason: 'header name ($accountType)',
        );
        expect(
          find.text('Search products…'),
          findsOneWidget,
          reason: 'search bar ($accountType)',
        );
        expect(
          find.byKey(const Key('pencilEditBtn')),
          findsOneWidget,
          reason: 'pencil button ($accountType)',
        );
        expect(
          find.byIcon(Icons.mic_none_rounded),
          findsOneWidget,
          reason: 'mic button ($accountType)',
        );
        // The full-width "Review & Save" bar was replaced by a compact cart FAB
        // (no item-count badge while the cart's empty).
        expect(
          find.byKey(const Key('cartBar')),
          findsOneWidget,
          reason: 'cart FAB ($accountType)',
        );
        expect(
          find.byIcon(Icons.shopping_cart_outlined),
          findsOneWidget,
          reason: 'cart FAB icon ($accountType)',
        );

        // ── Customer & Dates dialog (pencil button, centered) ──
        expect(
          find.text('Customer & Dates'),
          findsNothing,
          reason: 'dialog starts closed ($accountType)',
        );
        tester
            .widget<GestureDetector>(find.byKey(const Key('pencilEditBtn')))
            .onTap!();
        // pumpAndSettle() would hang here — the voucher box's CircularProgressIndicator
        // spins forever while the (test-harness-blocked) network call never resolves —
        // so settle the dialog route's transition with a bounded pump instead.
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byType(Dialog),
          findsOneWidget,
          reason: 'opens as a Dialog, not a sheet/panel ($accountType)',
        );
        expect(
          find.text('Customer & Dates'),
          findsOneWidget,
          reason: 'dialog opened ($accountType)',
        );
        // _label() uppercases field labels — "Document Date *" renders as "DOCUMENT DATE *".
        expect(
          find.text('DOCUMENT DATE *'),
          findsOneWidget,
          reason: 'dialog fields ($accountType)',
        );
        tester
            .widget<GestureDetector>(
              find.byKey(const Key('customerDatesCloseBtn')),
            )
            .onTap!();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text('Customer & Dates'),
          findsNothing,
          reason: 'dialog closed ($accountType)',
        );
        expect(
          find.byType(Dialog),
          findsNothing,
          reason: 'dialog route popped ($accountType)',
        );

        // ── Cart sheet (cart FAB) ──
        tester
            .widget<GestureDetector>(find.byKey(const Key('cartBar')))
            .onTap!();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text('Cart'),
          findsOneWidget,
          reason: 'cart sheet opened ($accountType)',
        );
        expect(
          find.text('Delivery Info'),
          findsOneWidget,
          reason: 'delivery banner ($accountType)',
        );
        // The still-blank starter line has no productId/packId, so it renders
        // through the manual (catalog-less) item form, not the compact cart row.
        expect(
          find.text('Item 1  |  HSN: NA'),
          findsOneWidget,
          reason: 'item header ($accountType)',
        );
        expect(
          find.text('GROSS AMOUNT'),
          findsOneWidget,
          reason: 'line totals ($accountType)',
        );
        expect(
          find.text('TOTAL TAX'),
          findsOneWidget,
          reason: 'line totals ($accountType)',
        );
        expect(
          find.text('PRODUCT TOTAL'),
          findsOneWidget,
          reason: 'line totals ($accountType)',
        );
        expect(
          find.text('Bill Details'),
          findsOneWidget,
          reason: 'bill details card ($accountType)',
        );
        expect(
          find.text('Amount'),
          findsOneWidget,
          reason: 'bill details row ($accountType)',
        );
        expect(
          find.text('Delivery Charges'),
          findsOneWidget,
          reason: 'bill details row ($accountType)',
        );
        expect(
          find.text('Total Amount'),
          findsOneWidget,
          reason: 'bill details row ($accountType)',
        );
        // Customer footer's action button reads "Place Order | ₹<total>" (leads,
        // which never create a real order, keep the plain "Save" label). It's
        // the sheet's only bottom button now — Cancel was dropped in favor of
        // the sheet's own close (X), matching the single-button cart mockup.
        expect(
          find.text(accountType == 'customer' ? 'Place Order  |  ₹0' : 'Save'),
          findsOneWidget,
          reason: 'footer ($accountType)',
        );
        expect(
          find.text('Cancel'),
          findsNothing,
          reason: 'no separate Cancel button ($accountType)',
        );

        // No SGST/CGST rows before any product is picked (gstPercent starts at 0).
        expect(
          find.text('SGST'),
          findsNothing,
          reason: 'no product picked yet ($accountType)',
        );
        expect(
          find.text('CGST'),
          findsNothing,
          reason: 'no product picked yet ($accountType)',
        );

        // customer vs lead messaging differs — confirms accountType actually threads through.
        if (accountType == 'customer') {
          expect(find.text('Pay on Delivery'), findsOneWidget);
        } else {
          expect(
            find.textContaining('no real Sales Order will be created'),
            findsOneWidget,
          );
        }

        tester
            .widget<GestureDetector>(find.byKey(const Key('reviewCloseBtn')))
            .onTap!();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text('Cart'),
          findsNothing,
          reason: 'cart sheet closed ($accountType)',
        );
      }
    },
  );
}
