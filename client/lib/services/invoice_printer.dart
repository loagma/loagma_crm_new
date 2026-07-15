import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'api_service.dart';

// Builds a printable receipt PDF for one order (owner/contact/address, itemised
// table, totals) and hands it to the platform print dialog — the same flow as
// clicking "Print" on the reference web order-list, just generated in-app
// instead of depending on `invoice_pdf_url` (which is null/localhost for most
// historical orders).
class InvoicePrinter {
  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static Future<void> print(BuildContext context, String orderId, {Map<String, dynamic>? preloaded}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PreparingDialog(),
    );

    final order = preloaded ?? await ApiService.getOrderDetail(orderId);

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close the "preparing" dialog

    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load this order for printing')),
      );
      return;
    }

    final doc = _buildDocument(order);
    final bytes = await doc.save();

    try {
      // On desktop web this waits for a hidden iframe to load the PDF and
      // then calls print() on it. If the browser is set to "always download
      // PDFs" (a common setting) that iframe never fires its load event, so
      // this would otherwise hang forever with no error. Time it out and
      // fall back to a direct download so the user always gets *something*.
      final ok = await Printing.layoutPdf(
        name: 'Order_$orderId',
        onLayout: (format) async => bytes,
      ).timeout(const Duration(seconds: 8));

      if (!ok && context.mounted) {
        await _downloadFallback(context, orderId, bytes);
      }
    } catch (e, st) {
      debugPrint('InvoicePrinter.print layoutPdf failed/timed out: $e\n$st');
      if (context.mounted) {
        await _downloadFallback(context, orderId, bytes, layoutError: e);
      }
    }
  }

  static Future<void> _downloadFallback(
    BuildContext context,
    String orderId,
    Uint8List bytes, {
    Object? layoutError,
  }) async {
    try {
      await Printing.sharePdf(bytes: bytes, filename: 'Order_$orderId.pdf');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Print preview didn\'t open — invoice PDF downloaded instead')),
        );
      }
    } catch (e, st) {
      debugPrint('InvoicePrinter._downloadFallback failed: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print failed: ${layoutError ?? e}'),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  static pw.Document _buildDocument(Map<String, dynamic> order) {
    final orderId    = (order['order_id'] ?? '').toString();
    final buyerId    = (order['buyer_userid'] ?? '').toString();
    final orderDt    = (order['order_datetime'] ?? '').toString();
    final ownerName  = (order['owner_name'] ?? order['contact_name'] ?? '').toString();
    final contact    = (order['owner_contact'] ?? order['contact_number'] ?? '').toString();
    final address    = (order['delivery_address'] ?? order['address'] ?? '').toString();
    final items      = (order['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final subTotal   = _num(order['before_discount'] ?? order['order_total']);
    final discount   = _num(order['discount']);
    final deliveryCg = _num(order['delivery_charge']);
    final total      = _num(order['order_total']);

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Order No: $orderId',
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.Text(orderDt, style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
            if (buyerId.isNotEmpty) pw.Text('Customer ID: $buyerId', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 6),
            if (ownerName.isNotEmpty)
              pw.Text(ownerName, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            if (contact.isNotEmpty) pw.Text('Contact: $contact', style: const pw.TextStyle(fontSize: 9)),
            if (address.isNotEmpty) pw.Text(address, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
              },
              headers: ['ID', 'Name', 'Unit', 'Qty', 'Rate', 'Total'],
              data: items.map((it) {
                final qty  = (it['quantity'] as int?) ?? 0;
                final rate = _num(it['item_price']);
                final tot  = _num(it['item_total']);
                return [
                  (it['product_id'] ?? '').toString(),
                  (it['name'] ?? 'Item').toString(),
                  (it['pack_size'] ?? '').toString(),
                  qty.toString(),
                  rate.toStringAsFixed(2),
                  tot.toStringAsFixed(2),
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 10),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Sub total: ${subTotal.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Delivery Charge: ${deliveryCg.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Discount: ${discount.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 4),
                  pw.Text('Total: ${total.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return doc;
  }
}

class _PreparingDialog extends StatelessWidget {
  const _PreparingDialog();

  static const _gold = Color(0xFFD7BE69);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: _gold.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.print_rounded, color: _gold, size: 28),
            ),
            const SizedBox(height: 16),
            const Text('Preparing Print Preview',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Please wait...', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            const SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: _gold),
            ),
          ],
        ),
      ),
    );
  }
}
