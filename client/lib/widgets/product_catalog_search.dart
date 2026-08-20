import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../screens/telecaller/telecaller_mock_data.dart' show kGold, kGoldDark;
import '../services/api_service.dart';
import 'create_sales_order_sheet.dart' show OrderLineItem;

/// Search-and-browse product catalog for the Create Sales Order sheet —
/// search bar + scrollable product cards (image placeholder, LOAGMA code,
/// pack-price chips, qty stepper, Add). Feeds picked items straight into
/// the sheet's line-item cart via [onAdd] instead of the old "tap to open a
/// picker sheet, then type qty/price by hand" flow.
///
/// Price always comes from the selected pack — never typed in — so a
/// product with no `vendor_products` row for the current vendor (see
/// ProductController::search) simply can't be added yet; the card says so
/// and disables Add instead of asking for a hand-typed price.
class ProductCatalogSearch extends StatefulWidget {
  final void Function(OrderLineItem item) onAdd;
  // Rendered between the search field and the results list — e.g. the
  // store-name/pencil-edit bar in CreateSalesOrderSheet's catalog-first
  // layout. Kept generic here rather than hardcoding that bar, so this
  // widget doesn't need to know about Customer & Dates at all.
  final Widget? secondaryHeader;
  const ProductCatalogSearch({
    super.key,
    required this.onAdd,
    this.secondaryHeader,
  });

  @override
  State<ProductCatalogSearch> createState() => _ProductCatalogSearchState();
}

class _ProductCatalogSearchState extends State<ProductCatalogSearch> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  bool _failed = false;
  List<Map<String, dynamic>> _results = [];

  // Bumped on every new search; a response is only applied if it's still the
  // most recent one requested — guards a slower earlier request from
  // overwriting a faster later one.
  int _requestId = 0;

  final stt.SpeechToText _speech = stt.SpeechToText();
  // Only set once `_speech.initialize()` has actually succeeded — lets the mic
  // button tell "not initialized yet" apart from "genuinely unsupported here"
  // without re-requesting mic/speech permission on every tap.
  bool _speechReady = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    if (_listening) _speech.stop();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  // Tap once to start listening, tap again (or wait out the natural pause
  // that `onStatus` reports as "done"/"notListening") to stop. Recognized
  // words land straight in the search field and re-use the normal debounced
  // search path — voice search is just a different way to fill the same box.
  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    if (!_speechReady) {
      final available = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (error) {
          if (mounted) setState(() => _listening = false);
          Fluttertoast.showToast(
            msg: 'Voice search error: ${error.errorMsg}',
            backgroundColor: Colors.red,
            textColor: Colors.white,
          );
        },
      );
      if (!mounted) return;
      if (!available) {
        Fluttertoast.showToast(
          msg:
              'Voice search isn\'t available on this device — check microphone/speech permissions.',
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        return;
      }
      _speechReady = true;
    }

    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _searchCtrl.text = result.recognizedWords;
          _searchCtrl.selection = TextSelection.collapsed(
            offset: _searchCtrl.text.length,
          );
        });
        _onChanged(result.recognizedWords);
      },
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: true,
        partialResults: true,
      ),
    );
  }

  Future<void> _search(String q) async {
    final myRequestId = ++_requestId;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final results = await ApiService.searchProducts(q);
    if (!mounted || myRequestId != _requestId) return;
    setState(() {
      _loading = false;
      if (results == null) {
        _failed = true;
      } else {
        _results = results;
      }
    });
  }

  Widget _micButton() => GestureDetector(
    onTap: _toggleListening,
    child: Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: _listening ? const Color(0xFFC0584C) : kGold,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (_listening ? const Color(0xFFC0584C) : kGold).withValues(
              alpha: 0.45,
            ),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(
        _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
        color: Colors.white,
        size: 24,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: _listening ? 'Listening…' : 'Search products…',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: _listening
                      ? const Color(0xFFC0584C)
                      : Colors.grey.shade400,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: kGoldDark,
                  size: 20,
                ),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kGold.withValues(alpha: 0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kGold.withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kGold, width: 1.4),
                ),
              ),
            ),
            if (widget.secondaryHeader != null) ...[
              const SizedBox(height: 12),
              widget.secondaryHeader!,
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: kGold))
                  : _failed
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wifi_off_rounded,
                            size: 34,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Could not load products.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => _search(_searchCtrl.text),
                            icon: const Icon(
                              Icons.refresh_rounded,
                              size: 16,
                              color: kGoldDark,
                            ),
                            label: const Text(
                              'Retry',
                              style: TextStyle(color: kGoldDark),
                            ),
                          ),
                        ],
                      ),
                    )
                  : _results.isEmpty
                  ? Center(
                      child: Text(
                        'No products found',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 76),
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _ProductCatalogCard(
                        key: ValueKey(_results[i]['product_id']),
                        product: _results[i],
                        onAdd: widget.onAdd,
                      ),
                    ),
            ),
          ],
        ),
        Positioned(bottom: 4, right: 4, child: _micButton()),
      ],
    );
  }
}

