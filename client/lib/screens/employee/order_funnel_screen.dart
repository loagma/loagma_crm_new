import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_config.dart';
import '../../services/api_service.dart';
import '../../services/open_visit_store.dart';
import '../../widgets/account_map_screen.dart';
import '../../widgets/create_sales_order_sheet.dart';
import '../telecaller/order_detail_screen.dart';
import '../telecaller/telecaller_mock_data.dart' show kComplaintCategories, kOrderStatusColors;

class OrderFunnelScreen extends StatefulWidget {
  final String accountId;
  final Map<String, dynamic>? account;

  const OrderFunnelScreen({
    super.key,
    required this.accountId,
    this.account,
  });

  @override
  State<OrderFunnelScreen> createState() => _OrderFunnelScreenState();
}

class _OrderFunnelScreenState extends State<OrderFunnelScreen> {
  static const _gold  = Color(0xFFD7BE69);
  static const _green = Color(0xFF43A047);

  // Fixed options for the "Notes Related To" dropdown.
  static const _relatedToOptions = [
    'Order', 'Payment', 'Complaint', 'Delivery', 'Product', 'Other',
  ];

  final ImagePicker _picker = ImagePicker();

  bool _visitedIn  = false;
  bool _visitedOut = false;

  DateTime? _visitInAt;
  Timer?    _timer;
  Duration  _elapsed = Duration.zero;

  // Geofence anchor — the salesman's position when he punched in.
  double? _anchorLat;
  double? _anchorLng;

  // 50m, not the 10m first suggested: phone GPS drifts 5-20m while standing
  // still, so a tighter fence closes visits the salesman is still attending.
  static const double _geofenceMeters = 50;

  StreamSubscription<Position>? _geoSub;
  bool _leftGeofence = false;
  bool _verifyingLocation = false;

  int _tab = 1; // 0 = History, 1 = Funnel, 2 = Transaction

  // ── Funnel form state ─────────────────────────────────────────────────────
  List<Map<String, dynamic>> _funnelOptions = [];
  bool   _loadingFunnel = true;
  String? _selectedSlug;
  String? _notesRelatedTo;
  bool   _savedLocally = false;   // funnel locally confirmed (not yet in DB)
  bool   _persisting   = false;   // writing to DB on Visit Out
  bool   _uploadingImage = false;
  final List<String> _images = [];
  final TextEditingController _notesCtrl = TextEditingController();

  // ── Transaction tab state ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _transactions = [];
  bool _loadingTx   = false;
  bool _txLoadedOnce = false;

  // ── Order History tab state ───────────────────────────────────────────────
  List<Map<String, dynamic>> _orders = [];
  bool _loadingOrders    = false;
  bool _ordersLoadedOnce = false;
  bool _ordersFailed     = false;
  Timer? _ordersPoll;

  Map<String, dynamic> get _acc => widget.account ?? {};
  bool get _editable => _visitedIn && !_visitedOut;
  bool get _isCustomerAccount => (_acc['account_type'] as String?) == 'customer';

  String? get _scheduleLabel {
    switch (_acc['frequency'] as String?) {
      case 'weekly':
        return 'WEEKLY';
      case 'monthly':
        return 'MONTHLY';
      case 'n_days':
        final n = _acc['interval_days'];
        return n == null ? 'RECURRING' : 'EVERY $n DAYS';
      default:
        return null;
    }
  }

