import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../screens/telecaller/telecaller_mock_data.dart' show kGold, kGoldDark;
import '../services/api_service.dart';
import 'create_sales_order_sheet.dart' show OrderLineItem;
import 'quantity_picker_sheet.dart';

// A card's stepper *is* the add-to-cart control — `qty` is the live quantity
// for this exact product+pack, not a "how many to add next" staging value.
typedef CatalogQtyChanged =
    void Function({
      required String productId,
      required String? packId,
      required int qty,
      required OrderLineItem Function() buildItem,
    });

/// Search-and-browse product catalog for the Create Sales Order sheet —
/// search bar + scrollable product cards (image placeholder, LOAGMA code,
/// pack-price chips, qty stepper). Each pack's stepper directly reflects
/// (and edits) its own live cart line via [onQtyChanged]/[qtyFor] instead of
/// the old "tap to open a picker sheet, then type qty/price by hand" flow.
///
/// Price always comes from the selected pack — never typed in — so a
/// product with no `vendor_products` row for the current vendor (see
/// ProductController::search) simply can't be added yet; the card says so
/// and disables the stepper instead of asking for a hand-typed price.
class ProductCatalogSearch extends StatefulWidget {
  final CatalogQtyChanged onQtyChanged;
  // How many of this product+pack are already in the cart — read on build so
  // a card reflects reality (e.g. re-opening the catalog after adding 3 of a
  // pack shows "3", not a stepper reset back to 0).
  final int Function(String productId, String? packId) qtyFor;
  // Rendered between the search field and the results list — e.g. the
  // store-name/pencil-edit bar in CreateSalesOrderSheet's catalog-first
  // layout. Kept generic here rather than hardcoding that bar, so this
  // widget doesn't need to know about Customer & Dates at all.
  final Widget? secondaryHeader;
  const ProductCatalogSearch({
    super.key,
    required this.onQtyChanged,
    required this.qtyFor,
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

    try {
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
    } catch (e) {
      // Without this, a native-side failure (missing plugin registration,
      // OS-level mic permission blocked outright, etc.) throws *after* the
      // tap's synchronous gesture context — Flutter logs it to the console
      // and the button silently does nothing from the user's perspective.
      if (mounted) setState(() => _listening = false);
      Fluttertoast.showToast(
        msg: 'Voice search failed to start: $e',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
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

  @override
  Widget build(BuildContext context) {
    return Column(
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
            suffixIcon: GestureDetector(
              onTap: _toggleListening,
              child: Icon(
                _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: _listening ? const Color(0xFFC0584C) : kGoldDark,
                size: 20,
              ),
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
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 76),
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _ProductCatalogCard(
                    key: ValueKey(_results[i]['product_id']),
                    product: _results[i],
                    onQtyChanged: widget.onQtyChanged,
                    qtyFor: widget.qtyFor,
                  ),
                ),
        ),
      ],
    );
  }
}

class _ProductCatalogCard extends StatefulWidget {
  final Map<String, dynamic> product;
  final CatalogQtyChanged onQtyChanged;
  final int Function(String productId, String? packId) qtyFor;
  const _ProductCatalogCard({
    super.key,
    required this.product,
    required this.onQtyChanged,
    required this.qtyFor,
  });

  @override
  State<_ProductCatalogCard> createState() => _ProductCatalogCardState();
}

class _ProductCatalogCardState extends State<_ProductCatalogCard> {
  late final List<Map<String, dynamic>> _packs;
  String? _selectedPackId;
  late int _qty;
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
    // Defaults to whatever's already in the cart for this pack (0 if
    // nothing's been added yet) rather than always starting at 1 — the
    // stepper IS the live cart quantity, not a separate "how many to add"
    // staging value.
    _qty = _productId == null ? 0 : widget.qtyFor(_productId!, _selectedPackId);
  }

  String? get _productId => widget.product['product_id'] as String?;

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
  // `stock` (parsed from vendor_products.packs[].stk) is kept in sync across
  // every pack of the same product server-side, so the selected pack's own
  // figure already reflects the shared pool — see ProductController::parsePacks.
  int get _stock => (_selectedPack?['stock'] as num?)?.toInt() ?? 0;
  bool get _canAdd => _selectedPack != null && _stock > 0;

  Future<void> _openQtyPicker() async {
    if (!_canAdd) return;
    final picked = await showQuantityPickerSheet(
      context,
      productName: (widget.product['name'] as String?)?.trim() ?? '',
      packLabel: (_selectedPack!['label'] as String?) ?? '',
      currentQty: _qty == 0 ? 1 : _qty,
      maxQty: _stock,
    );
    if (picked != null) _changeQty(picked);
  }

  // Every +/-/picker change lands here — this pack's stepper *is* its live
  // cart line, so each change immediately creates/updates/removes that line
  // via onQtyChanged rather than staging a value behind a separate Add tap.
  void _changeQty(int newQty) {
    final pack = _selectedPack;
    if (pack == null) return;
    final clamped = newQty.clamp(0, _stock > 0 ? _stock : 0);
    setState(() => _qty = clamped);
    final productId = _productId;
    if (productId == null) return;
    widget.onQtyChanged(
      productId: productId,
      packId: _selectedPackId,
      qty: clamped,
      buildItem: () {
        final price = (pack['price'] as num?)?.toDouble() ?? 0;
        final item = OrderLineItem();
        item.product.text = (widget.product['name'] as String?) ?? '';
        item.productId = productId;
        item.packId = _selectedPackId;
        item.gstPercent =
            (widget.product['gst_percent'] as num?)?.toDouble() ?? 0;
        item.maxQty = _stock;
        item.packLabel = pack['label'] as String?;
        item.unit = _shortUnit(pack['label'] as String? ?? _fallbackUnit);
        item.unitPrice.text = price.toStringAsFixed(2);
        return item;
      },
    );
  }

