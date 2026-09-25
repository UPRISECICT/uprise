// lib/screens/web/org/org_merchandise.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../services/activity_logger.dart' as activity_log;
import '../../../theme/org_theme.dart';
import '../../../widgets/admin_export_button.dart';
import '../../../widgets/stat_cards.dart';
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/org_modal_shell.dart';
import '../../../widgets/student/app_image.dart';
import '../admin/export_util.dart';
import '../admin/export_pdf.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (mirrors student accounts)
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const double radiusSm = 8;
  static const double radiusMd = 14;
  static const double radiusPill = 100;
  static const Color borderSoft = Color(0xFFE2E6EA);
  // Card chrome shared with Event Proposals / OrgModalSection.
  static const Color cardBorder = Color(0xFFE8ECF0);
  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
  static final cardShadowHover = [
    BoxShadow(
      color: Colors.black.withAlpha(24),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  static InputDecoration inputDecoration(
    String label, {
    String? hint,
    IconData? icon,
    bool required = false,
  }) {
    final labelStyle = GoogleFonts.beVietnamPro(
      fontSize: 13,
      color: const Color(0xFF64748B),
    );
    return InputDecoration(
      label: required
          ? RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: label, style: labelStyle),
                  TextSpan(
                    text: ' *',
                    style: labelStyle.copyWith(color: UpriseColors.error),
                  ),
                ],
              ),
            )
          : null,
      labelText: required ? null : label,
      hintText: hint,
      // Was a prefixIcon on every field regardless of [icon] — a form with
      // a dozen fields meant a dozen near-identical generic icons doing no
      // real disambiguating work. Label text already says what the field
      // is; [icon] is kept for existing call sites but intentionally
      // unused now.
      labelStyle: labelStyle,
      hintStyle: GoogleFonts.beVietnamPro(
        fontSize: 13,
        color: const Color(0xFF9AA5B4),
      ),
      filled: true,
      fillColor: const Color(0xFFF8F9FB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        borderSide: BorderSide(color: UpriseColors.primaryDark, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        borderSide: BorderSide(color: UpriseColors.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        borderSide: BorderSide(color: UpriseColors.error, width: 1.5),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status badge
//
// This used to speak a vocabulary the data never uses — published / draft /
// archived — while products actually store available / out_of_stock /
// discontinued, so every badge fell through to the grey default and rendered
// the raw field, underscore and all ("OUT_OF_STOCK"). The labels below are the
// real states, phrased the way they behave in the mobile app: anything not
// archived IS visible to students, which is why 'available' reads as live.
// ─────────────────────────────────────────────────────────────────────────────
String _statusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'available':
      return 'Available';
    case 'out_of_stock':
      return 'Out of Stock';
    case 'discontinued':
      return 'Discontinued';
    default:
      return status.isEmpty
          ? 'Available'
          : status.replaceAll('_', ' ').toUpperCase();
  }
}

_BadgeStyle _statusStyle(String status, {bool isArchived = false}) {
  if (isArchived) {
    return _BadgeStyle(
      const Color(0xFFF3F4F6),
      const Color(0xFF6B7280),
      'ARCHIVED',
      Icons.archive_outlined,
    );
  }
  switch (status.toLowerCase()) {
    case 'out_of_stock':
      return _BadgeStyle(
        const Color(0xFFFEF2F2),
        const Color(0xFFDC2626),
        'OUT OF STOCK',
        Icons.remove_shopping_cart_outlined,
      );
    case 'discontinued':
      return _BadgeStyle(
        const Color(0xFFF3F4F6),
        const Color(0xFF6B7280),
        'DISCONTINUED',
        Icons.do_not_disturb_on_outlined,
      );
    default:
      return _BadgeStyle(
        const Color(0xFFECFDF5),
        const Color(0xFF059669),
        'AVAILABLE',
        Icons.check_circle_outline_rounded,
      );
  }
}

Widget _statusBadge(String status, {bool isArchived = false}) {
  final s = _statusStyle(status, isArchived: isArchived);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: s.bg,
      borderRadius: BorderRadius.circular(_DS.radiusPill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(s.icon, size: 11, color: s.fg),
        const SizedBox(width: 5),
        Text(
          s.label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: s.fg,
            letterSpacing: 0.6,
          ),
        ),
      ],
    ),
  );
}

class _BadgeStyle {
  final Color bg, fg;
  final String label;
  final IconData icon;
  const _BadgeStyle(this.bg, this.fg, this.label, this.icon);
}

const List<String> _merchandiseCategories = [
  'T-Shirts / Uniforms',
  'Lanyards / IDs',
  'Stickers / Pins',
  'Tumblers / Water Bottles',
  'Notebooks / Planners',
  'Others',
];

/// Which slice of the catalog the grid shows. Driven by the stat cards.
enum _Visibility { all, live, hidden }

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────
class OrgMerchandiseScreen extends StatefulWidget {
  final String orgId;
  const OrgMerchandiseScreen({super.key, required this.orgId});

  @override
  State<OrgMerchandiseScreen> createState() => _OrgMerchandiseScreenState();
}

class _OrgMerchandiseScreenState extends State<OrgMerchandiseScreen> {
  // The grid keeps its own loaded list, so a parent setState() alone never
  // showed a product added from the toolbar button — the child State survives
  // the rebuild holding its old list. This key lets the save callback actually
  // re-run the query.
  final GlobalKey<_ProductsTabState> _gridKey = GlobalKey<_ProductsTabState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFE),
      body: _ProductsTab(
        key: _gridKey,
        orgId: widget.orgId,
        onAddProduct: () => _openAddProductModal(context),
        onExport: _exportProducts,
      ),
    );
  }

  Future<void> _exportProducts(String format) async {
    final snap = await FirebaseFirestore.instance
        .collection('products')
        .where('orgId', isEqualTo: widget.orgId)
        .where('isArchived', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .get();
    final docs = snap.docs;
    if (docs.isEmpty) {
      _showSnack('No products to export', UpriseColors.warning);
      return;
    }
    final now = DateFormat('yyyyMMdd').format(DateTime.now());
    // "Sold" used to be a column here, but with no checkout flow it can only
    // ever read 0 — likes are the one real signal the mobile catalog gives
    // back, so the export carries those instead.
    const headers = ['Name', 'Category', 'Price', 'Stock', 'Status', 'Likes'];
    List<String> rowFor(Map<String, dynamic> d) => [
      '${d['name'] ?? ''}',
      '${d['category'] ?? ''}',
      ((d['price'] ?? 0) as num).toDouble().toStringAsFixed(2),
      '${d['stock'] ?? 0}',
      _statusLabel('${d['status'] ?? ''}'),
      '${(d['likedBy'] as List?)?.length ?? 0}',
    ];

    // AdminExportButton's dropdown emits 'excel'/'pdf' (see
    // admin_export_button.dart's _items), not 'csv' — this used to check
    // for 'csv', so "Export as Excel" silently did nothing.
    if (format == 'excel') {
      final buf = StringBuffer();
      buf.writeln(headers.join(','));
      for (final doc in docs) {
        final row = rowFor(doc.data());
        buf.writeln(row.map((c) => '"$c"').join(','));
      }
      await AdminExportUtil.saveText(
        buf.toString(),
        'products_$now.csv',
        mimeType: 'text/csv',
      );
    } else if (format == 'pdf') {
      final pdfBytes = await AdminExportPdf.generateTablePdf(
        title: 'Product Catalog',
        headers: headers,
        rows: docs.map((doc) => rowFor(doc.data())).toList(),
      );
      await AdminExportUtil.saveBytes(
        pdfBytes,
        'products_$now.pdf',
        mimeType: 'application/pdf',
      );
    }
    _showSnack('Exported products', UpriseColors.success);
  }

  void _openAddProductModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProductModal(
        orgId: widget.orgId,
        knownCustomCategories:
            _gridKey.currentState?.customCategories ?? const [],
        onProductSaved: () => _gridKey.currentState?.reload(),
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    if (color == UpriseColors.error) {
      AppToast.error(context, msg);
    } else if (color == UpriseColors.success) {
      AppToast.success(context, msg);
    } else if (color == UpriseColors.warning) {
      AppToast.warning(context, msg);
    } else {
      AppToast.info(context, msg);
    }
  }
}

// ============================================================
// PRODUCTS TAB - Card Grid with Infinite Scroll
// ============================================================
class _ProductsTab extends StatefulWidget {
  final String orgId;
  final VoidCallback onAddProduct;
  final ValueChanged<String> onExport;
  const _ProductsTab({
    super.key,
    required this.orgId,
    required this.onAddProduct,
    required this.onExport,
  });

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _categoryFilter = 'All';
  String _statusFilter = 'All';
  // Visibility (active / archived) is a different question from
  // availability (in stock / discontinued), so it gets its own control. They
  // used to share one dropdown, where picking "Archived" silently threw the
  // availability filter away.
  _Visibility _visibility = _Visibility.live;
  // Set by the "Low / Out of Stock" card: active products at 5 or fewer.
  bool _lowStockOnly = false;
  // No stat card is highlighted until the org actually taps one — the page
  // opens on active products either way, same as Event Proposals.
  bool _statTouched = false;