class _ProductCatalogCard extends StatefulWidget {
  final Map<String, dynamic> product;
  final void Function(OrderLineItem item) onAdd;
  const _ProductCatalogCard({
    super.key,
    required this.product,
    required this.onAdd,
  });

  @override
  State<_ProductCatalogCard> createState() => _ProductCatalogCardState();
}

class _ProductCatalogCardState extends State<_ProductCatalogCard> {
  late final List<Map<String, dynamic>> _packs;
  String? _selectedPackId;
  int _qty = 1;
  late final String _fallbackUnit;

  @override
  void initState() {
    super.initState();
    _packs = ((widget.product['packs'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final defaultPack =
        _findPack((p) => p['is_default'] == true) ??
        (_packs.isNotEmpty ? _packs.first : null);
    _selectedPackId = defaultPack?['id'] as String?;
    final uom = (widget.product['stock_uom'] as String?)?.trim() ?? '';
    _fallbackUnit = uom.isEmpty ? 'PCS' : uom;
  }

  Map<String, dynamic>? _findPack(bool Function(Map<String, dynamic>) test) {
    for (final p in _packs) {
      if (test(p)) return p;
    }
    return null;
  }

  Map<String, dynamic>? get _selectedPack =>
      _findPack((p) => p['id'] == _selectedPackId);

  // Price is always taken from whichever pack is selected — never typed in —
  // so there's nothing to add without a real vendor price for this product.
  bool get _canAdd => _selectedPack != null;

  void _add() {
    final pack = _selectedPack;
    if (pack == null) return; // Add is disabled in this state — see _canAdd
    final price = (pack['price'] as num?)?.toDouble() ?? 0;
    final item = OrderLineItem();
    item.product.text = (widget.product['name'] as String?) ?? '';
    item.productId = widget.product['product_id'] as String?;
    item.gstPercent = (widget.product['gst_percent'] as num?)?.toDouble() ?? 0;
    item.qty.text = '$_qty';
    item.unit = _shortUnit(pack['label'] as String? ?? _fallbackUnit);
    item.unitPrice.text = price.toStringAsFixed(2);
    widget.onAdd(item);
    Fluttertoast.showToast(
      msg: 'Added ${item.product.text.trim()}',
      backgroundColor: kGold,
      textColor: Colors.white,
    );
    // Each Add always creates its own separate cart line (never merges into a
    // previous one, even for the same product/pack) — reset the stepper back
    // to 1 so switching packs and adding again starts from a clean qty each
    // time, instead of silently carrying over whatever was left on screen.
    setState(() => _qty = 1);
  }

  // Pack labels from `packs` are free text like "1 kg" / "500 gm" — the order
  // form's unit field expects a plain unit token, so this takes just the
  // trailing word (falls back to the whole label if that doesn't parse).
  String _shortUnit(String label) {
    final parts = label.trim().split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.last : label;
  }

  // A single-pack product has nothing to choose between, so it gets a plain
  // read-only info box instead of a (misleadingly tappable-looking) chip.
  Widget _singlePackBox(Map<String, dynamic> pack) {
    final mrp = (pack['mrp'] as num?)?.toDouble() ?? 0;
    final price = (pack['price'] as num?)?.toDouble() ?? 0;
    final label = (pack['label'] as String?) ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFE7E7E7)),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF20242B),
            ),
          ),
          if (mrp > price) ...[
            Text(
              '₹${mrp.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 11.5,
                decoration: TextDecoration.lineThrough,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            '₹${price.toStringAsFixed(price == price.roundToDouble() ? 0 : 2)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: kGoldDark,
            ),
          ),
        ],
      ),
    );
  }

  // Summary of the currently-selected pack, shown above the chip row so the
  // price stays visible even once the chips themselves scroll or wrap.
  Widget _packSummaryLine() {
    final pack = _selectedPack;
    if (pack == null) return const SizedBox.shrink();
    final price = (pack['price'] as num?)?.toDouble() ?? 0;
    final label = (pack['label'] as String?) ?? '';
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF20242B),
            ),
          ),
          TextSpan(
            text:
                '₹${price.toStringAsFixed(price == price.roundToDouble() ? 0 : 2)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: kGoldDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _packChip(Map<String, dynamic> pack) {
    final selected = pack['id'] == _selectedPackId;
    final mrp = (pack['mrp'] as num?)?.toDouble() ?? 0;
    final price = (pack['price'] as num?)?.toDouble() ?? 0;
    final label = (pack['label'] as String?) ?? '';
    return GestureDetector(
      onTap: () => setState(() => _selectedPackId = pack['id'] as String?),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? kGold : const Color(0xFFF6F6F7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? kGold : const Color(0xFFE7E7E7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF20242B),
              ),
            ),
            const SizedBox(width: 4),
            if (mrp > price) ...[
              Text(
                '₹${mrp.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 9,
                  decoration: TextDecoration.lineThrough,
                  color: selected ? Colors.white70 : Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 2),
            ],
            Text(
              '₹${price.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : kGoldDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyStepper() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF6F6F7),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _qty = _qty > 1 ? _qty - 1 : 1),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(
              Icons.remove_rounded,
              size: 15,
              color: Color(0xFF20242B),
            ),
          ),
        ),
        SizedBox(
          width: 22,
          child: Text(
            '$_qty',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        GestureDetector(
          onTap: () => setState(() => _qty += 1),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.add_rounded, size: 15, color: Color(0xFF20242B)),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final name = (widget.product['name'] as String?)?.trim() ?? '';
    final productId = (widget.product['product_id'] as String?) ?? '';
    // "Code: " + vendor-vendorProductId-category-subcategory-product, e.g.
    // "Code: 108-82-35-42-555". vendor_id/vendor_product_id are null when
    // there's no valid auth token, or (for vendor_product_id specifically)
    // when this vendor has no `vendor_products` listing for the product at
    // all — shown as "-" rather than silently dropping a segment, so the
    // format always stays 5 parts.
    String idSeg(dynamic v) =>
        (v == null || v.toString().isEmpty) ? '-' : v.toString();
    final ids = [
      idSeg(widget.product['vendor_id']),
      idSeg(widget.product['vendor_product_id']),
      idSeg(widget.product['cat_id']),
      idSeg(widget.product['subcat_id']),
      idSeg(productId),
    ].join('-');
    final code = 'Code: $ids';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEDEE)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF141F1F).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F6F7),
                  borderRadius: BorderRadius.circular(11),
                ),
                // No real product-photo hosting wired up yet (display_photo is a
                // bare relative path with no known domain) — placeholder icon
                // until that's available, rather than guessing a broken URL.
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: Colors.grey.shade400,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      code,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_packs.length == 1)
            _singlePackBox(_packs.first)
          else if (_packs.length > 1) ...[
            _packSummaryLine(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _packs.map(_packChip).toList(),
            ),
          ] else
            // No vendor_products row for this vendor+product — price is
            // never typed in by hand, so there's genuinely nothing to sell
            // here yet rather than a field to fill in.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F6F7),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'No price listed for this vendor',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Opacity(
                opacity: _canAdd ? 1 : 0.4,
                child: IgnorePointer(ignoring: !_canAdd, child: _qtyStepper()),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _canAdd ? _add : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _canAdd ? kGold : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'Add',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