  List<String> get _dayChips {
    if ((_acc['frequency'] as String?) == 'weekly') {
      return (_acc['days'] as List?)?.map((e) => e.toString()).toList() ?? [];
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    _loadFunnel();
    _restoreOpenVisit();
  }

  // Navigating back doesn't end a visit — it just disposes this screen. Rebuild
  // the in-progress visit from the store so returning shows the same visit,
  // still counting, instead of a fresh one.
  Future<void> _restoreOpenVisit() async {
    final open = await OpenVisitStore.load(widget.accountId);
    if (!mounted || open == null) return;
    setState(() {
      _visitedIn  = true;
      _visitInAt  = open.visitInAt;
      _elapsed    = DateTime.now().difference(open.visitInAt);
      _anchorLat  = open.lat;
      _anchorLng  = open.lng;
    });
    _startTicker();
    _startGeofenceWatch();
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _visitInAt == null) return;
      // Recomputed from the punch-in instant rather than incremented, so time
      // spent on another screen (or with the app backgrounded) still counts.
      setState(() => _elapsed = DateTime.now().difference(_visitInAt!));
    });
  }

  // Watches distance from the punch-in point for as long as this screen is
  // open. Leaving the fence ends the visit if a funnel stage was already
  // chosen; otherwise the visit stays open and the salesman is warned, since
  // the server (rightly) won't accept a visit with no stage and inventing one
  // would put a reason on record that he never gave.
  void _startGeofenceWatch() {
    if (_anchorLat == null || _anchorLng == null) return;
    _geoSub?.cancel();
    _geoSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(_onGeofencePosition, onError: (_) {});
  }

  void _onGeofencePosition(Position pos) {
    if (!mounted || !_visitedIn || _visitedOut) return;
    if (_anchorLat == null || _anchorLng == null) return;

    final metres = Geolocator.distanceBetween(
        _anchorLat!, _anchorLng!, pos.latitude, pos.longitude);

    if (metres <= _geofenceMeters) {
      if (_leftGeofence) setState(() => _leftGeofence = false);
      return;
    }

    if (_selectedSlug != null && !_persisting) {
      _geoSub?.cancel();
      _endVisit();
      return;
    }
    if (!_leftGeofence) setState(() => _leftGeofence = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _geoSub?.cancel();
    _ordersPoll?.cancel();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFunnel() async {
    final options = await ApiService.getOrderFunnels();
    if (!mounted) return;
    setState(() {
      _funnelOptions = options;
      _loadingFunnel = false;
    });
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _loadingTx = true;
      _txLoadedOnce = true;
    });
    final rows = await ApiService.getOrderFunnelResponses(widget.accountId);
    if (!mounted) return;
    setState(() {
      _transactions = rows;
      _loadingTx = false;
    });
  }

  /// [silent] is used by the background poll: it refreshes the list in place
  /// without flashing a spinner, and keeps the last good data if the poll fails.
  Future<void> _loadOrderHistory({bool silent = false}) async {
    // Orders hang off a real `user` row via orders.buyer_userid — a lead has no
    // such row, so there is nothing to fetch rather than an empty result.
    if (!_isCustomerAccount || widget.accountId.isEmpty) return;
    setState(() {
      // A silent poll must not clear an existing error state up front: if the
      // poll also fails, the error card would vanish and the empty list would
      // render as "no orders yet" — the exact lie this guards against.
      if (!silent) {
        _loadingOrders = true;
        _ordersFailed  = false;
      }
      _ordersLoadedOnce = true;
    });
    final res = await ApiService.getOrders(buyerUserId: widget.accountId, perPage: 50);
    if (!mounted) return;
    final raw = res['data'];
    setState(() {
      _loadingOrders = false;
      // Distinguish a genuinely empty history from a failed request — getOrders
      // returns success:false with an empty list on error, and reporting that as
      // "no orders" would be a lie.
      if (res['success'] == true && raw is List) {
        _orders       = raw.map((o) => Map<String, dynamic>.from(o as Map)).toList();
        _ordersFailed = false;
      } else if (!silent) {
        _ordersFailed = true;
      }
    });
  }

  // No push channel on this backend, so "live" is a poll — but only while the
  // History tab is actually on screen, so it costs nothing the rest of the time.
  void _startOrdersPolling() {
    _ordersPoll?.cancel();
    _ordersPoll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _tab != 0) return;
      _loadOrderHistory(silent: true);
    });
  }

  void _stopOrdersPolling() {
    _ordersPoll?.cancel();
    _ordersPoll = null;
  }

  String _titleCase(String s) => s.isEmpty
      ? s
      : s.split(RegExp(r'[_\s]+')).map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  // ── Visit lifecycle ───────────────────────────────────────────────────────

  double? get _shopLat => (_acc['latitude'] as num?)?.toDouble();
  double? get _shopLng => (_acc['longitude'] as num?)?.toDouble();

  /// Plenty of accounts still carry 0,0 rather than a real fix, and 0,0 is a
  /// point in the Atlantic — treating it as the shop would put every salesman
  /// thousands of km "away" and lock them out of those accounts entirely.
  bool get _hasShopLocation {
    final lat = _shopLat, lng = _shopLng;
    return lat != null && lng != null && !(lat == 0 && lng == 0);
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    LocationPermission permission = LocationPermission.denied;
    try {
      permission = await Geolocator.checkPermission();
    } catch (_) {}
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      try {
        permission = await Geolocator.requestPermission();
      } catch (_) {
        return false;
      }
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  void _visitError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: const Color(0xFFC0584C),
      duration: const Duration(seconds: 4),
    ));
  }

  // Outside the geofence, the salesman is asked to confirm rather than being
  // blocked outright — GPS drift or an inaccurate shop pin can put a genuine
  // visit outside the fence.
  Future<bool> _confirmFarVisit(double metres) async {
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not at shop location'),
        content: Text(
            'You are about ${metres.round()} m away from the shop '
            '(outside the ${_geofenceMeters.round()} m range). '
            'Do you still want to Visit In?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _startVisit() async {
    double? anchorLat;
    double? anchorLng;

    // A salesman may only punch in while he is actually at the shop. This is
    // only enforceable when the account has real coordinates to measure
    // against — see _hasShopLocation.
    if (_hasShopLocation) {
      setState(() => _verifyingLocation = true);

      Position? pos;
      if (await _ensureLocationPermission()) {
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          ).timeout(const Duration(seconds: 15));
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _verifyingLocation = false);

      // No fix means the check can't be performed. Letting the visit through
      // here would make the rule opt-out by simply switching GPS off.
      if (pos == null) {
        _visitError('Could not read your location. Turn on GPS/location permission and try again.');
        return;
      }

      final metres = Geolocator.distanceBetween(
          _shopLat!, _shopLng!, pos.latitude, pos.longitude);
      if (metres > _geofenceMeters) {
        final proceed = await _confirmFarVisit(metres);
        if (!mounted || !proceed) return;
      }

      // Measure the auto-close fence from the shop itself, since we now know
      // he started at it.
      anchorLat = _shopLat;
      anchorLng = _shopLng;
    }

    final startedAt = DateTime.now();
    setState(() {
      _visitedIn = true;
      _visitInAt = startedAt;
      _elapsed   = Duration.zero;
      _anchorLat = anchorLat;
      _anchorLng = anchorLng;
    });
    _startTicker();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Visit started')),
    );

    // Persist immediately so a back-press right after punching in can't lose
    // the visit.
    await OpenVisitStore.save(OpenVisit(
      accountId: widget.accountId,
      visitInAt: startedAt,
      lat: anchorLat,
      lng: anchorLng,
    ));

    if (anchorLat != null) {
      _startGeofenceWatch();
      return;
    }

    // Shop coordinates unknown, so fall back to wherever he punched in as the
    // auto-close anchor — the visit still can't be left open indefinitely.
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
    if (pos == null || !mounted) return;
    setState(() {
      _anchorLat = pos!.latitude;
      _anchorLng = pos.longitude;
    });
    _startGeofenceWatch();
    await OpenVisitStore.save(OpenVisit(
      accountId: widget.accountId,
      visitInAt: startedAt,
      lat: pos.latitude,
      lng: pos.longitude,
    ));
  }

  Future<void> _endVisit() async {
    // Require a funnel selection before closing the visit.
    if (_selectedSlug == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a funnel stage before Visit Out')),
      );
      return;
    }

    final outAt = DateTime.now();
    setState(() => _persisting = true);

    final result = await ApiService.saveOrderFunnelResponse(
      accountId:       widget.accountId,
      funnelSlug:      _selectedSlug!,
      accountType:     _acc['account_type'] as String?,
      beatPlanId:      _acc['beat_plan_id'] is int ? _acc['beat_plan_id'] as int : null,
      generalNotes:    _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      notesRelatedTo:  _notesRelatedTo,
      visitInAt:       _visitInAt?.toUtc().toIso8601String(),
      visitOutAt:      outAt.toUtc().toIso8601String(),
      durationSeconds: _visitInAt == null ? null : outAt.difference(_visitInAt!).inSeconds,
      images:          _images.isEmpty ? null : List<String>.from(_images),
    );

    // The visit is closed once the server has it — drop the local open-visit
    // record so reopening this account starts a fresh visit rather than
    // resurrecting this one.
    if (result != null && result['errors'] == null) {
      await OpenVisitStore.clear(widget.accountId);
    }

    if (!mounted) return;
    final ok = result != null && result['errors'] == null;
    setState(() {
      _persisting = false;
      if (ok) {
        _visitedOut = true;
        _timer?.cancel();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Visit completed — funnel saved' : 'Failed to save. Try again.'),
      backgroundColor: ok ? _green : Colors.red,
    ));

    // Refresh the Transaction list so the just-saved visit appears.
    if (ok) _loadTransactions();
  }

  // ── Local-only funnel save (synced to DB on Visit Out) ────────────────────
  void _saveFunnelLocal() {
    if (_selectedSlug == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a funnel stage')),
      );
      return;
    }
    setState(() => _savedLocally = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved — will sync to records on Visit Out')),
    );
  }

  // ── Images ────────────────────────────────────────────────────────────────
  Future<ImageSource?> _askImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _addImage() async {
    final source = await _askImageSource();
    if (source == null || !mounted) return;

    XFile? picked;
    try {
      picked = await _picker.pickImage(source: source, imageQuality: 80);
    } catch (e) {
      debugPrint('pickImage error: $e');
    }
    if (picked == null || !mounted) return;

    setState(() => _uploadingImage = true);
    final bytes = await picked.readAsBytes();
    final name  = picked.name.isNotEmpty ? picked.name : 'funnel.jpg';
    final path = await ApiService.uploadOrderFunnelImage(bytes, name);
    if (!mounted) return;
    setState(() {
      _uploadingImage = false;
      if (path != null && path.isNotEmpty) _images.add(path);
    });
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image upload failed')),
      );
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _whatsapp(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    final n = d.length == 10 ? '91$d' : d;
    _launch('https://wa.me/$n');
  }

  Future<void> _raiseComplaint() async {
    if (!_visitedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please Visit In before raising a complaint')),
      );
      return;
    }

    String? category;
    final descCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Raise Complaint', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    const Text('Category *', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: category,
                      isExpanded: true,
                      decoration: InputDecoration(
                        hintText: 'Select category',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                      items: kComplaintCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setSheetState(() => category = v),
                    ),
                    const SizedBox(height: 14),
                    const Text('Description *', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'What went wrong?',
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Please describe the issue' : null,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
                        onPressed: () {
                          if (category == null) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please select a category')));
                            return;
                          }
                          if (formKey.currentState?.validate() != true) return;
                          Navigator.pop(ctx, true);
                        },
                        child: const Text('Submit Complaint', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (submitted != true || !mounted) return;

    final res = await ApiService.createComplaint(
      accountId: widget.accountId,
      accountType: (_acc['account_type'] as String?) ?? 'lead',
      category: category!,
      description: descCtrl.text.trim(),
      beatPlanId: _acc['beat_plan_id'] is int ? _acc['beat_plan_id'] as int : null,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res != null ? 'Complaint raised successfully' : 'Failed to raise complaint — please try again')),
    );
  }

  // Same "Create Sales Order" sheet used from the telecaller's account
  // profile (CreateSalesOrderSheet, shared via widgets/create_sales_order_sheet.dart)
  // — it already knows a real Sales Order can only be created for a
  // registered customer (SalesOrderController::store requires buyer_userid
  // to match a `user` row) and falls back to a local-only draft with a clear
  // banner for a lead account, so no separate guard is needed here.
  Future<void> _takeOrder() async {
    final accountType = (_acc['account_type'] as String?) ?? 'lead';
    final address = (_acc['address'] as String?) ?? '';
    final lat = (_acc['latitude'] as num?)?.toDouble();
    final lng = (_acc['longitude'] as num?)?.toDouble();
    final deliveryAddress = (address.isNotEmpty || (lat != null && lng != null))
        ? {'address': address, 'latitude': lat, 'longitude': lng}
        : null;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateSalesOrderSheet(
        name: (_acc['businessName'] as String?) ?? '',
        accountId: widget.accountId,
        accountType: accountType,
        deliveryAddress: deliveryAddress,
        areaName: _acc['area'] as String?,
        contactNumber: _acc['contactNumber'] as String?,
        gstNumber: _acc['gstNumber'] as String?,
        accountCode: _acc['accountCode'] as String?,
        city: _acc['city'] as String?,
        state: _acc['state'] as String?,
        pincode: _acc['pincode'] as String?,
        onSave: (items, amt, status, pay, realOrderId) {
          if (!mounted) return;
          // The order the salesman just placed should be in the history
          // immediately, not 20 seconds later on the next poll.
          if (realOrderId != null) _loadOrderHistory(silent: true);
          // Unlike the telecaller flow, this screen has no local order list to
          // append a draft to (its "Order History" tab is a static placeholder)
          // — so for a lead account nothing is actually persisted here. Say so
          // honestly rather than claiming it was "saved".
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(realOrderId != null
                  ? 'Sales order #$realOrderId created — ₹$amt'
                  : 'Not saved — this account is a lead, not a registered customer yet. Convert it to a customer to create a real order.'),
              backgroundColor: realOrderId != null ? _green : null,
            ),
          );
        },
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final code    = _acc['accountCode']   as String? ?? '';
    final owner   = _acc['personName']    as String? ?? '';
    final shop    = _acc['businessName']  as String? ?? '—';
    final address = _acc['address']       as String? ?? '';
    final phone   = _acc['contactNumber'] as String? ?? '';
    final lat     = _acc['latitude'];
    final lng     = _acc['longitude'];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Account card ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEEEEEE)),
                boxShadow: const [BoxShadow(
                    color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Code + owner (single row)
                  Row(
                    children: [
                      Text(code,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black45,
                              letterSpacing: 0.4)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text('Owner Name : $owner',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Schedule chips + visit buttons. A weekly plan with
                  // several days selected produced enough chips to overflow
                  // a plain Row + Spacer on narrower widths — the chips now
                  // live in an Expanded Wrap so they wrap to a second line
                  // instead, while the two buttons stay pinned at the end.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (_scheduleLabel != null)
                              _Chip(label: _scheduleLabel!,
                                  bg: _green.withValues(alpha: 0.10), fg: const Color(0xFF2E7D32)),
                            ..._dayChips.map((d) => _Chip(label: d,
                                bg: Colors.grey.shade200, fg: Colors.black54)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Visit In
                      _VisitBtn(
                        label: _verifyingLocation ? 'Checking…' : 'Visit In',
                        active: !_visitedIn && !_verifyingLocation,
                        onTap: (_visitedIn || _verifyingLocation) ? null : _startVisit,
                      ),
                      const SizedBox(width: 6),
                      // Visit Out
                      _VisitBtn(
                        label: _persisting ? 'Saving…' : 'Visit Out',
                        active: _editable && !_persisting,
                        onTap: (_editable && !_persisting) ? _endVisit : null,
                      ),
                    ],
                  ),

                  // Walked out of the fence without choosing a stage — the
                  // visit is still running and still his to close.
                  if (_leftGeofence && _editable) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC0584C).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFFC0584C).withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_off_rounded,
                              size: 17, color: Color(0xFFC0584C)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You have left this shop and the visit is still open. '
                              'Pick a funnel stage, then tap Visit Out to close it.',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Visit timer
                  if (_visitedIn) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(_visitedOut ? Icons.check_circle_rounded : Icons.timer_rounded,
                            size: 18, color: _visitedOut ? _green : _gold),
                        const SizedBox(width: 6),
                        Text(
                          _visitedOut
                              ? 'Visit duration ${_fmt(_elapsed)}'
                              : 'In progress · ${_fmt(_elapsed)}',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700,
                              color: _visitedOut ? _green : Colors.black87),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 10),
                  // Shop name
                  Text('Shop Name : $shop',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  if (address.isNotEmpty)
                    Text('Address : $address',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 12),
                  // Actions + take order
                  Row(
                    children: [
                      _ActionBtn(
                        icon: Icons.call_rounded,
                        color: _green,
                        onTap: phone.isNotEmpty ? () => _launch('tel:$phone') : null,
                      ),
                      const SizedBox(width: 10),
                      _ActionBtn(
                        faIcon: FontAwesomeIcons.whatsapp,
                        color: const Color(0xFF25D366),
                        onTap: phone.isNotEmpty ? () => _whatsapp(phone) : null,
                      ),
                      const SizedBox(width: 10),
                      _ActionBtn(
                        icon: Icons.map_rounded,
                        color: const Color(0xFF1565C0),
                        onTap: (lat != null && lng != null)
                            ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AccountMapScreen(
                                    title: shop,
                                    accounts: [{
                                      ..._acc,
                                      '_type': _acc['account_type'] ?? 'lead',
                                    }],
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Complaint + Take Order — separated from the contact icons
                  // above since these are full actions, not quick-dial links.
                  // Both are gated on an open visit: the salesman has to be
                  // checked in before transacting. Call/WhatsApp/Map stay open
                  // so he can still reach the shop to announce his arrival.
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _editable ? _raiseComplaint : null,
                          icon: const Icon(Icons.report_problem_rounded, size: 16),
                          label: const Text('Raise Complaint',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade600,
                            side: BorderSide(
                                color: _editable ? Colors.red.shade300 : Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _editable ? _takeOrder : null,
                          icon: const Icon(Icons.shopping_cart_rounded, size: 16),
                          label: const Text('Take Order',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _gold.withValues(alpha: 0.35),
                            disabledForegroundColor: Colors.white70,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // A disabled button with no reason reads as a broken screen —
                  // say which state the visit is in instead.
                  if (!_editable) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _visitedOut
                                ? 'Visit closed — these actions are locked for this visit.'
                                : 'Tap Visit In to take an order or raise a complaint.',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey.shade600)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Tabs row ──────────────────────────────────────────────────
            Row(
              children: [
                Expanded(child: _TabBtn(
                    label: 'Order History', active: _tab == 0,
                    onTap: () {
                      setState(() => _tab = 0);
                      // Always refetch on entry, not just the first time — an
                      // order placed since the last look should already be here.
                      _loadOrderHistory(silent: _ordersLoadedOnce);
                      _startOrdersPolling();
                    })),
                const SizedBox(width: 10),
                Expanded(child: _TabBtn(
                    label: 'Order Funnel', active: _tab == 1,
                    onTap: () {
                      setState(() => _tab = 1);
                      _stopOrdersPolling();
                    })),
                const SizedBox(width: 10),
                Expanded(child: _TabBtn(
                    label: 'Transaction', active: _tab == 2,
                    onTap: () {
                      setState(() => _tab = 2);
                      _stopOrdersPolling();
                      if (!_txLoadedOnce) _loadTransactions();
                    })),
              ],
            ),

            const SizedBox(height: 14),

            // ── Tab content ────────────────────────────────────────────────
            if (_tab == 1)
              _buildFunnelTab()
            else if (_tab == 2)
              _buildTransactionTab()
            else
              _buildHistoryTab(),
          ],
        ),
      ),
    );
  }

  // ── Order Funnel tab ────────────────────────────────────────────────────
  Widget _buildFunnelTab() {
    final editable = _editable;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(
            color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Order Funnel',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),

          if (!_visitedIn)
            _banner('Please click "Visit In" to start editing')
          else if (_visitedOut)
            _banner('Visit completed. This funnel has been saved.', done: true),

          if (_loadingFunnel)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_funnelOptions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No funnel stages configured.',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
            )
          else
            _buildOptionsGrid(editable),

          const SizedBox(height: 16),
          const Text('Details',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),

          const Text('General Notes',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _notesCtrl,
            enabled: editable,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter general notes here...',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),

          const SizedBox(height: 14),
          const Text('Notes Related To',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _notesRelatedTo,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: 'Select',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            items: _relatedToOptions
                .map((o) => DropdownMenuItem(
                      value: o,
                      child: Text(o, style: const TextStyle(fontSize: 13)),
                    ))
                .toList(),
            onChanged: editable ? (v) => setState(() => _notesRelatedTo = v) : null,
          ),

          const SizedBox(height: 14),
          const Text('Photos',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _buildImagesRow(editable),

          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: editable ? _saveFunnelLocal : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _savedLocally ? _green : _gold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_savedLocally ? 'Saved ✓  (syncs on Visit Out)' : 'Save Funnel',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Order History tab ───────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    if (!_isCustomerAccount) {
      return const _PlaceholderCard(
          text: 'No order history — this account is still a lead, not a registered customer.');
    }
    if (_loadingOrders) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_ordersFailed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Column(
          children: [
            Icon(Icons.wifi_off_rounded, size: 34, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Could not load order history.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _loadOrderHistory,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _gold, foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }
    if (_orders.isEmpty) {
      return const _PlaceholderCard(text: 'No orders yet for this customer.');
    }
    return Column(children: _orders.map(_buildOrderCard).toList());
  }

  Widget _buildOrderCard(Map<String, dynamic> o) {
    final orderId = o['order_id']?.toString();
    final state   = _titleCase((o['order_state'] ?? '').toString());
    final pay     = _titleCase((o['payment_status'] ?? '').toString());
    final items   = (o['items_count'] as num?)?.toInt() ?? 0;
    final total   = (o['order_total'] as num?)?.toDouble() ?? 0;
    final when    = (o['order_datetime'] ?? '').toString();
    final sc      = kOrderStatusColors[state] ?? const Color(0xFF5A6472);

    return GestureDetector(
      onTap: orderId == null
          ? null
          : () async {
              // Order Detail can add/edit/delete line items, so refresh on the
              // way back rather than leaving a stale total on this card.
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)),
              );
              if (mounted) await _loadOrderHistory();
            },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          boxShadow: const [BoxShadow(
              color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 34,
                  width: 34,
                  decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.receipt_long_rounded,
                      size: 17, color: Color(0xFF9C7B1E)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Order #$orderId',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800)),
                      if (when.isNotEmpty)
                        Text(when,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('₹${total.round()}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (state.isNotEmpty) _orderPill(state, sc),
                if (pay.isNotEmpty) _orderPill(pay, const Color(0xFF5A6472)),
                _orderPill('$items item(s)', const Color(0xFF5A6472)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderPill(String label, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
      );

  // ── Transaction tab ─────────────────────────────────────────────────────
  Widget _buildTransactionTab() {
    if (_loadingTx) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_transactions.isEmpty) {
      return const _PlaceholderCard(text: 'No transactions yet.');
    }
    return Column(
      children: _transactions.map(_buildTransactionCard).toList(),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final stage   = tx['funnel_name'] as String? ?? '—';
    final related = tx['notes_related_to'] as String?;
    final notes   = tx['general_notes'] as String?;
    final dur     = tx['duration_seconds'];
    final whenRaw = (tx['visit_out_at'] ?? tx['created_at']) as String?;
    final when    = _fmtDate(whenRaw);
    final images  = (tx['images'] as List?)?.whereType<String>().toList() ?? [];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(
            color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(stage,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              if (when != null)
                Text(when,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            ],
          ),
          if (dur is int) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.timer_rounded, size: 15, color: _gold),
                const SizedBox(width: 5),
                Text('Duration ${_fmt(Duration(seconds: dur))}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
          if (related != null && related.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Related to: $related',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800)),
          ],
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(notes,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          ],
          if (images.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: images.map((p) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network('${ApiConfig.baseUrl}$p',
                    width: 64, height: 64, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 64, height: 64, color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image_rounded,
                            color: Colors.black26))),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  String? _fmtDate(String? iso) {
    if (iso == null) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return null;
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/${dt.year} $hh:$mm';
  }

  Widget _banner(String text, {bool done = false}) {
    final c = done ? _green : _gold;
    final fg = done ? const Color(0xFF1B5E20) : const Color(0xFF9C7B1E);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
              size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsGrid(bool editable) {
    return Wrap(
      runSpacing: 4,
      children: _funnelOptions.map((o) {
        final slug = o['slug'] as String?;
        final name = o['name'] as String? ?? '';
        return SizedBox(
          width: (MediaQuery.of(context).size.width - 28 - 28) / 2,
          child: RadioListTile<String>(
            value: slug ?? '',
            groupValue: _selectedSlug,
            onChanged: editable
                ? (v) => setState(() => _selectedSlug = v)
                : null,
            title: Text(name, style: const TextStyle(fontSize: 13)),
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            activeColor: _gold,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildImagesRow(bool editable) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ..._images.asMap().entries.map((e) {
          final idx = e.key;
          final url = '${ApiConfig.baseUrl}${e.value}';
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(url,
                    width: 72, height: 72, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 72, height: 72, color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image_rounded,
                            color: Colors.black26))),
              ),
              if (editable)
                Positioned(
                  right: -6, top: -6,
                  child: IconButton(
                    icon: const Icon(Icons.cancel, size: 20, color: Colors.redAccent),
                    onPressed: () => setState(() => _images.removeAt(idx)),
                  ),
                ),
            ],
          );
        }),
        // Add button
        GestureDetector(
          onTap: (editable && !_uploadingImage) ? _addImage : null,
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: editable ? _gold.withValues(alpha: 0.10) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: editable ? _gold : Colors.grey.shade300,
                  style: BorderStyle.solid),
            ),
            child: _uploadingImage
                ? const Center(
                    child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : Icon(Icons.add_a_photo_rounded,
                    color: editable ? _gold : Colors.grey.shade400),
          ),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _PlaceholderCard extends StatelessWidget {
  final String text;
  const _PlaceholderCard({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Center(
          child: Text(text,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final Color  bg, fg;
  const _Chip({required this.label, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      );
}

class _VisitBtn extends StatelessWidget {
  final String       label;
  final bool         active;
  final VoidCallback? onTap;
  const _VisitBtn({required this.label, required this.active, this.onTap});

  static const _gold = Color(0xFFD7BE69);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? _gold : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: active ? Colors.white : Colors.grey.shade600)),
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData?     icon;
  final IconData?     faIcon;
  final Color         color;
  final VoidCallback? onTap;
  const _ActionBtn({this.icon, this.faIcon, required this.color, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Center(
            child: faIcon != null
                ? FaIcon(faIcon, size: 17, color: color)
                : Icon(icon, size: 19, color: color),
          ),
        ),
      );
}

class _TabBtn extends StatelessWidget {
  final String       label;
  final bool         active;
  final VoidCallback onTap;
  const _TabBtn({required this.label, required this.active, required this.onTap});

  static const _gold = Color(0xFFD7BE69);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _gold : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: active ? _gold : const Color(0xFFEEEEEE)),
            boxShadow: const [BoxShadow(
                color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: active ? Colors.white : Colors.black87)),
        ),
      );
}