  final List<String> _statusFilters = const [
    'All',
    'Available',
    'Out of Stock',
    'Discontinued',
  ];

  bool _isLoading = true;
  String? _loadError;
  // Every product this org owns, archived included. A catalog is tens of
  // items, not thousands, so one query up front makes search and the filters
  // honest: they used to run client-side over a 20-doc page, which meant
  // searching returned only what happened to match inside that page and the
  // "N products" counter was counting the page, not the catalog.
  List<ProductModel> _allProducts = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Re-runs the query. Called by the parent (through a GlobalKey) after a
  /// product is added from the header button.
  void reload() => _loadProducts();

  Future<void> _loadProducts() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      // Deliberately no orderBy here: an equality filter plus orderBy needs a
      // composite index, and the catalog is small enough to sort locally.
      final snapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('orgId', isEqualTo: widget.orgId)
          .get();

      final products = snapshot.docs
          .map((d) => ProductModel.fromFirestore(d))
          .toList();
      // Newest first; docs whose serverTimestamp has not resolved yet sort to
      // the top, where a just-created product belongs anyway.
      products.sort((a, b) {
        final at = a.createdAt, bt = b.createdAt;
        if (at == null && bt == null) return 0;
        if (at == null) return -1;
        if (bt == null) return 1;
        return bt.compareTo(at);
      });