  // Pack labels from `packs` are free text like "1 kg" / "500 gm" — the order
  // form's unit field expects a plain unit token, so this takes just the
  // trailing word (falls back to the whole label if that doesn't parse).
  String _shortUnit(String label) {
    final parts = label.trim().split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.last : label;
  }

  static const _chipGreen = Color(0xFF1EA37A);
  static const _stepperOlive = Color(0xFF9C8A4E);

  // A single-pack product has nothing to choose between, so it gets a plain
  // read-only info box instead of a (misleadingly tappable-looking) chip.
  Widget _singlePackBox(Map<String, dynamic> pack) =>
      _priceBox(pack, selected: true);

  // Summary of the currently-selected pack, shown above the chip row so the
  // price stays visible even once the chips themselves scroll or wrap.
  Widget _packSummaryLine() {
    final pack = _selectedPack;
    if (pack == null) return const SizedBox.shrink();
    return _priceBox(pack, selected: true);
  }

  // Bordered "label: ₹price" box — matches the crm-telecaller mockup's plain
  // (non-gold, non-full-width) price pill shown above the pack chip row.
  Widget _priceBox(Map<String, dynamic> pack, {required bool selected}) {
    final price = (pack['price'] as num?)?.toDouble() ?? 0;
    final label = (pack['label'] as String?) ?? '';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label : ',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF20242B),
                ),
              ),
              TextSpan(
                text:
                    '₹${price.toStringAsFixed(price == price.roundToDouble() ? 0 : 2)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF20242B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Green fill marks the *default* pack (vendor_products.default_pack_id,
  // surfaced as `is_default` by ProductController::parsePacks) — a fixed,
  // data-driven attribute that never moves just because the user tapped a
  // different pack. Which pack is actively selected (drives price/qty/Add)
  // is a separate, independent state shown via the gold border + check
  // instead, so the two concepts don't get visually conflated.
  Widget _packChip(Map<String, dynamic> pack) {
    final selected = pack['id'] == _selectedPackId;
    final isDefault = pack['is_default'] == true;
    final label = (pack['label'] as String?) ?? '';
    return GestureDetector(
      onTap: () => setState(() {
        _selectedPackId = pack['id'] as String?;
        // Each pack is its own independent cart line — switching to it shows
        // whatever's actually already in the cart for *that* pack (0 if
        // nothing's been added), not whatever qty the previous pack had.
        final productId = _productId;
        _qty = productId == null
            ? 0
            : widget.qtyFor(productId, _selectedPackId);
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDefault ? _chipGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? kGoldDark
                : (isDefault ? _chipGreen : const Color(0xFFE0E0E0)),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(
                Icons.check_circle_rounded,
                size: 12,
                color: isDefault ? Colors.white : kGoldDark,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDefault ? Colors.white : const Color(0xFF5B5B5B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // At 0 there's nothing to decrement or number to show — a compact "ADD"
  // pill takes the stepper's place; tapping it adds the first unit straight
  // to the cart and the full −/qty/+ stepper takes over from there.
  Widget _qtyStepper() {
    if (_qty == 0) {
      return GestureDetector(
        onTap: () => _changeQty(1),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _stepperOlive,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'ADD',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _stepperOlive,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _changeQty(_qty - 1),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.remove_rounded, size: 15, color: Colors.white),
            ),
          ),
          // Tapping the number itself opens the "Select Quantity" grid sheet —
          // a single tap to jump straight to a specific quantity, capped at
          // this pack's live stock, instead of repeatedly tapping +/-.
          GestureDetector(
            onTap: _openQtyPicker,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$_qty',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF20242B),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _changeQty(_qty + 1),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.add_rounded, size: 15, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

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
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F6F7),
                  borderRadius: BorderRadius.circular(14),
                ),
                // No real product-photo hosting wired up yet (display_photo is a
                // bare relative path with no known domain) — placeholder icon
                // until that's available, rather than guessing a broken URL.
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: Colors.grey.shade400,
                  size: 28,
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
          const SizedBox(height: 8),
          if (_packs.length == 1)
            // Indented to align under the name/code text column (image width
            // + the 12px gap beside it), not flush with the card's own edge.
            Padding(
              padding: const EdgeInsets.only(left: 84),
              child: _singlePackBox(_packs.first),
            )
          else if (_packs.length > 1) ...[
            Padding(
              padding: const EdgeInsets.only(left: 84),
              child: _packSummaryLine(),
            ),
            const SizedBox(height: 8),
            // Pack chips and the qty stepper/ADD pill share one row (wrapping
            // together, flush with the card's own left edge, under the image)
            // rather than the stepper sitting on its own row below.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ..._packs.map(_packChip),
                Opacity(
                  opacity: _canAdd ? 1 : 0.4,
                  child: IgnorePointer(
                    ignoring: !_canAdd,
                    child: _qtyStepper(),
                  ),
                ),
              ],
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
          // Multi-pack already put the stepper/ADD pill inside the chip Wrap
          // above — only single-pack and no-pack cards need it on its own row.
          if (_packs.length <= 1) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Spacer(),
                Opacity(
                  opacity: _canAdd ? 1 : 0.4,
                  child: IgnorePointer(
                    ignoring: !_canAdd,
                    child: _qtyStepper(),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
