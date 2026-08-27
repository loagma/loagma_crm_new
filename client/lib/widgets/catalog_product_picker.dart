import 'package:flutter/material.dart';

import 'create_sales_order_sheet.dart' show OrderLineItem;
import 'product_catalog_search.dart';

/// Opens the same product catalog (real pack pricing/stock, pack chips, qty
/// stepper) used by Create Sales Order and Order Details' "Add Item", but as
/// a single-pick flow for forms that just need one product+pack+qty back —
/// e.g. the manual/edit item form's "Product" search field, which used to
/// open the plain [ProductPickerSheet] (no pack pricing at all).
///
/// Every card's stepper starts at 0/"ADD" (nothing is ever "already picked"
/// here — [qtyFor] always returns 0), and the very first tap that brings a
/// pack's qty above 0 immediately returns that item and closes the sheet,
/// instead of staying open for a multi-item cart session.
Future<OrderLineItem?> showCatalogProductPicker(BuildContext context) {
  return showModalBottomSheet<OrderLineItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => Container(
      height: MediaQuery.of(sheetCtx).size.height * 0.92,
      padding: EdgeInsets.fromLTRB(
        18,
        8,
        18,
        14 + MediaQuery.of(sheetCtx).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Select Product',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(sheetCtx).pop(),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ProductCatalogSearch(
              qtyFor: (productId, packId) => 0,
              onQtyChanged:
                  ({
                    required productId,
                    required packId,
                    required qty,
                    required buildItem,
                  }) {
                    if (qty <= 0) return;
                    Navigator.of(sheetCtx).pop(buildItem()..qty.text = '$qty');
                  },
            ),
          ),
        ],
      ),
    ),
  );
}