      if (!mounted) return;
      setState(() {
        _allProducts = products;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = '$e';
      });
      _showSnack('Error loading products: $e', UpriseColors.error);
    }
  }

  /// Categories actually in use, so the dropdown never offers a filter that
  /// matches nothing — and always includes custom ("Others") categories the
  /// org typed in, which are real categories in the mobile app's filter row.
  List<String> get _categoryFilters {
    final used = _allProducts
        .map((p) => p.category.trim())
        .where((c) => c.isNotEmpty)
        .toSet();
    final ordered = <String>[
      ..._merchandiseCategories.where(used.contains),
      ...used.where((c) => !_merchandiseCategories.contains(c)).toList()
        ..sort(),
    ];
    return ['All', ...ordered];
  }

  List<ProductModel> get _visibleProducts {
    final q = _searchQuery.trim().toLowerCase();
    return _allProducts.where((p) {
      final matchVisibility = switch (_visibility) {
        _Visibility.all => true,
        _Visibility.live => !p.isArchived,
        _Visibility.hidden => p.isArchived,
      };
      final matchStock = !_lowStockOnly || p.totalStock <= 5;
      final matchSearch =
          q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q);
      final matchCat =
          _categoryFilter == 'All' || p.category == _categoryFilter;
      final matchStatus =
          _statusFilter == 'All' ||
          (_statusFilter == 'Available' && p.status == 'available') ||
          (_statusFilter == 'Out of Stock' && p.status == 'out_of_stock') ||
          (_statusFilter == 'Discontinued' && p.status == 'discontinued');
      return matchVisibility &&
          matchStock &&
          matchSearch &&
          matchCat &&
          matchStatus;
    }).toList();
  }

  /// Categories this org typed in itself (anything outside the preset list).
  /// They are real, student-facing filter chips in the mobile app, so the
  /// product form offers them for reuse instead of letting near-duplicates
  /// accumulate.
  List<String> get customCategories {
    final custom = _allProducts
        .map((p) => p.category.trim())
        .where((c) => c.isNotEmpty && !_merchandiseCategories.contains(c))
        .toSet()
        .toList();
    custom.sort();
    return custom;
  }

  bool get _hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      _categoryFilter != 'All' ||
      _statusFilter != 'All';

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _categoryFilter = 'All';
      _statusFilter = 'All';
    });
  }

  Future<void> _archiveProduct(ProductModel product) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        // Was unset — Dialog falls back to Flutter's default Material
        // surface color, which skews purple/lavender on this app's
        // unseeded theme.
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.archive_outlined,
                      color: Color(0xFF6B7280),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Archive product?',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: UpriseColors.charcoal,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '"${product.name}" will be removed from the public catalog. '
                'Its details and likes are kept, and you can restore it '
                'anytime from the Archived tab.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  color: UpriseColors.darkGray,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: UpriseColors.charcoal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: UpriseColors.warning,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    child: Text(
                      'Archive & hide',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('products')
          .doc(product.id)
          .update({
            'isArchived': true,
            'archivedAt': FieldValue.serverTimestamp(),
          });
      await activity_log.ActivityLogger.log(
        action: 'archive_product',
        module: 'merchandise',
        details: {
          'orgId': widget.orgId,
          'productId': product.id,
          'name': product.name,
        },
      );
      if (mounted) {
        _showSnack('Product archived', UpriseColors.success);
        await _loadProducts();
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', UpriseColors.error);
    }
  }

  // Archiving a product previously had no way back short of a manual
  // Firestore edit — the confirm dialog said "hidden from the store" but
  // there was no "Archived" filter to find it again afterward, making the
  // action effectively permanent. Mirrors org_finance.dart's
  // _unarchiveTransaction.
  Future<void> _unarchiveProduct(ProductModel product) async {
    try {
      await FirebaseFirestore.instance
          .collection('products')
          .doc(product.id)
          .update({'isArchived': false, 'archivedAt': FieldValue.delete()});
      await activity_log.ActivityLogger.log(
        action: 'unarchive_product',
        module: 'merchandise',
        details: {
          'orgId': widget.orgId,
          'productId': product.id,
          'name': product.name,
        },
      );
      if (mounted) {
        _showSnack('Product restored', UpriseColors.success);
        await _loadProducts();
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', UpriseColors.error);
    }
  }

  void _showSnack(String msg, Color color) {
    if (color == UpriseColors.error) {
      AppToast.error(context, msg);
    } else if (color == UpriseColors.success) {
      AppToast.success(context, msg);
    } else if (color == UpriseColors.warning) {
      AppToast.warning(context, msg);
    } else {
      AppToast.info(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatsRow(isMobile),
        _buildToolbar(isMobile),
        const SizedBox(height: 16),
        Expanded(child: _buildProductGrid(isMobile)),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Stats row ─────────────────────────────────────────────────────
  // Same shared StatCard as Event Proposals and Certificates; each card is a
  // filter for the grid below.
  Widget _buildStatsRow(bool isMobile) {
    final horizontalPadding = isMobile ? 16.0 : 28.0;
    final cardGap = isMobile ? 8.0 : 14.0;
    final active = _allProducts.where((p) => !p.isArchived).toList();
    final archived = _allProducts.length - active.length;
    final lowStock = active.where((p) => p.totalStock <= 5).length;
    String n(int v) => _isLoading && _allProducts.isEmpty ? '—' : '$v';

    bool isSelected(_Visibility v, {bool lowStock = false}) =>
        _statTouched && _visibility == v && _lowStockOnly == lowStock;

    // Tapping the highlighted card again drops back to the default view
    // (active products, nothing highlighted).
    void select(_Visibility v, {bool lowStock = false}) => setState(() {
      if (isSelected(v, lowStock: lowStock)) {
        _visibility = _Visibility.live;
        _lowStockOnly = false;
        _statTouched = false;
      } else {
        _visibility = v;
        _lowStockOnly = lowStock;
        _statTouched = true;
      }
    });

    final statCards = [
      StatCard(
        label: 'Total Products',
        value: n(_allProducts.length),
        icon: Icons.inventory_2_outlined,
        color: UpriseColors.primaryDark,
        selected: isSelected(_Visibility.all),
        onTap: () => select(_Visibility.all),
      ),
      StatCard(
        label: 'Active',
        value: n(active.length),
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xFF059669),
        selected: isSelected(_Visibility.live),
        onTap: () => select(_Visibility.live),
      ),
      StatCard(
        label: 'Low / Out of Stock',
        value: n(lowStock),
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFFB923C),
        selected: isSelected(_Visibility.live, lowStock: true),
        onTap: () => select(_Visibility.live, lowStock: true),
      ),
      StatCard(
        label: 'Archived',
        value: n(archived),
        icon: Icons.archive_outlined,
        color: const Color(0xFF64748B),
        selected: isSelected(_Visibility.hidden),
        onTap: () => select(_Visibility.hidden),
      ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
      child: isMobile
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(
                  statCards.length,
                  (index) => Padding(
                    padding: EdgeInsets.only(
                      right: index < statCards.length - 1 ? cardGap : 0,
                    ),
                    child: SizedBox(width: 220, child: statCards[index]),
                  ),
                ),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(statCards.length * 2 - 1, (index) {
                if (index.isOdd) return SizedBox(width: cardGap);
                return Expanded(child: statCards[index ~/ 2]);
              }),
            ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search name, category or description…',
          hintStyle: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: const Color(0xFF9AA5B4),
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: Color(0xFF9AA5B4),
          ),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Color(0xFF9AA5B4),
                  ),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _DS.borderSoft),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _DS.borderSoft),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: UpriseColors.primaryDark, width: 1.5),
          ),
        ),
      ),
    );
  }

  // ── Toolbar ───────────────────────────────────────────────────────
  // One row like the other org pages: search, filters, then page actions.
  Widget _buildToolbar(bool isMobile) {
    final horizontalPadding = isMobile ? 16.0 : 28.0;
    const gap = 12.0;

    final categoryFilters = _categoryFilters;
    final categoryFilter = _FilterDropdown(
      value: categoryFilters.contains(_categoryFilter)
          ? _categoryFilter
          : 'All',
      items: categoryFilters,
      hint: 'Category',
      icon: Icons.category_outlined,
      onChanged: (v) => setState(() => _categoryFilter = v ?? 'All'),
    );
    final availabilityFilter = _FilterDropdown(
      value: _statusFilter,
      items: _statusFilters,
      hint: 'Availability',
      icon: Icons.tune_rounded,
      onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
    );

    // The catalog is fetched once rather than streamed, so there is an
    // explicit way to pull in changes another officer made.
    final refreshButton = Tooltip(
      message: 'Refresh',
      child: SizedBox(
        width: 40,
        height: 40,
        child: OutlinedButton(
          onPressed: _isLoading ? null : _loadProducts,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(40, 40),
            foregroundColor: const Color(0xFF64748B),
            backgroundColor: Colors.white,
            side: const BorderSide(color: _DS.borderSoft),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Icon(Icons.refresh_rounded, size: 18),
        ),
      ),
    );

    final exportButton = AdminExportButton(
      label: 'Export',
      onSelected: widget.onExport,
    );

    final addButton = SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: widget.onAddProduct,
        icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
        label: Text(
          'Add Product',
          style: GoogleFonts.beVietnamPro(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: UpriseColors.primaryDark,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
      ),
    );

    final shown = _visibleProducts.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        isMobile ? 16 : 20,
        horizontalPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMobile) ...[
            _buildSearchField(),
            const SizedBox(height: gap),
            Row(
              children: [
                Expanded(child: categoryFilter),
                const SizedBox(width: gap),
                Expanded(child: availabilityFilter),
              ],
            ),
            const SizedBox(height: gap),
            Row(
              children: [
                refreshButton,
                const SizedBox(width: gap),
                Expanded(child: exportButton),
                const SizedBox(width: gap),
                Expanded(child: addButton),
              ],
            ),
          ] else
            Row(
              children: [
                Expanded(child: _buildSearchField()),
                const SizedBox(width: gap),
                categoryFilter,
                const SizedBox(width: gap),
                availabilityFilter,
                const SizedBox(width: gap),
                refreshButton,
                const SizedBox(width: gap),
                exportButton,
                const SizedBox(width: gap),
                addButton,
              ],
            ),
          if (_hasActiveFilters) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '$shown result${shown == 1 ? '' : 's'}',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12.5,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 15),
                  label: Text(
                    'Clear filters',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: UpriseColors.primaryDark,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductGrid(bool isMobile) {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: UpriseColors.primaryDark,
          ),
        ),
      );
    }

    if (_loadError != null && _allProducts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load your products',
        subtitle: 'Check your connection and try again.',
        action: OutlinedButton.icon(
          onPressed: _loadProducts,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text(
            'Retry',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: UpriseColors.primaryDark,
            side: const BorderSide(color: UpriseColors.primaryDark),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      );
    }

    final products = _visibleProducts;

    if (products.isEmpty) {
      // Three genuinely different situations that used to share one message.
      if (_hasActiveFilters) {
        return _buildEmptyState(
          icon: Icons.search_off_rounded,
          title: 'No products match',
          subtitle: 'Try a different search term or clear the filters.',
          action: TextButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: Text(
              'Clear filters',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: UpriseColors.primaryDark,
            ),
          ),
        );
      }
      if (_lowStockOnly) {
        return _buildEmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'All products are well stocked',
          subtitle: 'No active product is at 5 items or fewer.',
        );
      }
      if (_visibility == _Visibility.hidden) {
        return _buildEmptyState(
          icon: Icons.archive_outlined,
          title: 'No archived products',
          subtitle: 'Products you archive will appear here.',
        );
      }
      return _buildEmptyState(
        icon: Icons.storefront_outlined,
        title: 'No products yet',
        subtitle: 'Add your first product to start building your catalog.',
        action: ElevatedButton.icon(
          onPressed: widget.onAddProduct,
          icon: const Icon(Icons.add, size: 18, color: Colors.white),
          label: Text(
            'Add Your First Product',
            style: GoogleFonts.beVietnamPro(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: UpriseColors.primaryDark,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 0,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProducts,
      color: UpriseColors.primaryDark,
      child: GridView.builder(
        // A few px top/bottom so the cards' resting shadow isn't clipped.
        padding: EdgeInsets.fromLTRB(
          isMobile ? 16 : 28,
          4,
          isMobile ? 16 : 28,
          12,
        ),
        // MaxCrossAxisExtent sizes each card to a comfortable target width and
        // lets the column count adapt to what is actually there, like a real
        // product catalog rather than a sparse admin table.
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: isMobile ? 480 : 288,
          crossAxisSpacing: 20,
          mainAxisSpacing: 24,
          // Photo is now edge-to-edge (square) with the details padded
          // underneath, so the card needs a little more height than width.
          childAspectRatio: 0.66,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return _ProductCard(
            product: product,
            alwaysShowActions: isMobile,
            onTap: () => showDialog(
              context: context,
              builder: (_) => _ProductDetailsModal(product: product),
            ),
            onArchive: () => product.isArchived
                ? _unarchiveProduct(product)
                : _archiveProduct(product),
            onEdit: () => showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => _ProductModal(
                orgId: widget.orgId,
                existingProduct: product,
                knownCustomCategories: customCategories,
                onProductSaved: _loadProducts,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: UpriseColors.primaryDark.withAlpha(18),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(
                      icon,
                      size: 40,
                      color: UpriseColors.primaryDark.withAlpha(160),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        height: 1.5,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  if (action != null) ...[const SizedBox(height: 20), action],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PRODUCT CARD WIDGET (with Base64 image support)
// ============================================================
class _ProductCard extends StatefulWidget {
  final ProductModel product;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback onEdit;
  // Hover has no equivalent on a touch device, so the reveal-on-hover admin
  // icons would otherwise be permanently unreachable there — narrow/mobile
  // layouts keep them always visible instead of gating on hover.
  final bool alwaysShowActions;

  const _ProductCard({
    required this.product,
    required this.onTap,
    required this.onArchive,
    required this.onEdit,
    this.alwaysShowActions = false,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

// Restyled from an admin-table-style tile (bordered card, small square
// image, always-visible edit/archive icons) into a storefront-style
// listing — bigger square product photo as the hero, plain typography on
// the page background instead of card chrome, and admin controls that only
// reveal on hover instead of permanently cluttering the photo. Same data
// and callbacks as before, purely a presentation change.
class _ProductCardState extends State<_ProductCard> {
  bool _hovering = false;
  // Decoded once and reused — decoding fresh inside build() meant every
  // hover-triggered setState() re-ran base64Decode and handed Image.memory
  // a brand-new Uint8List each time. Flutter's image cache keys off that
  // object's identity, not its bytes, so each hover looked like "a whole
  // new image" and forced a full re-decode — that was the hover glitch.
  Uint8List? _decodedImage;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  @override
  void didUpdateWidget(covariant _ProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.imageBase64 != widget.product.imageBase64 ||
        !identical(
          oldWidget.product.rotationPhotos,
          widget.product.rotationPhotos,
        )) {
      _decodeImage();
    }
  }

  void _decodeImage() {
    // Was reading product.imageBase64 (the single "main photo" field)
    // directly — but a product whose org only ever used the "Add Photos"
    // rotation-gallery picker and never set a separate main image has that
    // field empty while rotationPhotos holds the real data. displayPhotos
    // (rotationPhotos first, imageBase64 as fallback) is the same accessor
    // the mobile catalog's gallery always renders through, which is why
    // those products showed up fine there but not here.
    final photos = widget.product.displayPhotos;
    final b64 = photos.isNotEmpty ? photos.first : null;
    if (b64 != null && b64.isNotEmpty) {
      try {
        // Some products were saved with a `data:image/...;base64,` prefix,
        // others with plain base64 — base64Decode() on the prefixed form
        // throws (invalid characters in "data:image/jpeg;base64"), which
        // this silently swallowed and fell back to "No photo" even though
        // the image data was there. Stripping a comma-delimited prefix
        // when present handles both, matching the pattern already used
        // elsewhere in this file (see the raw.split(',').last usage below).
        final raw = b64.contains(',') ? b64.split(',').last : b64;
        _decodedImage = base64Decode(raw);
        return;
      } catch (_) {}
    }
    _decodedImage = null;
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final totalStock = product.totalStock;
    final isArchived = product.isArchived;
    final isOutOfStock = totalStock <= 0;
    final isLowStock = totalStock > 0 && totalStock <= 5;
    final isDiscontinued = product.status == 'discontinued';
    // Only states that need the org to do something get a strip under the
    // price. "Live and in stock" is the normal case and says nothing.
    final (String, IconData, Color)? alert = isArchived
        ? null
        : isOutOfStock
        ? (
            'Out of stock',
            Icons.remove_shopping_cart_outlined,
            UpriseColors.error,
          )
        : isDiscontinued
        ? (
            'Marked unavailable',
            Icons.do_not_disturb_on_outlined,
            UpriseColors.darkGray,
          )
        : isLowStock
        ? (
            'Only $totalStock left',
            Icons.warning_amber_rounded,
            UpriseColors.warning,
          )
        : null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        // Same card chrome as the other org pages (Event Proposals' table,
        // the modal section cards): white, soft border, resting shadow.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_DS.radiusMd),
            border: Border.all(
              color: _hovering
                  ? UpriseColors.primaryDark.withAlpha(90)
                  : _DS.cardBorder,
            ),
            boxShadow: _hovering ? _DS.cardShadowHover : _DS.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Archived products are dimmed rather than badged only,
                      // so a hidden item never reads as part of the live
                      // catalog at a glance.
                      Opacity(
                        opacity: isArchived ? 0.45 : 1,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 200),
                          scale: _hovering ? 1.04 : 1.0,
                          child: _buildProductImage(),
                        ),
                      ),
                      if (isArchived)
                        Positioned(
                          left: 10,
                          top: 10,
                          child: _statusBadge(product.status, isArchived: true),
                        ),
                      // Likes are the only engagement signal the mobile
                      // catalog produces, so they sit on the photo the way a
                      // storefront shows its wishlist count.
                      if (!isArchived && product.likeCount > 0)
                        Positioned(
                          left: 10,
                          top: 10,
                          child: _LikePill(count: product.likeCount),
                        ),
                      // Quick actions stay invisible until hover instead of
                      // being permanent chrome over the product photo.
                      Positioned(
                        right: 10,
                        top: 10,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: (_hovering || widget.alwaysShowActions)
                              ? 1
                              : 0,
                          child: IgnorePointer(
                            ignoring: !(_hovering || widget.alwaysShowActions),
                            child: Column(
                              children: [
                                _CardActionButton(
                                  icon: Icons.edit_outlined,
                                  tooltip: 'Edit',
                                  onTap: widget.onEdit,
                                ),
                                const SizedBox(height: 6),
                                _CardActionButton(
                                  icon: isArchived
                                      ? Icons.unarchive_outlined
                                      : Icons.archive_outlined,
                                  tooltip: isArchived ? 'Restore' : 'Archive',
                                  onTap: widget.onArchive,
                                  color: isArchived
                                      ? UpriseColors.success
                                      : UpriseColors.warning,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.category.isEmpty
                            ? 'Uncategorized'
                            : product.category,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: UpriseColors.darkGray,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        product.name,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A202C),
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          // Was NumberFormat('#,###'), which rounded — a ₱149.50
                          // product read as ₱150 here while the mobile app showed
                          // ₱149.5. Same format as the student and guest catalogs.
                          Text(
                            '₱${NumberFormat('#,##0.##').format(product.price)}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1A202C),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              product.variants.isNotEmpty
                                  ? '$totalStock in ${product.variants.length} variant${product.variants.length == 1 ? '' : 's'}'
                                  : '$totalStock in stock',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                color: const Color(0xFF94A3B8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 16,
                        child: isArchived
                            ? Row(
                                children: [
                                  const Icon(
                                    Icons.archive_outlined,
                                    size: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Archived',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              )
                            : alert == null
                            ? const SizedBox.shrink()
                            : Row(
                                children: [
                                  Icon(alert.$2, size: 12, color: alert.$3),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      alert.$1,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: alert.$3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductImage() {
    final bytes = _decodedImage;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        // Decodes at a card-sized resolution instead of whatever the org
        // originally uploaded — full camera-resolution photos decoded
        // for every card in a grid is what was making the list laggy.
        cacheWidth: 400,
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFFF8F9FB),
          child: const Icon(
            Icons.shopping_bag_outlined,
            size: 40,
            color: Color(0xFF9AA5B4),
          ),
        ),
      );
    }
    return _buildNetworkImage();
  }

  Widget _buildNetworkImage() {
    final product = widget.product;
    if (product.imageUrl.isNotEmpty) {
      return Image.network(
        product.imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: const Color(0xFFF8F9FB),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => const _NoPhotoPlaceholder(),
      );
    }
    return const _NoPhotoPlaceholder();
  }
}

// A flat gray box + generic bag icon read as "broken image" rather than
// "no photo yet" — this gives an empty product a deliberate, on-brand look
// instead of looking like something failed to load.
/// How many students and guests have hearted this product in the mobile app.
/// The card used to show "N sold" here, a number that can no longer move now
/// that there is no checkout — this is the one signal the catalog really
/// produces.
class _LikePill extends StatelessWidget {
  final int count;
  const _LikePill({required this.count});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$count like${count == 1 ? '' : 's'}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(235),
          borderRadius: BorderRadius.circular(_DS.radiusPill),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.favorite_rounded,
              size: 11,
              color: UpriseColors.primaryDark,
            ),
            const SizedBox(width: 5),
            Text(
              NumberFormat.compact().format(count),
              style: GoogleFonts.beVietnamPro(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A202C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPhotoPlaceholder extends StatelessWidget {
  const _NoPhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFF8F9FB)),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 30,
            color: UpriseColors.darkGray.withAlpha(150),
          ),
          const SizedBox(height: 6),
          Text(
            'No photo',
            style: GoogleFonts.beVietnamPro(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: UpriseColors.darkGray.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CARD ACTION BUTTON
// ============================================================
class _CardActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _CardActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(140),
        borderRadius: BorderRadius.circular(6),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 14, color: Colors.white),
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        tooltip: tooltip,
      ),
    );
  }
}

// Product photos are stored as base64 directly on the Firestore document
// (see _submit() below) rather than uploaded to Storage, so the whole doc
// has to stay under Firestore's hard 1 MiB-per-document limit — base64
// itself already inflates raw bytes by ~33%, and a raw phone photo can
// easily be several MB, which is exactly what was blowing past the limit
// and throwing a raw `invalid-argument` error at save time. Compressing
// every picked image down to a bounded size before it's ever base64-encoded
// keeps a single photo comfortably under ~300KB while still looking sharp
// at product-card/detail sizes.
Future<Uint8List> _compressImageForStorage(
  Uint8List bytes, {
  int maxDimension = 1280,
  int quality = 72,
}) async {
  try {
    final compressed = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxDimension,
      minHeight: maxDimension,
      quality: quality,
      format: CompressFormat.jpeg,
    );
    // Guard against the rare case where compression makes things worse
    // (already-tiny/simple images can sometimes grow slightly under JPEG
    // re-encoding) — never return something larger than what came in.
    return compressed.length < bytes.length ? compressed : bytes;
  } catch (_) {
    // If compression itself fails for any reason, fall back to the
    // original bytes rather than blocking the whole picker action — the
    // pre-submit size guard in _submit() still catches an oversized result.
    return bytes;
  }
}

// ============================================================
// PRODUCT MODAL (with Base64 image support & auto-refresh)
// ============================================================
class _ProductModal extends StatefulWidget {
  final String orgId;
  final ProductModel? existingProduct;
  final VoidCallback? onProductSaved;
  // Custom ("Others") categories this org has already used, offered back as
  // chips so near-duplicates do not pile up in the mobile app's filter row.
  final List<String> knownCustomCategories;

  const _ProductModal({
    required this.orgId,
    this.existingProduct,
    this.onProductSaved,
    this.knownCustomCategories = const [],
  });

  @override
  State<_ProductModal> createState() => _ProductModalState();
}

class _ProductModalState extends State<_ProductModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _customCategoryCtrl = TextEditingController();
  String _category = _merchandiseCategories.first;
  bool _isDiscontinued = false;
  List<ProductVariant> _variants = [];
  Uint8List? _imageBytes;
  String? _pickedImageName;
  bool _uploadingImage = false;
  bool _submitting = false;
  String? _uploadError;
  // Angle photos for the 360 drag-to-rotate viewer — kept as raw bytes
  // while editing, re-encoded to base64 only on submit.
  final List<Uint8List> _rotationPhotoBytes = [];

  bool get _isEdit => widget.existingProduct != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final p = widget.existingProduct!;
      _nameCtrl.text = p.name;
      _descCtrl.text = p.description;
      _priceCtrl.text = p.price.toStringAsFixed(2);
      _stockCtrl.text = p.stock.toString();
      if (_merchandiseCategories.contains(p.category)) {
        _category = p.category;
      } else {
        _category = 'Others';
        _customCategoryCtrl.text = p.category;
      }
      _isDiscontinued = p.status == 'discontinued';
      _variants = List.from(p.variants);

      // ── LOAD EXISTING BASE64 IMAGE ──
      // Strips a `data:image/...;base64,` prefix when present — same fix
      // as _ProductCard._decodeImage() below, otherwise editing a product
      // whose image was saved with that prefix showed the upload dropzone
      // as if no image existed at all.
      if (p.imageBase64 != null && p.imageBase64!.isNotEmpty) {
        try {
          final raw = p.imageBase64!.contains(',')
              ? p.imageBase64!.split(',').last
              : p.imageBase64!;
          _imageBytes = base64Decode(raw);
        } catch (_) {
          _imageBytes = null;
        }
      }

      // ── LOAD EXISTING ROTATION PHOTOS ──
      for (final photo in p.rotationPhotos) {
        try {
          final raw = photo.contains(',') ? photo.split(',').last : photo;
          _rotationPhotoBytes.add(base64Decode(raw));
        } catch (_) {}
      }
    }
  }

  Future<void> _pickRotationPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (mounted) setState(() => _uploadingImage = true);
    final compressed = <Uint8List>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      // Rotation sets can have many frames, so each one is compressed a
      // bit harder than the main photo to keep the whole product document
      // well under Firestore's 1 MiB limit.
      compressed.add(
        await _compressImageForStorage(bytes, maxDimension: 900, quality: 60),
      );
    }
    if (mounted) {
      setState(() {
        _rotationPhotoBytes.addAll(compressed);
        _uploadingImage = false;
      });
    }
  }

  void _removeRotationPhoto(int index) {
    setState(() => _rotationPhotoBytes.removeAt(index));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _customCategoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    final price = double.tryParse(_priceCtrl.text.trim()) ?? -1;

    final hasVariants = _variants.isNotEmpty;
    final stock = hasVariants
        ? _variants.fold<int>(0, (sum, v) => sum + v.stock)
        : int.tryParse(_stockCtrl.text.trim()) ?? 0;

    final effectiveCategory = _category == 'Others'
        ? _customCategoryCtrl.text.trim()
        : _category;

    final computedStatus = (_isEdit && _isDiscontinued)
        ? 'discontinued'
        : (stock == 0 ? 'out_of_stock' : 'available');

    setState(() {
      _submitting = true;
      _uploadError = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;

      final data = <String, dynamic>{
        'orgId': widget.orgId,
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'category': effectiveCategory,
        'price': price,
        'stock': stock,
        'status': computedStatus,
        'variants': _variants.map((v) => v.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final productRef = _isEdit
          ? FirebaseFirestore.instance
                .collection('products')
                .doc(widget.existingProduct!.id)
          : FirebaseFirestore.instance.collection('products').doc();
      final productId = productRef.id;

      // ── SAVE IMAGE AS BASE64 (with existing image preservation) ──
      if (_imageBytes != null) {
        try {
          if (mounted) setState(() => _uploadingImage = true);
          final base64Image = base64Encode(_imageBytes!);
          data['imageBase64'] = base64Image;
          data['imageFormat'] = _pickedImageName?.split('.').last ?? 'jpg';
          if (mounted) setState(() => _uploadingImage = false);
        } catch (e) {
          if (mounted) {
            setState(() {
              _uploadingImage = false;
              _uploadError = 'Image encoding failed: $e';
            });
          }
          data['imageBase64'] = '';
        }
      } else if (_isEdit && widget.existingProduct?.imageBase64 != null) {
        // Keep existing image if no new image uploaded
        data['imageBase64'] = widget.existingProduct!.imageBase64;
        data['imageFormat'] = widget.existingProduct!.imageFormat ?? 'jpg';
      } else {
        data['imageBase64'] = '';
      }

      // ── SAVE ROTATION PHOTOS AS BASE64 ──
      data['rotationPhotos'] = _rotationPhotoBytes
          .map((bytes) => base64Encode(bytes))
          .toList();

      // ── GUARD AGAINST EXCEEDING FIRESTORE'S 1 MiB DOCUMENT LIMIT ──
      // Catch this client-side with a clear, actionable message instead of
      // letting the whole save fail with a raw `invalid-argument` Firestore
      // error — this is what was happening before compression was added
      // above; this guard stays as a safety net for products with a photo
      // plus several rotation frames that could still add up.
      final imageBytesTotal =
          ((data['imageBase64'] as String?)?.length ?? 0) +
          (data['rotationPhotos'] as List).fold<int>(
            0,
            (sum, p) => sum + (p as String).length,
          );
      const maxDocBytes = 1048576; // Firestore's hard per-document limit
      const safetyBudget = 900000; // leaves headroom for the doc's other fields
      if (imageBytesTotal > safetyBudget) {
        if (mounted) {
          setState(() {
            _submitting = false;
            _uploadError =
                'These photos are too large to save (${(imageBytesTotal / 1024).round()} KB of a '
                '${(maxDocBytes / 1024).round()} KB limit) — remove a rotation photo or pick a smaller main image.';
          });
        }
        return;
      }

      // ── SAVE PRODUCT ──
      if (_isEdit) {
        await productRef.update(data);
      } else {
        data['sold'] = 0;
        data['isArchived'] = false;
        data['createdAt'] = FieldValue.serverTimestamp();
        data['createdBy'] = user?.uid ?? '';
        await productRef.set(data);
      }

      // ── Log writes ──────────────────────────────────────────────
      try {
        await activity_log.ActivityLogger.log(
          action: _isEdit ? 'edit_product' : 'create_product',
          module: 'merchandise',
          details: _isEdit
              ? {'orgId': widget.orgId, 'productId': productId}
              : {'orgId': widget.orgId, 'name': data['name']},
        );
      } catch (_) {}

      // ── CALLBACK PARA MAG-REFRESH ──
      if (mounted) {
        widget.onProductSaved?.call();
        Navigator.pop(context);
        AppToast.success(
          context,
          _isEdit
              ? 'Product updated successfully!'
              : 'Product added successfully!',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _uploadingImage = false;
        });
        _showError('Error saving product: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _uploadingImage = false;
        });
      }
    }
  }

  void _showError(String msg) {
    AppToast.error(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    // Same shell as Submit Event Proposal: orange compact header, white
    // body, footer action bar.
    return OrgModalShell(
      accentColor: UpriseColors.primaryDark,
      headerColor: UpriseColors.primaryDark,
      compactHeader: true,
      icon: _isEdit ? Icons.edit_rounded : Icons.shopping_bag_outlined,
      title: _isEdit ? 'Edit Product' : 'Add Product',
      subtitle: _isEdit ? null : 'List a new item in your merch catalog.',
      // Says up front whether the product being edited is actually in the
      // students' catalog right now.
      subtitleWidget: _isEdit && widget.existingProduct != null
          ? Align(
              alignment: Alignment.centerLeft,
              child: _statusBadge(
                widget.existingProduct!.status,
                isArchived: widget.existingProduct!.isArchived,
              ),
            )
          : null,
      width: 640,
      maxHeightFraction: 0.88,
      closeEnabled: !_submitting,
      footerActions: [
        OutlinedButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFE2E6EA)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          ),
          child: Text(
            'Cancel',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF374151),
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: (_submitting || _uploadingImage) ? null : _submit,
          icon: (_submitting || _uploadingImage)
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_rounded, size: 16),
          label: Text(
            _uploadingImage
                ? 'Encoding Image...'
                : (_isEdit ? 'Save Changes' : 'Add Product'),
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: UpriseColors.primaryDark,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          ),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Core identifying info first (name, category, price,
              // stock) — these used to sit below the image + 360°
              // photo uploaders, which pushed every essential field
              // out of view on anything but a tall screen, forcing a
              // long scroll before reaching Category or Price. Photos
              // are the more optional part of listing a product, so
              // they move to the end instead.
              _sectionLabel(
                'Product Information',
                icon: Icons.info_outline_rounded,
                hint: 'Basic details shown on the product listing.',
              ),
              // Name and Category share a row like Event Title / Category
              // in Submit Event Proposal; they stack on narrow screens.
              LayoutBuilder(
                builder: (context, constraints) {
                  final nameField = TextFormField(
                    controller: _nameCtrl,
                    decoration: _DS.inputDecoration(
                      'Product Name',
                      hint: 'e.g., Premium Shirt 2026',
                      icon: Icons.label_outline_rounded,
                      required: true,
                    ),
                    style: GoogleFonts.beVietnamPro(fontSize: 13),
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Required' : null,
                  );
                  final categoryField = DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: _DS.inputDecoration('Category', required: true),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Color(0xFF9AA5B4),
                    ),
                    dropdownColor: Colors.white,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: const Color(0xFF1A202C),
                    ),
                    items: _merchandiseCategories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _category = value);
                    },
                  );
                  if (constraints.maxWidth < 480) {
                    return Column(
                      children: [
                        nameField,
                        const SizedBox(height: 12),
                        categoryField,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: nameField),
                      const SizedBox(width: 12),
                      Expanded(child: categoryField),
                    ],
                  );
                },
              ),
              if (_category == 'Others') ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _customCategoryCtrl,
                  decoration: _DS.inputDecoration(
                    'Custom Category',
                    hint: 'Type category name…',
                    icon: Icons.edit_outlined,
                    required: true,
                  ),
                  style: GoogleFonts.beVietnamPro(fontSize: 13),
                  onChanged: (_) => setState(() {}),
                  validator: (v) =>
                      v?.trim().isEmpty ?? true ? 'Required' : null,
                ),
                // Whatever is typed here becomes a filter chip in the
                // student and guest catalogs, so "Tshirts" and
                // "T-shirts" would sit there as two separate
                // categories forever. Offering the org's existing ones
                // makes reuse the easy path.
                if (widget.knownCustomCategories.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Already used by this org — tap to reuse:',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: widget.knownCustomCategories.map((c) {
                      final selected =
                          _customCategoryCtrl.text.trim().toLowerCase() ==
                          c.toLowerCase();
                      return InkWell(
                        onTap: () => setState(() {
                          _customCategoryCtrl.text = c;
                        }),
                        borderRadius: BorderRadius.circular(_DS.radiusPill),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? UpriseColors.primaryDark.withAlpha(22)
                                : const Color(0xFFF1F4F8),
                            borderRadius: BorderRadius.circular(_DS.radiusPill),
                            border: Border.all(
                              color: selected
                                  ? UpriseColors.primaryDark.withAlpha(90)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            c,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 11.5,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected
                                  ? UpriseColors.primaryDark
                                  : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: _DS
                    .inputDecoration(
                      'Description',
                      hint: 'Product details...',
                      icon: Icons.description_outlined,
                    )
                    .copyWith(alignLabelWithHint: true),
                style: GoogleFonts.beVietnamPro(fontSize: 13),
              ),
              const SizedBox(height: 16),
              _sectionLabel(
                'Pricing',
                icon: Icons.payments_outlined,
                hint: 'The price shown on the product listing.',
              ),
              TextFormField(
                controller: _priceCtrl,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: _DS.inputDecoration(
                  'Price',
                  hint: '0.00',
                  icon: Icons.payments_outlined,
                  required: true,
                ),
                style: GoogleFonts.beVietnamPro(fontSize: 13),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final price = double.tryParse(v?.trim() ?? '');
                  if (price == null || price <= 0) {
                    return 'Enter a valid price';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _sectionLabel(
                'Inventory',
                icon: Icons.inventory_2_outlined,
                hint: 'Shown as "Out of stock" once this reaches zero.',
              ),
              // Adding a variant used to make this field vanish and
              // throw away whatever was typed in it, with nothing to
              // say where the number had gone. The field is still
              // replaced — variant stocks are the source of truth —
              // but now it says so and shows the running total.
              if (_variants.isEmpty)
                TextFormField(
                  controller: _stockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _DS.inputDecoration(
                    'Stock Quantity',
                    hint: '0',
                    icon: Icons.inventory_2_outlined,
                    required: true,
                  ),
                  style: GoogleFonts.beVietnamPro(fontSize: 13),
                  validator: (v) {
                    final stock = int.tryParse(v?.trim() ?? '');
                    if (stock == null || stock < 0) {
                      return 'Enter a valid quantity';
                    }
                    return null;
                  },
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FB),
                    borderRadius: BorderRadius.circular(_DS.radiusSm),
                    border: Border.all(color: _DS.borderSoft),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.functions_rounded,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Stock is added up from your variants',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12.5,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ),
                      Text(
                        '${_variants.fold<int>(0, (sum, v) => sum + v.stock)} total',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A202C),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isEdit) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: _submitting
                      ? null
                      : () =>
                            setState(() => _isDiscontinued = !_isDiscontinued),
                  borderRadius: BorderRadius.circular(_DS.radiusSm),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isDiscontinued
                          ? const Color(0xFFF3F4F6)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(_DS.radiusSm),
                      border: Border.all(
                        color: _isDiscontinued
                            ? const Color(0xFFD1D5DB)
                            : _DS.borderSoft,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: _isDiscontinued,
                            activeColor: const Color(0xFF6B7280),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onChanged: _submitting
                                ? null
                                : (v) => setState(
                                    () => _isDiscontinued = v ?? false,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mark as discontinued',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF374151),
                                ),
                              ),
                              const SizedBox(height: 2),
                              // Says what actually happens: mobile
                              // keeps showing discontinued products,
                              // just greyed out and marked. Only
                              // archiving removes them.
                              Text(
                                'Stays listed but is marked unavailable. '
                                'To remove it from the catalog entirely, '
                                'archive it instead.',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11.5,
                                  height: 1.45,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _sectionLabel(
                'Variants',
                icon: Icons.tune_rounded,
                hint:
                    'Sizes or colors available for this product. '
                    'Each one carries its own stock.',
              ),
              ..._variants.map((v) => _buildVariantChip(v)),
              if (_variants.isNotEmpty) const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _openAddVariantDialog,
                icon: const Icon(Icons.add, size: 14),
                label: Text(
                  'Add Variant',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: UpriseColors.primaryDark,
                  side: BorderSide(color: UpriseColors.primaryDark),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _sectionLabel(
                'Main Photo',
                icon: Icons.image_outlined,
                hint:
                    'The cover image for the listing. '
                    'Square photos crop best.',
              ),
              _buildImagePicker(),
              const SizedBox(height: 16),
              _sectionLabel(
                'More Photos (optional)',
                icon: Icons.collections_outlined,
                hint:
                    'Extra angles shown as a swipeable gallery on the '
                    'product page.',
              ),
              _buildRotationPhotosPicker(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    // Check if there's an existing base64 image
    final existingBase64 = widget.existingProduct?.imageBase64 ?? '';
    final hasImage = _imageBytes != null || existingBase64.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildImagePickerBox(hasImage, existingBase64),
        const SizedBox(height: 6),
        Text(
          'JPG or PNG, square recommended, up to 10 MB — auto-compressed on upload.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 11,
            color: const Color(0xFF9AA5B4),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePickerBox(bool hasImage, String existingBase64) {
    return MouseRegion(
      cursor: (_submitting || _uploadingImage)
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: (_submitting || _uploadingImage) ? null : _pickImage,
        child: Container(
          height: hasImage ? 140 : 150,
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasImage
                  ? UpriseColors.primaryDark.withAlpha(77)
                  : const Color(0xFFE2E6EA),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: hasImage
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_imageBytes != null)
                        Image.memory(
                          _imageBytes!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 140,
                          cacheHeight: 280,
                          errorBuilder: (_, __, ___) => const SizedBox(),
                        )
                      else
                        Image.memory(
                          base64Decode(
                            existingBase64.contains(',')
                                ? existingBase64.split(',').last
                                : existingBase64,
                          ),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 140,
                          cacheHeight: 280,
                          errorBuilder: (_, __, ___) => const SizedBox(),
                        ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: _uploadPill(label: 'Change'),
                      ),
                      if (_uploadError != null)
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: _uploadErrorBadge(),
                        ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 32,
                        color: Color(0xFF9AA5B4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Upload Product Image',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: const Color(0xFF9AA5B4),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _uploadPill(label: 'Upload'),
                      if (_uploadError != null) ...[
                        const SizedBox(height: 10),
                        _uploadErrorBadge(),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // Was a bare 64x64 "+" square buried after two lines of small gray text —
  // easy to miss entirely, which is why this read as "not working" rather
  // than "not yet used." Now a bordered card with a full-width branded CTA
  // button that's impossible to scroll past without noticing.
  Widget _buildRotationPhotosPicker() {
    final count = _rotationPhotoBytes.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E6EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add photos of different angles — front, side, back, sole, '
            'etc. — shown as a swipeable gallery on the product page. '
            'JPG or PNG, up to 10 MB each '
            '— auto-compressed on upload.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 11.5,
              color: const Color(0xFF6B7280),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          MouseRegion(
            cursor: (_submitting || _uploadingImage)
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: (_submitting || _uploadingImage)
                  ? null
                  : _pickRotationPhotos,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: UpriseColors.primaryDark,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      count == 0 ? 'Add Photos' : 'Add More Photos',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (count > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  '$count photo${count == 1 ? '' : 's'}',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF374151),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _rotationPhotoBytes.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _rotationPhotoBytes[i],
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox(width: 72, height: 72),
                        ),
                      ),
                      // Order matters for the gallery swipe order —
                      // numbering makes that visible instead of an
                      // unordered pile.
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: Tooltip(
                          message: 'Remove Photo',
                          waitDuration: const Duration(milliseconds: 400),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () => _removeRotationPhoto(i),
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: Colors.black87,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _uploadPill({required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: UpriseColors.primaryDark,
        borderRadius: BorderRadius.circular(6),
      ),
      child: _uploadingImage
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.upload_rounded, size: 13, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _uploadErrorBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 12, color: Color(0xFFDC2626)),
          const SizedBox(width: 4),
          Text(
            'Upload failed',
            style: GoogleFonts.beVietnamPro(
              fontSize: 10,
              color: const Color(0xFF991B1B),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    if (mounted) setState(() => _uploadingImage = true);
    final compressed = await _compressImageForStorage(bytes);
    if (mounted) {
      setState(() {
        _imageBytes = compressed;
        _pickedImageName = file.name;
        _uploadError = null;
        _uploadingImage = false;
      });
    }
  }

  void _openAddVariantDialog() async {
    final variant = await showDialog<ProductVariant>(
      context: context,
      builder: (_) => const _VariantDialog(),
    );
    if (variant != null) {
      setState(() => _variants.add(variant));
    }
  }

  Widget _buildVariantChip(ProductVariant v) {
    final label = [
      if (v.size.isNotEmpty) v.size,
      if (v.color.isNotEmpty) v.color,
    ].join(' / ');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E6EA)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: UpriseColors.primaryDark.withAlpha(18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.tune_rounded,
              size: 14,
              color: UpriseColors.primaryDark,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label.isEmpty ? 'Variant' : label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A202C),
              ),
            ),
          ),
          Text(
            'Stock: ${v.stock}',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          if (v.priceOffset != null) ...[
            const SizedBox(width: 10),
            Text(
              '${v.priceOffset! >= 0 ? '+' : ''}₱${NumberFormat('#,###.##').format(v.priceOffset)}',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: UpriseColors.primaryDark,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Tooltip(
            message: 'Remove Variant',
            waitDuration: const Duration(milliseconds: 400),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () =>
                    setState(() => _variants.removeWhere((x) => x.id == v.id)),
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Color(0xFF9AA5B4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Colored accent bar instead of a generic gray icon — the icon was purely
  // decorative (label text already says what the section is) and this modal
  // has several of these, so it was several near-identical icons in a row.
  // The accent bar still gives each section a splash of color.
  // [hint] carries the one thing this form could never say before: where the
  // fields under this heading actually show up in the mobile app.
  Widget _sectionLabel(String text, {IconData? icon, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 15,
                decoration: BoxDecoration(
                  color: UpriseColors.primaryDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                text,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: UpriseColors.primaryDark,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Divider(color: const Color(0xFFE2E6EA), thickness: 1),
              ),
            ],
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 13, top: 4),
              child: Text(
                hint,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11.5,
                  height: 1.45,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Variant Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _VariantDialog extends StatefulWidget {
  const _VariantDialog();

  @override
  State<_VariantDialog> createState() => _VariantDialogState();
}

class _VariantDialogState extends State<_VariantDialog> {
  final _sizeCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _priceOffsetCtrl = TextEditingController();

  @override
  void dispose() {
    _sizeCtrl.dispose();
    _colorCtrl.dispose();
    _stockCtrl.dispose();
    _priceOffsetCtrl.dispose();
    super.dispose();
  }

  void _showVariantError(String message) {
    AppToast.error(context, message);
  }

  void _save() {
    if (_sizeCtrl.text.trim().isEmpty && _colorCtrl.text.trim().isEmpty) {
      _showVariantError('Enter at least a size or color.');
      return;
    }
    final stockText = _stockCtrl.text.trim();
    final stock = stockText.isEmpty ? 0 : int.tryParse(stockText);
    if (stock == null || stock < 0) {
      _showVariantError('Enter a valid, non-negative stock quantity.');
      return;
    }
    final offsetText = _priceOffsetCtrl.text.trim();
    double? priceOffset;
    if (offsetText.isNotEmpty) {
      priceOffset = double.tryParse(offsetText);
      if (priceOffset == null) {
        _showVariantError('Enter a valid price offset (e.g., 10 or -5.50).');
        return;
      }
    }
    Navigator.pop(
      context,
      ProductVariant(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        size: _sizeCtrl.text.trim(),
        color: _colorCtrl.text.trim(),
        stock: stock,
        priceOffset: priceOffset,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      // Was unset — Dialog falls back to Flutter's default Material
      // surface color, which skews purple/lavender on this app's
      // unseeded theme.
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: UpriseColors.primaryDark.withAlpha(18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: UpriseColors.primaryDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Add Variant',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Color(0xFF64748B),
                  ),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _sizeCtrl,
                    decoration: _DS.inputDecoration(
                      'Size',
                      hint: 'e.g., M, L, XL',
                      icon: Icons.straighten_outlined,
                    ),
                    style: GoogleFonts.beVietnamPro(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _colorCtrl,
                    decoration: _DS.inputDecoration(
                      'Color',
                      hint: 'e.g., Red, Blue',
                      icon: Icons.color_lens_outlined,
                    ),
                    style: GoogleFonts.beVietnamPro(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _stockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _DS.inputDecoration(
                      'Stock',
                      hint: '0',
                      icon: Icons.inventory_2_outlined,
                    ),
                    style: GoogleFonts.beVietnamPro(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _priceOffsetCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: _DS.inputDecoration(
                      'Price Offset',
                      hint: '+0.00 (optional)',
                      icon: Icons.add_circle_outline_rounded,
                    ),
                    style: GoogleFonts.beVietnamPro(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE2E6EA)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.beVietnamPro(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: UpriseColors.primaryDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    'Add Variant',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PRODUCT DETAILS MODAL (with Base64 image support)
// ============================================================
class _ProductDetailsModal extends StatelessWidget {
  final ProductModel product;
  const _ProductDetailsModal({required this.product});

  @override
  Widget build(BuildContext context) {
    final totalStock = product.totalStock;
    final productId = 'PRD-${product.id.substring(0, 4).toUpperCase()}';
    // Photo-left / details-right like the event proposal view; narrow
    // screens stack the photo above the details instead.
    final isWide = MediaQuery.of(context).size.width >= 820;

    final (String, Color?) availability = product.isArchived
        ? ('Archived', const Color(0xFF6B7280))
        : product.status == 'discontinued'
        ? ('Discontinued', const Color(0xFF6B7280))
        : totalStock <= 0
        ? ('Out of stock', UpriseColors.error)
        : totalStock <= 5
        ? ('Only $totalStock left', UpriseColors.warning)
        : ('$totalStock in stock', null);

    Widget pair(Widget left, Widget right) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OrgModalSection(
          title: 'Product Details',
          icon: Icons.info_outline_rounded,
          accentColor: UpriseColors.primaryDark,
          child: Column(
            children: [
              pair(
                OrgDetailItem(
                  label: 'Price',
                  value: '₱${NumberFormat('#,##0.##').format(product.price)}',
                  icon: Icons.sell_outlined,
                  iconColor: UpriseColors.primaryDark,
                ),
                OrgDetailItem(
                  label: 'Category',
                  value: product.category.isEmpty
                      ? 'Uncategorized'
                      : product.category,
                  icon: Icons.category_outlined,
                  iconColor: UpriseColors.primaryDark,
                ),
              ),
              const SizedBox(height: 12),
              pair(
                OrgDetailItem(
                  label: 'Availability',
                  value: availability.$1,
                  valueColor: availability.$2,
                  icon: Icons.inventory_2_outlined,
                  iconColor: UpriseColors.primaryDark,
                ),
                OrgDetailItem(
                  label: 'Likes',
                  value: '${product.likeCount}',
                  icon: Icons.favorite_border_rounded,
                  iconColor: UpriseColors.primaryDark,
                ),
              ),
              const SizedBox(height: 12),
              pair(
                OrgDetailItem(
                  label: 'Variants',
                  value: product.variants.isEmpty
                      ? 'None'
                      : '${product.variants.length} '
                            'variant${product.variants.length == 1 ? '' : 's'}',
                  icon: Icons.tune_rounded,
                  iconColor: UpriseColors.primaryDark,
                ),
                OrgDetailItem(
                  label: 'Photos',
                  value: '${product.displayPhotos.length}',
                  icon: Icons.photo_library_outlined,
                  iconColor: UpriseColors.primaryDark,
                ),
              ),
              if (product.createdAt != null) ...[
                const SizedBox(height: 12),
                pair(
                  OrgDetailItem(
                    label: 'Listed On',
                    value: DateFormat(
                      'MMMM dd, yyyy',
                    ).format(product.createdAt!),
                    icon: Icons.calendar_today_outlined,
                    iconColor: UpriseColors.primaryDark,
                  ),
                  const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        OrgModalSection(
          title: 'Description',
          icon: Icons.description_outlined,
          accentColor: UpriseColors.primaryDark,
          child: Text(
            product.description.isEmpty
                ? 'No description provided.'
                : product.description,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
              height: 1.6,
            ),
          ),
        ),
        if (product.variants.isNotEmpty) ...[
          const SizedBox(height: 20),
          OrgModalSection(
            title: 'Variants',
            icon: Icons.tune_rounded,
            accentColor: UpriseColors.primaryDark,
            child: _buildVariantsTable(),
          ),
        ],
      ],
    );

    return OrgModalShell(
      accentColor: UpriseColors.primaryDark,
      headerColor: UpriseColors.primaryDark,
      compactHeader: true,
      icon: Icons.shopping_bag_outlined,
      title: product.name,
      width: 960,
      maxHeightFraction: 0.85,
      subtitleWidget: Row(
        children: [
          Text(
            productId,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: Colors.white.withAlpha(180),
            ),
          ),
          const SizedBox(width: 12),
          _statusBadge(product.status, isArchived: product.isArchived),
        ],
      ),
      footerActions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: UpriseColors.primaryDark,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          ),
          child: Text(
            'Close',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
      body: isWide
          ? SizedBox(
              height: 560,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _ProductGallery(product: product),
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(4, 20, 24, 20),
                      child: details,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 380,
                    child: _ProductGallery(product: product),
                  ),
                  const SizedBox(height: 20),
                  details,
                ],
              ),
            ),
    );
  }

  Widget _buildVariantsTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE8ECF0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
              border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: _variantHeader('SIZE')),
                Expanded(flex: 2, child: _variantHeader('COLOR')),
                Expanded(flex: 1, child: _variantHeader('STOCK')),
                Expanded(flex: 2, child: _variantHeader('PRICE')),
              ],
            ),
          ),
          ...product.variants.asMap().entries.map((entry) {
            final v = entry.value;
            final isLast = entry.key == product.variants.length - 1;
            final effectivePrice = product.price + (v.priceOffset ?? 0);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(
                        bottom: BorderSide(color: Color(0xFFF1F5F9)),
                      ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _variantValue(v.size.isEmpty ? '—' : v.size),
                  ),
                  Expanded(
                    flex: 2,
                    child: _variantValue(v.color.isEmpty ? '—' : v.color),
                  ),
                  Expanded(flex: 1, child: _variantValue('${v.stock}')),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Text(
                          '₱${NumberFormat('#,###.##').format(effectivePrice)}',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: UpriseColors.primaryDark,
                          ),
                        ),
                        if (v.priceOffset != null && v.priceOffset != 0) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '(${v.priceOffset! >= 0 ? '+' : ''}${NumberFormat('#,###.##').format(v.priceOffset!)})',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 10,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _variantHeader(String text) {
    return Text(
      text,
      style: GoogleFonts.beVietnamPro(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF64748B),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _variantValue(String text) {
    return Text(
      text,
      style: GoogleFonts.beVietnamPro(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF1A202C),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product gallery (view modal)
//
// Big photo on top with a strip of small thumbnails underneath, the same way
// the mobile Product Details screen shows the other angles of a product.
// Tapping a thumbnail (or the arrows) swaps the main photo.
// ─────────────────────────────────────────────────────────────────────────────
class _ProductGallery extends StatefulWidget {
  final ProductModel product;
  const _ProductGallery({required this.product});

  @override
  State<_ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<_ProductGallery> {
  // Resolved once so switching photos doesn't re-decode base64 every build.
  late final List<ImageProvider?> _photos = widget.product.displayPhotos
      .map(AppImage.provider)
      .toList();
  int _index = 0;

  void _go(int i) {
    if (_photos.isEmpty) return;
    setState(() => _index = i % _photos.length);
  }

  @override
  Widget build(BuildContext context) {
    final multiple = _photos.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E6EA)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildMain(),
                if (multiple) ...[
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(140),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_index + 1}/${_photos.length}',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _arrow(
                        Icons.chevron_left_rounded,
                        () => _go(_index - 1 + _photos.length),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _arrow(
                        Icons.chevron_right_rounded,
                        () => _go(_index + 1),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (multiple) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final selected = i == _index;
                final image = _photos[i];
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _go(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? UpriseColors.primaryDark
                              : const Color(0xFFE2E6EA),
                          width: selected ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: image == null
                          ? const Icon(
                              Icons.broken_image_outlined,
                              size: 20,
                              color: Color(0xFFB0BAC8),
                            )
                          : Image(
                              image: ResizeImage(image, width: 160),
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMain() {
    if (_photos.isNotEmpty) {
      final image = _photos[_index];
      if (image != null) {
        return Image(
          image: image,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      }
      return _placeholder();
    }
    // Very old products only carry an imageUrl.
    final url = widget.product.imageUrl;
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => const Center(
    child: Icon(
      Icons.image_not_supported_outlined,
      size: 48,
      color: Color(0xFF9AA5B4),
    ),
  );

  Widget _arrow(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withAlpha(230),
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 22, color: const Color(0xFF1A202C)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────
class _FilterDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final String hint;
  final IconData icon;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.hint,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = value != 'All';
    return AnchoredMenuTrigger<String>(
      items: items,
      labelOf: (s) => s,
      selectedValue: value,
      onSelected: onChanged,
      trigger: Container(
        height: 40,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? UpriseColors.primaryDark.withAlpha(14) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? UpriseColors.primaryDark.withAlpha(90)
                : _DS.borderSoft,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // [icon] used to be accepted but never actually rendered —
            // Category and Availability looked identical at a glance.
            Icon(
              icon,
              size: 15,
              color: active
                  ? UpriseColors.primaryDark
                  : const Color(0xFF9AA5B4),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                active ? value : hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active
                      ? UpriseColors.primaryDark
                      : const Color(0xFF374151),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: active
                  ? UpriseColors.primaryDark
                  : const Color(0xFF9AA5B4),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MODEL CLASSES (updated with Base64 support)
// ============================================================
class ProductVariant {
  final String id;
  final String size;
  final String color;
  final int stock;
  final double? priceOffset;

  ProductVariant({
    required this.id,
    required this.size,
    required this.color,
    required this.stock,
    this.priceOffset,
  });

  factory ProductVariant.fromMap(Map<String, dynamic> map) => ProductVariant(
    id: map['id'] ?? '',
    size: map['size'] ?? '',
    color: map['color'] ?? '',
    stock: ((map['stock'] ?? 0) as num).toInt(),
    priceOffset: map['priceOffset'] != null
        ? (map['priceOffset'] as num).toDouble()
        : null,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'size': size,
    'color': color,
    'stock': stock,
    if (priceOffset != null) 'priceOffset': priceOffset,
  };
}

class ProductModel {
  final String id;
  final String name;
  final String description;
  final String category;
  final double price;
  final double costPrice;
  final int stock;
  final int sold;
  final String imageUrl;
  final String? imageBase64;
  final String? imageFormat;
  final String status;
  final bool isArchived;
  final List<ProductVariant> variants;
  // Multiple angle photos for the swipeable product gallery. Falls back to
  // just [imageBase64] when empty, so existing products with a single photo
  // still render fine.
  final List<String> rotationPhotos;
  // Students and guests heart products from the mobile catalog into this
  // array — with no checkout flow left, it is the only real feedback the
  // shop produces, so the org portal reads it too.
  final List<String> likedBy;
  final DateTime? createdAt;

  ProductModel({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    this.costPrice = 0,
    required this.stock,
    required this.sold,
    this.imageUrl = '',
    this.imageBase64,
    this.imageFormat,
    this.status = 'available',
    this.isArchived = false,
    this.variants = const [],
    this.rotationPhotos = const [],
    this.likedBy = const [],
    this.createdAt,
  });

  factory ProductModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ProductModel(
      id: doc.id,
      name: d['name'] ?? '',
      description: d['description'] ?? '',
      category: d['category'] ?? '',
      price: (d['price'] ?? 0).toDouble(),
      costPrice: (d['costPrice'] ?? 0).toDouble(),
      stock: d['stock'] ?? 0,
      sold: d['sold'] ?? 0,
      imageUrl: d['imageUrl'] ?? '',
      imageBase64: d['imageBase64'] as String?,
      imageFormat: d['imageFormat'] as String?,
      status: d['status'] ?? 'available',
      isArchived: d['isArchived'] == true,
      variants: ((d['variants'] as List?) ?? [])
          .map((v) => ProductVariant.fromMap(v as Map<String, dynamic>))
          .toList(),
      rotationPhotos: ((d['rotationPhotos'] as List?) ?? []).cast<String>(),
      likedBy: ((d['likedBy'] as List?) ?? [])
          .map((e) => e.toString())
          .toList(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  // Falls back to the single main photo when no dedicated photo set was
  // uploaded, so the gallery always has at least one image to show.
  int get likeCount => likedBy.length;

  // Total on hand: variant stocks are the source of truth once any variant
  // exists, otherwise the flat [stock] field.
  int get totalStock => variants.isNotEmpty
      ? variants.fold<int>(0, (sum, v) => sum + v.stock)
      : stock;

  List<String> get displayPhotos => rotationPhotos.isNotEmpty
      ? rotationPhotos
      : (imageBase64 != null && imageBase64!.isNotEmpty ? [imageBase64!] : []);
}
