// lib/screens/web/org/org_merchandise.dart

import 'dart:convert';
import '../../../widgets/stat_cards.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:universal_html/html.dart' as html;
import '../../../services/activity_logger.dart' as activity_log;
import '../../../theme/org_theme.dart';
import '../../../widgets/admin_export_button.dart';
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/product_photo_gallery.dart';
import '../../../widgets/org_action_icon_button.dart';
import '../admin/export_util.dart';
import '../admin/export_pdf.dart';
import 'export_pdf.dart' show OrgExportPdf;
import 'export_util.dart' show OrgExportUtil;

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (mirrors student accounts)
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const double radiusSm = 8;
  static const double radiusMd = 14;
  static const double radiusPill = 100;
  static const Color borderSoft = Color(0xFFE2E6EA);

  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
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
// Status badge (reused)
// ─────────────────────────────────────────────────────────────────────────────
Widget _statusBadge(String status) {
  final Map<String, _BadgeStyle> styles = {
    'published': _BadgeStyle(
      const Color(0xFFECFDF5),
      const Color(0xFF059669),
      'PUBLISHED',
    ),
    'draft': _BadgeStyle(
      const Color(0xFFFFFBEB),
      const Color(0xFFFB923C),
      'DRAFT',
    ),
    'archived': _BadgeStyle(
      const Color(0xFFFEF2F2),
      const Color(0xFFDC2626),
      'ARCHIVED',
    ),
  };
  final s =
      styles[status.toLowerCase()] ??
      _BadgeStyle(
        const Color(0xFFF3F4F6),
        const Color(0xFF6B7280),
        status.toUpperCase(),
      );
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: s.bg,
      borderRadius: BorderRadius.circular(_DS.radiusPill),
    ),
    child: Text(
      s.label,
      style: GoogleFonts.beVietnamPro(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: s.fg,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _BadgeStyle {
  final Color bg, fg;
  final String label;
  const _BadgeStyle(this.bg, this.fg, this.label);
}

const List<String> _merchandiseCategories = [
  'T-Shirts / Uniforms',
  'Lanyards / IDs',
  'Stickers / Pins',
  'Tumblers / Water Bottles',
  'Notebooks / Planners',
  'Others',
];

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────
class OrgMerchandiseScreen extends StatefulWidget {
  final String orgId;
  const OrgMerchandiseScreen({super.key, required this.orgId});

  @override
  State<OrgMerchandiseScreen> createState() => _OrgMerchandiseScreenState();
}

class _OrgMerchandiseScreenState extends State<OrgMerchandiseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTab = 0;

  // Created once, not inline in build() — _buildStatsRow rebuilds on every
  // tab change, so constructing fresh .snapshots() there each time was
  // re-subscribing to Firestore from scratch every time.
  late final Stream<QuerySnapshot> _statsProductsStream = FirebaseFirestore
      .instance
      .collection('products')
      .where('orgId', isEqualTo: widget.orgId)
      .where('isArchived', isEqualTo: false)
      .snapshots();
  late final Stream<QuerySnapshot> _statsOrdersStream = FirebaseFirestore
      .instance
      .collection('orders')
      .where('orgId', isEqualTo: widget.orgId)
      .snapshots();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFE),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(isMobile),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _ProductsTab(
                  orgId: widget.orgId,
                  onAddProduct: () => _openAddProductModal(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Bordered admin-dashboard-style stat cards + a separate toolbar row read
  // as a generic CRUD panel, not a shop — merged into one header where the
  // stats are lightweight inline chips (secondary information) and the
  // actual visual weight goes to the "Shop" identity and the product grid
  // below. _statsOrdersStream is left defined but unused (Sales/Revenue
  // cards were removed along with the checkout flow).
  Widget _buildHeader(bool isMobile) {
    return StreamBuilder<QuerySnapshot>(
      stream: _statsProductsStream,
      builder: (context, productSnap) {
        final products = productSnap.data?.docs ?? [];
        final totalProducts = products.length;
        final lowStock = products
            .where((p) => ((p.data() as Map)['stock'] ?? 0) <= 5)
            .length;

        final title = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Shop',
              style: GoogleFonts.beVietnamPro(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1A202C),
              ),
            ),
            const SizedBox(width: 14),
            Container(width: 1, height: 16, color: const Color(0xFFE2E6EA)),
            const SizedBox(width: 14),
            _InlineStat(
              icon: Icons.shopping_bag_outlined,
              text: '$totalProducts product${totalProducts == 1 ? '' : 's'}',
              color: UpriseColors.info,
            ),
            if (lowStock > 0) ...[
              const SizedBox(width: 16),
              _InlineStat(
                icon: Icons.warning_amber_rounded,
                text: '$lowStock low stock',
                color: UpriseColors.error,
              ),
            ],
          ],
        );

        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AdminExportButton(
              onSelected: (format) => _exportCurrentTab(format),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () => _openAddProductModal(context),
              icon: const Icon(Icons.add, size: 18, color: Colors.white),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ],
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 16 : 28,
            isMobile ? 16 : 24,
            isMobile ? 16 : 28,
            0,
          ),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 14), actions],
                )
              : Row(children: [title, const Spacer(), actions]),
        );
      },
    );
  }

  Future<void> _exportCurrentTab(String format) async {
    if (_selectedTab == 0) {
      await _exportProducts(format);
    } else {
      await _exportOrders(format);
    }
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
    // AdminExportButton's dropdown emits 'excel'/'pdf' (see
    // admin_export_button.dart's _items), not 'csv' — this used to check
    // for 'csv', so "Export as Excel" silently did nothing.
    if (format == 'excel') {
      final buf = StringBuffer();
      buf.writeln('Product Name,Category,Price,Stock,Sold');
      for (final doc in docs) {
        final d = doc.data();
        buf.writeln(
          '"${d['name']}","${d['category']}","${d['price']}","${d['stock']}","${d['sold']}"',
        );
      }
      await AdminExportUtil.saveText(
        buf.toString(),
        'products_$now.csv',
        mimeType: 'text/csv',
      );
    } else if (format == 'pdf') {
      final rows = docs.map((doc) {
        final d = doc.data();
        return [
          '${d['name']}',
          '${d['category']}',
          '${d['price']}',
          '${d['stock']}',
          '${d['sold']}',
        ];
      }).toList();
      final pdfBytes = await AdminExportPdf.generateTablePdf(
        title: 'Product Inventory',
        headers: const ['Name', 'Category', 'Price', 'Stock', 'Sold'],
        rows: rows,
      );
      await AdminExportUtil.saveBytes(
        pdfBytes,
        'products_$now.pdf',
        mimeType: 'application/pdf',
      );
    }
    _showSnack('Exported products', UpriseColors.success);
  }

  Future<void> _exportOrders(String format) async {
    final snap = await FirebaseFirestore.instance
        .collection('orders')
        .where('orgId', isEqualTo: widget.orgId)
        .orderBy('createdAt', descending: true)
        .get();
    final docs = snap.docs;
    if (docs.isEmpty) {
      _showSnack('No orders to export', UpriseColors.warning);
      return;
    }
    final now = DateFormat('yyyyMMdd').format(DateTime.now());
    if (format == 'csv') {
      final buf = StringBuffer();
      buf.writeln(
        'Order ID,Customer,Section,Total,Status,Pickup Status,Date,Bundle ID',
      );
      for (final doc in docs) {
        final d = doc.data();
        final createdAt = d['createdAt'] as Timestamp?;
        final date = createdAt != null
            ? DateFormat('yyyy-MM-dd').format(createdAt.toDate())
            : '—';
        buf.writeln(
          '"${d['orderId']}","${d['customerName']}","${d['section'] ?? ''}","${d['total']}","${d['status']}","${d['pickupStatus'] ?? 'Pending'}","$date","${d['bundleId'] ?? ''}"',
        );
      }
      await AdminExportUtil.saveText(
        buf.toString(),
        'orders_$now.csv',
        mimeType: 'text/csv',
      );
    } else if (format == 'pdf') {
      final rows = docs.map((doc) {
        final d = doc.data();
        final createdAt = d['createdAt'] as Timestamp?;
        final date = createdAt != null
            ? DateFormat('yyyy-MM-dd').format(createdAt.toDate())
            : '—';
        return [
          '${d['orderId']}',
          '${d['customerName']}',
          '${d['section'] ?? ''}',
          '${d['total']}',
          '${d['status']}',
          '${d['pickupStatus'] ?? 'Pending'}',
          date,
        ];
      }).toList();
      final pdfBytes = await AdminExportPdf.generateTablePdf(
        title: 'Sales Orders',
        headers: const [
          'Order ID',
          'Customer',
          'Section',
          'Total',
          'Status',
          'Pickup Status',
          'Date',
        ],
        rows: rows,
      );
      await AdminExportUtil.saveBytes(
        pdfBytes,
        'orders_$now.pdf',
        mimeType: 'application/pdf',
      );
    }
    _showSnack('Exported orders', UpriseColors.success);
  }

  void _openAddProductModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProductModal(
        orgId: widget.orgId,
        onProductSaved: () {
          setState(() {});
        },
      ),
    );
  }

  void _openSalesReport(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _SalesReportModal(orgId: widget.orgId),
    );
  }

  void _openGcashSettings(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GcashSettingsDialog(orgId: widget.orgId),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.beVietnamPro()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pill Tab
// ─────────────────────────────────────────────────────────────────────────────
class _PillTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PillTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? UpriseColors.primaryDark : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline stat — a small icon+text pair instead of a bordered card, for the
// merchandise header where the stats are secondary to the "Shop" identity.
// ─────────────────────────────────────────────────────────────────────────────
class _InlineStat extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InlineStat({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          text,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// PRODUCTS TAB - Card Grid with Infinite Scroll
// ============================================================
class _ProductsTab extends StatefulWidget {
  final String orgId;
  final VoidCallback onAddProduct;
  const _ProductsTab({required this.orgId, required this.onAddProduct});

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _categoryFilter = 'All';
  String _statusFilter = 'All';

  final List<String> _categoryFilters = ['All', ..._merchandiseCategories];
  final List<String> _statusFilters = [
    'All',
    'Available',
    'Out of Stock',
    'Discontinued',
    'Archived',
  ];

  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  List<ProductModel> _products = [];
  DocumentSnapshot? _lastDocument;
  bool _isInitialLoad = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreProducts();
    }
  }

  Future<void> _loadProducts({bool reset = true}) async {
    if (_isLoading) return;
    if (reset) {
      setState(() {
        _products = [];
        _lastDocument = null;
        _hasMore = true;
        _isInitialLoad = true;
      });
    }
    await _fetchProducts(reset: reset);
  }

  Future<void> _fetchProducts({bool reset = true}) async {
    if (_isLoading || !_hasMore) return;

    setState(() => _isLoading = true);

    try {
      var query = FirebaseFirestore.instance
          .collection('products')
          .where('orgId', isEqualTo: widget.orgId)
          .where('isArchived', isEqualTo: _statusFilter == 'Archived')
          .orderBy('createdAt', descending: true);

      if (!reset && _lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      query = query.limit(20);
      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoading = false;
          _isInitialLoad = false;
        });
        return;
      }

      final newProducts = snapshot.docs
          .map((d) => ProductModel.fromFirestore(d))
          .toList();

      final filtered = _applyFilters(newProducts);

      setState(() {
        if (reset) {
          _products = filtered;
        } else {
          _products.addAll(filtered);
        }
        _lastDocument = snapshot.docs.last;
        _hasMore = snapshot.docs.length >= 20;
        _isLoading = false;
        _isInitialLoad = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isInitialLoad = false;
      });
      if (mounted) _showSnack('Error loading products: $e', UpriseColors.error);
    }
  }

  void _loadMoreProducts() {
    if (!_isLoading && _hasMore && !_isInitialLoad) {
      _fetchProducts(reset: false);
    }
  }

  List<ProductModel> _applyFilters(List<ProductModel> list) {
    return list.where((p) {
      final matchSearch =
          _searchQuery.isEmpty ||
          p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.category.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchCat =
          _categoryFilter == 'All' || p.category == _categoryFilter;
      final matchStatus =
          _statusFilter == 'All' ||
          _statusFilter == 'Archived' ||
          (_statusFilter == 'Available' && p.status == 'available') ||
          (_statusFilter == 'Out of Stock' && p.status == 'out_of_stock') ||
          (_statusFilter == 'Discontinued' && p.status == 'discontinued');
      return matchSearch && matchCat && matchStatus;
    }).toList();
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
                      'Archive Product',
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
                'Archive "${product.name}"? It will be hidden from the store.',
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
                      'Archive',
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
        setState(() {
          _products.removeWhere((p) => p.id == product.id);
        });
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
        setState(() {
          _products.removeWhere((p) => p.id == product.id);
        });
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', UpriseColors.error);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.beVietnamPro()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return Column(
      children: [
        _buildToolbar(isMobile),
        const SizedBox(height: 16),
        Expanded(child: _buildProductGrid(isMobile)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
          _loadProducts(reset: true);
        },
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search products...',
          hintStyle: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: const Color(0xFF9AA5B4),
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: Color(0xFF9AA5B4),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: UpriseColors.primaryDark, width: 1.5),
          ),
        ),
      ),
    );
  }

  // Was search + dropdowns floating loose directly on the page background,
  // no unifying surface — same "awful" bare-controls look fixed on the
  // Announcements toolbar. One elevated card now groups them.
  Widget _buildToolbar(bool isMobile) {
    final horizontalPadding = isMobile ? 16.0 : 28.0;
    final content = isMobile
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchField(),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _FilterDropdown(
                      value: _categoryFilter,
                      items: _categoryFilters,
                      hint: 'Category',
                      icon: Icons.category_outlined,
                      onChanged: (v) {
                        setState(() {
                          _categoryFilter = v!;
                        });
                        _loadProducts(reset: true);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FilterDropdown(
                      value: _statusFilter,
                      items: _statusFilters,
                      hint: 'Status',
                      icon: Icons.circle_outlined,
                      onChanged: (v) {
                        setState(() {
                          _statusFilter = v!;
                        });
                        _loadProducts(reset: true);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${_products.length} products',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          )
        : Row(
            children: [
              SizedBox(width: 260, child: _buildSearchField()),
              const SizedBox(width: 10),
              _FilterDropdown(
                value: _categoryFilter,
                items: _categoryFilters,
                hint: 'Category',
                icon: Icons.category_outlined,
                onChanged: (v) {
                  setState(() {
                    _categoryFilter = v!;
                  });
                  _loadProducts(reset: true);
                },
              ),
              const SizedBox(width: 10),
              _FilterDropdown(
                value: _statusFilter,
                items: _statusFilters,
                hint: 'Status',
                icon: Icons.circle_outlined,
                onChanged: (v) {
                  setState(() {
                    _statusFilter = v!;
                  });
                  _loadProducts(reset: true);
                },
              ),
              const Spacer(),
              Text(
                '${_products.length} products',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: _DS.cardShadow,
        ),
        child: content,
      ),
    );
  }

  Widget _buildProductGrid(bool isMobile) {
    if (_isInitialLoad) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_products.isEmpty) {
      return _buildEmptyState(
        Icons.inventory_2_outlined,
        'No products found',
        _searchQuery.isNotEmpty ||
                _categoryFilter != 'All' ||
                _statusFilter != 'All'
            ? 'Try adjusting your filters'
            : 'Click "Add Product" to get started.',
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 28),
      // A fixed 4-column grid always reserved 4 columns' worth of width even
      // with only 1-2 products, leaving most of a wide screen blank —
      // MaxCrossAxisExtent instead sizes each card to a comfortable target
      // width and lets the column count adapt to whatever's actually there,
      // like a real product-catalog grid rather than a sparse admin table.
      // A single column on phone widths gives each card its full target
      // size (280) instead of squeezing two half-width cards side by side.
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: isMobile ? 480 : 280,
        crossAxisSpacing: 20,
        mainAxisSpacing: 28,
        childAspectRatio: 0.68,
      ),
      itemCount: _products.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _products.length) {
          return _buildLoadingMoreIndicator();
        }
        return _ProductCard(
          product: _products[index],
          alwaysShowActions: isMobile,
          onTap: () => showDialog(
            context: context,
            builder: (_) => _ProductDetailsModal(product: _products[index]),
          ),
          onArchive: () => _products[index].isArchived
              ? _unarchiveProduct(_products[index])
              : _archiveProduct(_products[index]),
          onEdit: () => showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => _ProductModal(
              orgId: widget.orgId,
              existingProduct: _products[index],
              onProductSaved: () {
                _loadProducts(reset: true);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Container(
      height: 80,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message, String subtitle) {
    final bool noFiltersActive =
        _searchQuery.isEmpty &&
        _categoryFilter == 'All' &&
        _statusFilter == 'All';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: UpriseColors.primaryDark.withAlpha(20),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              icon,
              size: 44,
              color: UpriseColors.primaryDark.withAlpha(160),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            noFiltersActive ? 'Your store is empty' : message,
            style: GoogleFonts.beVietnamPro(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A202C),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            noFiltersActive
                ? 'Add your first product to start selling merchandise to students.'
                : subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
          if (noFiltersActive) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ],
        ],
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
    final totalStock = product.variants.isNotEmpty
        ? product.variants.fold<int>(0, (sum, v) => sum + v.stock)
        : product.stock;
    final isLowStock = totalStock <= 5 && totalStock > 0;
    final isOutOfStock = totalStock == 0;
    final isDiscontinued = product.status == 'discontinued';
    final String? statusLabel = isOutOfStock
        ? 'Out of Stock'
        : isDiscontinued
        ? 'Discontinued'
        : isLowStock
        ? 'Low Stock'
        : null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_DS.radiusMd),
            border: Border.all(color: _DS.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _hovering
                        ? [
                            BoxShadow(
                              color: Colors.black.withAlpha(28),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ]
                        : _DS.cardShadow,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedScale(
                          duration: const Duration(milliseconds: 200),
                          scale: _hovering ? 1.05 : 1.0,
                          child: _buildProductImage(),
                        ),
                        // Quick-action affordance, like a storefront's
                        // wishlist/quick-view icons — invisible until hovered
                        // instead of permanent chrome over the product photo.
                        Positioned(
                          right: 8,
                          top: 8,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: (_hovering || widget.alwaysShowActions)
                                ? 1
                                : 0,
                            child: IgnorePointer(
                              ignoring:
                                  !(_hovering || widget.alwaysShowActions),
                              child: Column(
                                children: [
                                  _CardActionButton(
                                    icon: Icons.edit_outlined,
                                    tooltip: 'Edit',
                                    onTap: widget.onEdit,
                                  ),
                                  const SizedBox(height: 6),
                                  _CardActionButton(
                                    icon: widget.product.isArchived
                                        ? Icons.unarchive_outlined
                                        : Icons.archive_outlined,
                                    tooltip: widget.product.isArchived
                                        ? 'Unarchive'
                                        : 'Archive',
                                    onTap: widget.onArchive,
                                    color: UpriseColors.warning,
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
              ),
              const SizedBox(height: 12),
              Text(
                product.category,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: UpriseColors.darkGray,
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
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
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '₱${NumberFormat('#,###').format(product.price)}',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$totalStock in stock',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: const Color(0xFF9AA5B4),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (statusLabel != null) ...[
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 12,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              ],
              if (product.sold > 0) ...[
                const SizedBox(height: 3),
                Text(
                  '${product.sold} sold',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF059669),
                  ),
                ),
              ],
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

  const _ProductModal({
    required this.orgId,
    this.existingProduct,
    this.onProductSaved,
  });

  @override
  State<_ProductModal> createState() => _ProductModalState();
}

class _ProductModalState extends State<_ProductModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _costPriceCtrl = TextEditingController();
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
      _costPriceCtrl.text = p.costPrice.toStringAsFixed(2);
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
    _costPriceCtrl.dispose();
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
      final oldStock = _isEdit ? widget.existingProduct!.stock : 0;

      final data = <String, dynamic>{
        'orgId': widget.orgId,
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'category': effectiveCategory,
        'costPrice': double.tryParse(_costPriceCtrl.text.trim()) ?? 0,
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
        if (stock != oldStock || !_isEdit) {
          final reason = !_isEdit
              ? 'initial'
              : (stock > oldStock ? 'restocked' : 'adjusted');
          await FirebaseFirestore.instance.collection('stock_logs').add({
            'productId': productId,
            'oldStock': oldStock,
            'newStock': stock,
            'reason': reason,
            'changedBy': user?.email ?? '',
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEdit
                  ? 'Product updated successfully!'
                  : 'Product added successfully!',
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.beVietnamPro()),
        backgroundColor: UpriseColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // A fixed 520px width overflowed on phone-width screens (insetPadding
    // alone doesn't shrink a Container with an explicit width) — cap it to
    // whatever's actually available instead.
    final modalWidth = screenWidth < 520 + 64 ? screenWidth - 64 : 520.0;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: modalWidth,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        // Only the header strip below had an explicit background — the
        // scrollable body had none, so Flutter's default unseeded Material
        // surface bled through there. Same root cause fixed on every other
        // modal in this app.
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FB),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: UpriseColors.primaryDark.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: UpriseColors.primaryDark,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEdit ? 'Edit Product' : 'Add Product',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_isEdit && widget.existingProduct != null)
                          Text(
                            'PRODUCT ID: #${widget.existingProduct!.id.substring(0, 8).toUpperCase()}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 10,
                              color: UpriseColors.darkGray,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Close',
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
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
                      ),
                      TextFormField(
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
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Category',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FB),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E6EA)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _category,
                            isExpanded: true,
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: Color(0xFF9AA5B4),
                            ),
                            items: _merchandiseCategories
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(
                                      c,
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null)
                                setState(() => _category = value);
                            },
                          ),
                        ),
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
                          validator: (v) =>
                              v?.trim().isEmpty ?? true ? 'Required' : null,
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descCtrl,
                        maxLines: 3,
                        decoration: _DS.inputDecoration(
                          'Description',
                          hint: 'Product details...',
                          icon: Icons.description_outlined,
                        ),
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      _sectionLabel('Pricing', icon: Icons.payments_outlined),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _costPriceCtrl,
                              keyboardType: TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: _DS.inputDecoration(
                                'Cost Price',
                                hint: '0.00',
                                icon: Icons.money_off_outlined,
                              ),
                              style: GoogleFonts.beVietnamPro(fontSize: 13),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _priceCtrl,
                              keyboardType: TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: _DS.inputDecoration(
                                'Base Price',
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
                          ),
                        ],
                      ),
                      _buildProfitMarginLine(),
                      if (_variants.isEmpty) ...[
                        const SizedBox(height: 16),
                        _sectionLabel(
                          'Inventory',
                          icon: Icons.inventory_2_outlined,
                        ),
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
                        ),
                      ],
                      if (_isEdit) ...[
                        const SizedBox(height: 10),
                        Row(
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
                            const SizedBox(width: 8),
                            Text(
                              'Mark as Discontinued',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                color: _isDiscontinued
                                    ? const Color(0xFF6B7280)
                                    : const Color(0xFF374151),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      _sectionLabel('Variants', icon: Icons.tune_rounded),
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
                        'Product Photo',
                        icon: Icons.image_outlined,
                      ),
                      _buildImagePicker(),
                      const SizedBox(height: 16),
                      _sectionLabel(
                        'More Photos (optional)',
                        icon: Icons.collections_outlined,
                      ),
                      _buildRotationPhotosPicker(),
                    ],
                  ),
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
                color: Color(0xFFF8F9FB),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE2E6EA)),
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
                        color: const Color(0xFF374151),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: (_submitting || _uploadingImage)
                        ? null
                        : _submit,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            'etc. — so students can swipe through the set, the way most '
            'shopping sites show a product. JPG or PNG, up to 10 MB each '
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

  Widget _buildProfitMarginLine() {
    final cost = double.tryParse(_costPriceCtrl.text.trim());
    final price = double.tryParse(_priceCtrl.text.trim());
    if (cost == null || price == null || price <= 0) {
      return const SizedBox(height: 4);
    }
    final profit = price - cost;
    final marginPct = (profit / price) * 100;
    final isNegative = profit < 0;
    final color = isNegative
        ? const Color(0xFFDC2626)
        : const Color(0xFF059669);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            isNegative
                ? Icons.trending_down_rounded
                : Icons.trending_up_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            'Profit: ₱${profit.toStringAsFixed(2)} (${marginPct.toStringAsFixed(0)}% margin)',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
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
  Widget _sectionLabel(String text, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.beVietnamPro()),
        backgroundColor: UpriseColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
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
    final totalStock = product.variants.isNotEmpty
        ? product.variants.fold<int>(0, (sum, v) => sum + v.stock)
        : product.stock;

    final productId = 'PRD-${product.id.substring(0, 4).toUpperCase()}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 520,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        // Neither the header nor body had an explicit background, so
        // Flutter's default unseeded Material surface bled through the
        // whole dialog — same root cause fixed elsewhere in this app.
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A flat white header here used to be a deliberate choice to
            // avoid a "loud" solid color block — but a soft flat tint gets
            // the same restraint while actually matching every other
            // modal's header treatment in this app (Registration Answers,
            // the dashboard's detail modal, etc.), instead of being the one
            // plain-white outlier next to them.
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 18),
              decoration: BoxDecoration(
                color: UpriseColors.primaryDark.withAlpha(16),
                border: const Border(
                  bottom: BorderSide(color: Color(0xFFEEF0F3)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: UpriseColors.primaryDark.withAlpha(28),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.shopping_bag_outlined,
                      color: UpriseColors.primaryDark,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1A202C),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          productId,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: const Color(0xFF9AA5B4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(product.status),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF9AA5B4),
                      size: 20,
                    ),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A portrait photo inside a full-width 220px-tall box
                    // (ProductPhotoGallery's default) left huge empty gutters
                    // on either side — capping the width and centering it
                    // makes the frame match the photo instead of dwarfing
                    // it.
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: _buildProductImage(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Plain stacked icon+label+value pairs read as a form,
                    // not a product summary — small tinted cards in a grid
                    // give each fact its own visual weight.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _detailCard(
                            'Category',
                            product.category,
                            Icons.category_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _detailCard(
                            'Price',
                            '₱${NumberFormat('#,###').format(product.price)}',
                            Icons.payments_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _detailCard(
                            'Stock',
                            '$totalStock units',
                            Icons.inventory_2_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _detailCard(
                            'Sold',
                            '${product.sold} units',
                            Icons.shopping_cart_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (product.description.isNotEmpty) ...[
                      _sectionTitle('Description', Icons.notes_rounded),
                      Text(
                        product.description,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: const Color(0xFF475569),
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Variants Section
                    if (product.variants.isNotEmpty) ...[
                      _sectionTitle('Variants', Icons.tune_rounded),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE8ECF0)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF8F9FB),
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(10),
                                ),
                                border: Border(
                                  bottom: BorderSide(color: Color(0xFFE8ECF0)),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: _variantHeader('SIZE'),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: _variantHeader('COLOR'),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: _variantHeader('STOCK'),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: _variantHeader('PRICE'),
                                  ),
                                ],
                              ),
                            ),
                            ...product.variants.asMap().entries.map((entry) {
                              final v = entry.value;
                              final isLast =
                                  entry.key == product.variants.length - 1;
                              final effectivePrice =
                                  product.price + (v.priceOffset ?? 0);
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  border: isLast
                                      ? null
                                      : const Border(
                                          bottom: BorderSide(
                                            color: Color(0xFFF1F5F9),
                                          ),
                                        ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: _variantValue(
                                        v.size.isEmpty ? '—' : v.size,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: _variantValue(
                                        v.color.isEmpty ? '—' : v.color,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: _variantValue('${v.stock}'),
                                    ),
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
                                          if (v.priceOffset != null &&
                                              v.priceOffset != 0) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              '(${v.priceOffset! >= 0 ? '+' : ''}${NumberFormat('#,###.##').format(v.priceOffset!)})',
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 10,
                                                color: const Color(0xFF64748B),
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
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Stock History
                    _sectionTitle('Stock History', Icons.history_rounded),
                    const SizedBox(height: 10),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('stock_logs')
                          .where('productId', isEqualTo: product.id)
                          .orderBy('timestamp', descending: true)
                          .limit(20)
                          .snapshots(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        final logs = snap.data?.docs ?? [];
                        if (logs.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FB),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                'No stock changes recorded yet.',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12,
                                  color: const Color(0xFF9AA5B4),
                                ),
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: logs.map((doc) {
                            final d = doc.data() as Map<String, dynamic>;
                            final ts = d['timestamp'] as Timestamp?;
                            final date = ts != null
                                ? DateFormat(
                                    'MMM d, yyyy h:mm a',
                                  ).format(ts.toDate())
                                : '—';
                            final oldS = d['oldStock'] ?? 0;
                            final newS = d['newStock'] ?? 0;
                            final reason = (d['reason'] ?? '').toString();
                            final by = d['changedBy'] ?? '—';
                            final isIncrease = newS > oldS;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FB),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFE8ECF0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: isIncrease
                                          ? const Color(0xFFECFDF5)
                                          : const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      isIncrease
                                          ? Icons.arrow_upward_rounded
                                          : Icons.arrow_downward_rounded,
                                      size: 16,
                                      color: isIncrease
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFDC2626),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              '$oldS → $newS units',
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF1A202C),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: UpriseColors.primaryDark
                                                    .withAlpha(18),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                reason.toUpperCase(),
                                                style: GoogleFonts.beVietnamPro(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      UpriseColors.primaryDark,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$date · $by',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 11,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
                color: Color(0xFFF8F9FB),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
              ),
              child: Row(
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
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    child: Text(
                      'Close',
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductImage() {
    // Prefer the drag-to-rotate viewer when there's at least one photo to
    // show — it degrades to a plain static image when only one is set, and
    // falls back to the legacy network image for very old products with
    // neither.
    final photos = product.displayPhotos;
    if (photos.isNotEmpty) {
      return ProductPhotoGallery(photosBase64: photos, height: 220);
    }
    return _buildNetworkImage();
  }

  Widget _buildNetworkImage() {
    if (product.imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          product.imageUrl,
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => Container(
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.image_not_supported_outlined,
              size: 48,
              color: Color(0xFF9AA5B4),
            ),
          ),
        ),
      );
    }
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 48,
        color: Color(0xFF9AA5B4),
      ),
    );
  }

  Widget _detailCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEF0F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: UpriseColors.primaryDark),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A202C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: UpriseColors.darkGray),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: UpriseColors.charcoal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(color: const Color(0xFFE2E6EA), thickness: 1),
          ),
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

// ============================================================
// ORDERS TAB (unchanged)
// ============================================================
class _OrdersTab extends StatefulWidget {
  final String orgId;
  const _OrdersTab({required this.orgId});

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  final TextEditingController _searchController = TextEditingController();
  // Created once, not inline in build() — _buildTable rebuilds on every
  // keystroke/filter change/pagination, so constructing fresh
  // .snapshots() there each time was re-subscribing to Firestore from
  // scratch on every keystroke.
  late final Stream<QuerySnapshot> _ordersStream = FirebaseFirestore.instance
      .collection('orders')
      .where('orgId', isEqualTo: widget.orgId)
      .orderBy('createdAt', descending: true)
      .snapshots();
  String _searchQuery = '';
  String _statusFilter = 'All';
  String _bundleIdFilter = 'All';
  String _sectionFilter = 'All';
  String _pickupStatusFilter = 'All';
  int _currentPage = 1;
  static const int _pageSize = 10;
  bool _isBulkUpdating = false;

  final List<String> _statusFilters = [
    'All',
    'Pending',
    'Processing',
    'Completed',
  ];
  List<String> _availableBundleIds = ['All'];
  List<String> _availableSections = ['All'];

  List<OrderModel> _applyFilters(List<OrderModel> orders) {
    return orders.where((o) {
      final matchSearch =
          _searchQuery.isEmpty ||
          o.customerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          o.orderId.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchStatus =
          _statusFilter == 'All' ||
          o.status.toLowerCase() == _statusFilter.toLowerCase();
      final matchBundle =
          _bundleIdFilter == 'All' || o.bundleId == _bundleIdFilter;
      final matchSection =
          _sectionFilter == 'All' || o.section == _sectionFilter;
      final matchPickup =
          _pickupStatusFilter == 'All' || o.pickupStatus == _pickupStatusFilter;
      return matchSearch &&
          matchStatus &&
          matchBundle &&
          matchSection &&
          matchPickup;
    }).toList();
  }

  void _updateBundleIds(List<OrderModel> orders) {
    final ids = orders
        .map((o) => o.bundleId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    ids.sort();
    final newBundleIds = ['All', ...ids];
    if (listEquals(_availableBundleIds, newBundleIds) &&
        (_bundleIdFilter == 'All' || ids.contains(_bundleIdFilter))) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _availableBundleIds = newBundleIds;
        if (_bundleIdFilter != 'All' && !ids.contains(_bundleIdFilter)) {
          _bundleIdFilter = 'All';
        }
      });
    });
  }

  void _updateSections(List<OrderModel> orders) {
    final sections = orders
        .map((o) => o.section)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    sections.sort();
    final newSections = ['All', ...sections];
    if (listEquals(_availableSections, newSections) &&
        (_sectionFilter == 'All' || sections.contains(_sectionFilter))) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _availableSections = newSections;
        if (_sectionFilter != 'All' && !sections.contains(_sectionFilter)) {
          _sectionFilter = 'All';
        }
      });
    });
  }

  Future<void> _updateOrderPickupStatus(
    String orderId,
    String pickupStatus,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(orderId).update(
        {'pickupStatus': pickupStatus},
      );
      if (mounted)
        _showSnack('Updated to "$pickupStatus"', UpriseColors.success);
    } catch (e) {
      if (mounted) _showSnack('Error: $e', UpriseColors.error);
    }
  }

  Future<void> _bulkUpdateSection(
    String section,
    String pickupStatus,
    List<OrderModel> sectionOrders,
  ) async {
    final count = sectionOrders.length;
    final confirmed = await _showBulkConfirmDialog(
      title: 'Update Section $section',
      message:
          'Mark $count order${count == 1 ? '' : 's'} in section $section as "$pickupStatus"?',
    );
    if (!confirmed) return;
    setState(() => _isBulkUpdating = true);
    try {
      final db = FirebaseFirestore.instance;
      WriteBatch current = db.batch();
      int opCount = 0;
      final List<WriteBatch> batches = [];
      for (final order in sectionOrders) {
        current.update(db.collection('orders').doc(order.id), {
          'pickupStatus': pickupStatus,
        });
        opCount++;
        if (opCount >= 500) {
          batches.add(current);
          current = db.batch();
          opCount = 0;
        }
      }
      if (opCount > 0) batches.add(current);
      for (final b in batches) {
        await b.commit();
      }
      if (mounted)
        _showSnack(
          'Updated $count orders to "$pickupStatus"',
          UpriseColors.success,
        );
    } catch (e) {
      if (mounted) _showSnack('Error: $e', UpriseColors.error);
    } finally {
      if (mounted) setState(() => _isBulkUpdating = false);
    }
  }

  Future<void> _bulkUpdateAll(
    String pickupStatus,
    List<OrderModel> allOrders,
  ) async {
    final count = allOrders.length;
    final confirmed = await _showBulkConfirmDialog(
      title: 'Mark ALL as "$pickupStatus"',
      message:
          'This will update $count order${count == 1 ? '' : 's'} across all sections to "$pickupStatus".',
    );
    if (!confirmed) return;
    setState(() => _isBulkUpdating = true);
    try {
      final db = FirebaseFirestore.instance;
      WriteBatch current = db.batch();
      int opCount = 0;
      final List<WriteBatch> batches = [];
      for (final order in allOrders) {
        current.update(db.collection('orders').doc(order.id), {
          'pickupStatus': pickupStatus,
        });
        opCount++;
        if (opCount >= 500) {
          batches.add(current);
          current = db.batch();
          opCount = 0;
        }
      }
      if (opCount > 0) batches.add(current);
      for (final b in batches) {
        await b.commit();
      }
      if (mounted)
        _showSnack(
          'Updated $count orders to "$pickupStatus"',
          UpriseColors.success,
        );
    } catch (e) {
      if (mounted) _showSnack('Error: $e', UpriseColors.error);
    } finally {
      if (mounted) setState(() => _isBulkUpdating = false);
    }
  }

  Future<bool> _showBulkConfirmDialog({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => Dialog(
            // Was unset — Dialog falls back to Flutter's default Material
            // surface color, which skews purple/lavender on this app's
            // unseeded theme.
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.update_rounded,
                          // Was a stale, more-vivid orange that didn't
                          // match the rest of this file's UpriseColors.
                          // primaryDark modals — same drift bug fixed
                          // elsewhere in the org portal this session.
                          color: UpriseColors.primaryDark,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
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
                        onPressed: () => Navigator.pop(ctx, true),
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
                          'Confirm',
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
          ),
        ) ??
        false;
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.beVietnamPro()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        const SizedBox(height: 16),
        Expanded(child: _buildTable()),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() {
                _searchQuery = value;
                _currentPage = 1;
              }),
              style: GoogleFonts.beVietnamPro(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search orders...',
                hintStyle: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF9AA5B4),
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Color(0xFF9AA5B4),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: UpriseColors.primaryDark,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _FilterDropdown(
            value: _statusFilter,
            items: _statusFilters,
            hint: 'Status',
            icon: Icons.tune_rounded,
            onChanged: (v) => setState(() {
              _statusFilter = v!;
              _currentPage = 1;
            }),
          ),
          const SizedBox(width: 10),
          if (_availableSections.length > 1) ...[
            _FilterDropdown(
              value: _sectionFilter,
              items: _availableSections,
              hint: 'Section',
              icon: Icons.groups_outlined,
              onChanged: (v) => setState(() {
                _sectionFilter = v!;
                _currentPage = 1;
              }),
            ),
            const SizedBox(width: 10),
          ],
          _FilterDropdown(
            value: _pickupStatusFilter,
            items: const ['All', 'Pending', 'Ready for Pickup', 'Claimed'],
            hint: 'Pickup',
            icon: Icons.local_shipping_outlined,
            onChanged: (v) => setState(() {
              _pickupStatusFilter = v!;
              _currentPage = 1;
            }),
          ),
          const SizedBox(width: 10),
          if (_availableBundleIds.length > 1)
            _FilterDropdown(
              value: _bundleIdFilter,
              items: _availableBundleIds,
              hint: 'Bundle',
              icon: Icons.local_offer_outlined,
              onChanged: (v) => setState(() {
                _bundleIdFilter = v!;
                _currentPage = 1;
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return StreamBuilder<QuerySnapshot>(
      stream: _ordersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final rawOrders = snapshot.data!.docs
            .map((d) => OrderModel.fromFirestore(d))
            .toList();
        _updateBundleIds(rawOrders);
        _updateSections(rawOrders);

        final Map<String, List<OrderModel>> sectionGroups = {};
        for (final o in rawOrders) {
          if (o.section.isNotEmpty) {
            sectionGroups.putIfAbsent(o.section, () => []).add(o);
          }
        }
        final sortedSections = sectionGroups.keys.toList()..sort();

        var allOrders = _applyFilters(rawOrders);

        final totalPages = allOrders.isEmpty
            ? 1
            : (allOrders.length / _pageSize).ceil();
        final safePage = _currentPage.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, allOrders.length);
        final pageOrders = allOrders.sublist(start, end);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rawOrders.isNotEmpty) _buildGlobalBulkButtons(rawOrders),
            if (sectionGroups.isNotEmpty)
              _buildSectionBanner(sortedSections, sectionGroups),
            if (rawOrders.isNotEmpty || sectionGroups.isNotEmpty)
              const SizedBox(height: 8),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                  boxShadow: _DS.cardShadow,
                ),
                child: Column(
                  children: [
                    _buildTableHeader(),
                    Expanded(
                      child: allOrders.isEmpty
                          ? _buildEmptyState(
                              Icons.shopping_cart_outlined,
                              'No orders yet',
                              'Orders will appear here after checkout.',
                            )
                          : ListView.builder(
                              itemCount: pageOrders.length,
                              itemBuilder: (_, i) => _buildOrderRow(
                                pageOrders[i],
                                isLast: i == pageOrders.length - 1,
                              ),
                            ),
                    ),
                    _buildFooter(allOrders.length, totalPages, start, end),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGlobalBulkButtons(List<OrderModel> allOrders) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
      child: Row(
        children: [
          Text(
            'Bulk Actions:',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _isBulkUpdating
                ? null
                : () => _bulkUpdateAll('Ready for Pickup', allOrders),
            icon: const Icon(Icons.check_circle_outline, size: 14),
            label: Text(
              'Mark ALL as Ready',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              side: const BorderSide(color: Color(0xFF93C5FD)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _isBulkUpdating
                ? null
                : () => _bulkUpdateAll('Claimed', allOrders),
            icon: const Icon(Icons.done_all_rounded, size: 14),
            label: Text(
              'Mark ALL as Claimed',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF059669),
              side: const BorderSide(color: Color(0xFF6EE7B7)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          if (_isBulkUpdating) ...[
            const SizedBox(width: 12),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              'Updating…',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionBanner(
    List<String> sortedSections,
    Map<String, List<OrderModel>> sectionGroups,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFEF3C7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.groups_outlined,
                size: 15,
                color: Color(0xFFFB923C),
              ),
              const SizedBox(width: 6),
              Text(
                'Section Summary',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFFB923C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...sortedSections.map((section) {
            final orders = sectionGroups[section]!;
            final itemCount = orders.fold<int>(
              0,
              (sum, o) => sum + o.items.fold<int>(0, (s, i) => s + i.quantity),
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: UpriseColors.primaryDark.withAlpha(18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      section,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: UpriseColors.primaryDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${orders.length} order${orders.length == 1 ? '' : 's'} / $itemCount item${itemCount == 1 ? '' : 's'}',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _isBulkUpdating
                        ? null
                        : () => _bulkUpdateSection(
                            section,
                            'Ready for Pickup',
                            orders,
                          ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      backgroundColor: const Color(0xFFEFF6FF),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(
                      'Ready',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: _isBulkUpdating
                        ? null
                        : () => _bulkUpdateSection(section, 'Claimed', orders),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF059669),
                      backgroundColor: const Color(0xFFECFDF5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(
                      'Claimed',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(
          bottom: BorderSide(color: UpriseColors.primaryDark.withAlpha(60)),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: _headerCell('ORDER ID')),
          Expanded(flex: 2, child: _headerCell('CUSTOMER')),
          Expanded(flex: 1, child: _headerCell('SECTION')),
          Expanded(flex: 1, child: _headerCell('DATE')),
          Expanded(flex: 1, child: _headerCell('TOTAL')),
          Expanded(flex: 2, child: _headerCell('PICKUP STATUS')),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerRight,
              child: _headerCell('ACTIONS'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String text) => Text(
    text,
    style: GoogleFonts.beVietnamPro(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF64748B),
      letterSpacing: 0.7,
    ),
  );

  Widget _buildOrderRow(OrderModel order, {required bool isLast}) {
    final date = DateFormat('MMM d, yyyy').format(order.createdAt.toDate());
    return InkWell(
      hoverColor: const Color(0xFFF8F9FB),
      onTap: () => showDialog(
        context: context,
        builder: (_) => _OrderDetailsModal(order: order),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                order.orderId,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: UpriseColors.primaryDark,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.customerName,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                  Text(
                    order.customerEmail,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: order.section.isEmpty
                  ? Text(
                      '—',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFF9AA5B4),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: UpriseColors.primaryDark.withAlpha(18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        order.section,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: UpriseColors.primaryDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                date,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₱${NumberFormat('#,###.00').format(order.total)}',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: UpriseColors.primaryDark,
                    ),
                  ),
                  if (order.paymentMethod == 'GCash')
                    Text(
                      order.paymentVerified
                          ? 'GCash · Verified'
                          : 'GCash · Unverified',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: order.paymentVerified
                            ? UpriseColors.success
                            : const Color(0xFFD97706),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(flex: 2, child: _pickupStatusBadge(order.pickupStatus)),
            Expanded(
              flex: 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OrgActionIconButton(
                    icon: Icons.visibility_outlined,
                    tooltip: 'View Details',
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => _OrderDetailsModal(order: order),
                    ),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    tooltip: 'Update Pickup Status',
                    onSelected: (value) =>
                        _updateOrderPickupStatus(order.id, value),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'Pending',
                        child: Text(
                          'Pending',
                          style: GoogleFonts.beVietnamPro(fontSize: 13),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'Ready for Pickup',
                        child: Text(
                          'Ready for Pickup',
                          style: GoogleFonts.beVietnamPro(fontSize: 13),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'Claimed',
                        child: Text(
                          'Claimed',
                          style: GoogleFonts.beVietnamPro(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickupStatusBadge(String status) {
    final Color bg, fg;
    final String label;
    switch (status) {
      case 'Ready for Pickup':
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF2563EB);
        label = 'READY';
        break;
      case 'Claimed':
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF059669);
        label = 'CLAIMED';
        break;
      default:
        bg = const Color(0xFFFFFBEB);
        fg = const Color(0xFFFB923C);
        label = 'PENDING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(_DS.radiusPill),
      ),
      child: Text(
        label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildFooter(int total, int totalPages, int start, int end) {
    const int maxVisible = 5;
    int firstPage = (_currentPage - maxVisible ~/ 2).clamp(1, totalPages);
    int lastPage = (firstPage + maxVisible - 1).clamp(1, totalPages);
    if (lastPage - firstPage + 1 < maxVisible && firstPage > 1) {
      firstPage = (lastPage - maxVisible + 1).clamp(1, totalPages);
    }
    final pages = List.generate(lastPage - firstPage + 1, (i) => firstPage + i);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
        color: Color(0xFFF8F9FB),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${total == 0 ? 0 : start + 1}–$end of $total orders',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          Row(
            children: [
              _PageButton(
                icon: Icons.chevron_left_rounded,
                enabled: _currentPage > 1,
                tooltip: 'Previous Page',
                onTap: () => setState(() => _currentPage--),
              ),
              const SizedBox(width: 4),
              ...pages.map(
                (p) => _PageNumButton(
                  page: p,
                  isActive: p == _currentPage,
                  onTap: () => setState(() => _currentPage = p),
                ),
              ),
              if (lastPage < totalPages) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '…',
                    style: GoogleFonts.beVietnamPro(
                      color: const Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ),
                _PageNumButton(
                  page: totalPages,
                  isActive: _currentPage == totalPages,
                  onTap: () => setState(() => _currentPage = totalPages),
                ),
              ],
              const SizedBox(width: 4),
              _PageButton(
                icon: Icons.chevron_right_rounded,
                enabled: _currentPage < totalPages,
                tooltip: 'Next Page',
                onTap: () => setState(() => _currentPage++),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 40, color: const Color(0xFF9AA5B4)),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E6EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // [icon] used to be accepted but never actually rendered —
            // Category and Status looked identical at a glance.
            Icon(icon, size: 15, color: const Color(0xFF9AA5B4)),
            const SizedBox(width: 8),
            Text(
              value,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF374151),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: Color(0xFF9AA5B4),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String? tooltip;
  const _PageButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? const Color(0xFF374151) : const Color(0xFFD1D5DB),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: button,
    );
  }
}

class _PageNumButton extends StatelessWidget {
  final int page;
  final bool isActive;
  final VoidCallback onTap;
  const _PageNumButton({
    required this.page,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? UpriseColors.primaryDark : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$page',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
              color: isActive ? Colors.white : const Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ORDER DETAILS MODAL
// ============================================================
class _OrderDetailsModal extends StatefulWidget {
  final OrderModel order;
  const _OrderDetailsModal({required this.order});

  @override
  State<_OrderDetailsModal> createState() => _OrderDetailsModalState();
}

class _OrderDetailsModalState extends State<_OrderDetailsModal> {
  bool _verifying = false;
  late bool _paymentVerified = widget.order.paymentVerified;

  OrderModel get order => widget.order;

  Future<void> _markPaymentVerified() async {
    setState(() => _verifying = true);
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(order.id)
          .update({'paymentVerified': true});
      await activity_log.ActivityLogger.log(
        action: 'verify_gcash_payment',
        module: 'merchandise',
        details: {'orgId': order.orgId, 'orderId': order.orderId},
      );
      if (mounted) setState(() => _paymentVerified = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: UpriseColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _viewProof() {
    final raw = order.gcashProofBase64;
    if (raw.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        // Explicit, not just unset — this is a bare image viewer with no
        // card chrome around it, so it should be transparent on purpose
        // (matching the same pattern elsewhere in the app), not fall back
        // to Flutter's default Material surface color, which would show
        // as a purple/lavender edge around the image on this app's
        // unseeded theme.
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            base64Decode(raw.contains(',') ? raw.split(',').last : raw),
            fit: BoxFit.contain,
          ),
        ),
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
        width: 520,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FB),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: UpriseColors.primaryDark.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.receipt_outlined,
                      size: 18,
                      color: UpriseColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Order Details',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Color(0xFF64748B),
                    ),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order ID: ${order.orderId}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle('Customer Information'),
                    const SizedBox(height: 8),
                    _infoRow(Icons.person_outline, order.customerName),
                    _infoRow(Icons.email_outlined, order.customerEmail),
                    _infoRow(Icons.phone_outlined, order.customerPhone),
                    if (order.customerAddress.isNotEmpty)
                      _infoRow(
                        Icons.location_on_outlined,
                        order.customerAddress,
                      ),
                    const SizedBox(height: 16),
                    _sectionTitle('Order Items'),
                    const SizedBox(height: 8),
                    ...order.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _itemThumbnail(item.imageBase64),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '₱${NumberFormat('#,###').format(item.price)} each',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 11,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Qty: ${item.quantity}',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 11,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  '₱${NumberFormat('#,###.00').format(item.totalPrice)}',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: UpriseColors.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle('Order Summary'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E6EA)),
                      ),
                      child: Column(
                        children: [
                          _summaryLine(
                            'Subtotal',
                            '₱${NumberFormat('#,###.00').format(order.total)}',
                          ),
                          const SizedBox(height: 4),
                          _summaryLine('Payment Method', order.paymentMethod),
                          if (order.paymentMethod == 'GCash') ...[
                            const SizedBox(height: 4),
                            _summaryLine(
                              'GCash Reference No.',
                              order.gcashReferenceNumber.isNotEmpty
                                  ? order.gcashReferenceNumber
                                  : '—',
                            ),
                            const SizedBox(height: 4),
                            _summaryLine(
                              'Payment Status',
                              _paymentVerified
                                  ? 'Verified'
                                  : 'Awaiting Verification',
                              valueColor: _paymentVerified
                                  ? UpriseColors.success
                                  : const Color(0xFFD97706),
                            ),
                            if (order.gcashProofBase64.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: _viewProof,
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.image_outlined,
                                      size: 15,
                                      color: UpriseColors.primaryDark,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'View payment screenshot',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: UpriseColors.primaryDark,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Divider(
                              color: const Color(0xFFE2E6EA),
                              height: 1,
                            ),
                          ),
                          _summaryLine(
                            'Total Amount',
                            '₱${NumberFormat('#,###.00').format(order.total)}',
                            bold: true,
                            valueColor: UpriseColors.primaryDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _sectionTitle('Order Timeline'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule,
                          size: 14,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Order placed: ${DateFormat('MMM d, yyyy h:mm a').format(order.createdAt.toDate())}',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
                color: Color(0xFFF8F9FB),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (order.paymentMethod == 'GCash' && !_paymentVerified) ...[
                    ElevatedButton.icon(
                      onPressed: _verifying ? null : _markPaymentVerified,
                      icon: _verifying
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline, size: 16),
                      label: Text(
                        'Mark Payment Verified',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: UpriseColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE2E6EA)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    child: Text(
                      'Close',
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemThumbnail(String imageBase64) {
    if (imageBase64.isNotEmpty) {
      try {
        final raw = imageBase64.contains(',')
            ? imageBase64.split(',').last
            : imageBase64;
        return Image.memory(
          base64Decode(raw),
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          cacheWidth: 80,
          cacheHeight: 80,
          errorBuilder: (_, __, ___) => _itemThumbnailFallback(),
        );
      } catch (_) {
        return _itemThumbnailFallback();
      }
    }
    return _itemThumbnailFallback();
  }

  Widget _itemThumbnailFallback() => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: UpriseColors.primaryDark.withAlpha(20),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(
      Icons.shopping_bag_outlined,
      size: 20,
      color: UpriseColors.primaryDark,
    ),
  );

  Widget _sectionTitle(String text) => Text(
    text,
    style: GoogleFonts.beVietnamPro(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF1A202C),
    ),
  );
  Widget _infoRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: GoogleFonts.beVietnamPro(fontSize: 12)),
        ),
      ],
    ),
  );
  Widget _summaryLine(
    String label,
    String value, {
    bool bold = false,
    Color? valueColor,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
      Text(
        value,
        style: GoogleFonts.beVietnamPro(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: valueColor,
        ),
      ),
    ],
  );
}

// ============================================================
// SALES REPORT MODAL
// ============================================================
class _SalesReportModal extends StatelessWidget {
  final String orgId;
  const _SalesReportModal({required this.orgId});

  void _exportReport(BuildContext context, List<OrderModel> orders) {
    final buf = StringBuffer();
    buf.writeln('MERCHANDISE SALES REPORT');
    buf.writeln(
      'Generated: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}\n',
    );
    buf.writeln('Order ID,Customer,Total,Status,Date,Bundle ID');
    for (final o in orders) {
      final date = DateFormat('MM/dd/yyyy').format(o.createdAt.toDate());
      buf.writeln(
        '"${o.orderId}","${o.customerName}","${o.total.toStringAsFixed(2)}","${o.status}","$date","${o.bundleId}"',
      );
    }
    final bytes = utf8.encode(buf.toString());
    final blob = html.Blob([bytes], 'text/csv');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute(
        'download',
        'sales_report_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
      )
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _exportReportPdf(
    BuildContext context,
    List<OrderModel> orders,
  ) async {
    try {
      String orgName = 'Organization';
      String orgLogoUrl = '';
      final orgDoc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(orgId)
          .get();
      if (orgDoc.exists) {
        orgName = orgDoc.data()?['name'] ?? orgName;
        orgLogoUrl = orgDoc.data()?['logoUrl'] ?? '';
      }

      final headers = [
        'Order ID',
        'Customer',
        'Items',
        'Total',
        'Status',
        'Date',
      ];
      final rows = orders.map((o) {
        final itemsSummary = o.items
            .map((it) => '${it.quantity}× ${it.name}')
            .join(', ');
        return [
          o.orderId,
          o.customerName,
          itemsSummary,
          '₱${o.total.toStringAsFixed(2)}',
          o.status,
          DateFormat('MM/dd/yyyy').format(o.createdAt.toDate()),
        ];
      }).toList();

      final pdfBytes = await OrgExportPdf.generateTablePdf(
        title: 'Merchandise Sales Report',
        subtitle: '$orgName - Merchandise Performance',
        headers: headers,
        rows: rows,
        orgLogoUrl: orgLogoUrl,
      );
      await OrgExportUtil.saveBytes(
        pdfBytes,
        'sales_report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
        mimeType: 'application/pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF export failed: $e'),
            backgroundColor: UpriseColors.error,
          ),
        );
      }
    }
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
        width: 720,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('products')
              .where('orgId', isEqualTo: orgId)
              .snapshots(),
          builder: (context, productSnap) {
            final Map<String, double> costByProductId = {};
            for (final doc in productSnap.data?.docs ?? []) {
              final d = doc.data() as Map<String, dynamic>;
              costByProductId[doc.id] = (d['costPrice'] ?? 0).toDouble();
            }
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('orders')
                  .where('orgId', isEqualTo: orgId)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                final orders = snapshot.hasData
                    ? snapshot.data!.docs
                          .map((d) => OrderModel.fromFirestore(d))
                          .toList()
                    : <OrderModel>[];

                double totalRevenue = 0;
                int completed = 0, processing = 0;
                for (final o in orders) {
                  totalRevenue += o.total;
                  if (o.status.toLowerCase() == 'completed') completed++;
                  if (o.status.toLowerCase() == 'processing') processing++;
                }

                final Map<String, double> monthly = {};
                for (final o in orders) {
                  final m = DateFormat('yyyy-MM').format(o.createdAt.toDate());
                  monthly[m] = (monthly[m] ?? 0) + o.total;
                }
                final months = monthly.keys.toList()..sort();

                final Map<String, int> unitsSold = {};
                final Map<String, double> revByProduct = {};
                final Map<String, double> profitByProduct = {};
                double totalProfit = 0;
                for (final o in orders) {
                  for (final item in o.items) {
                    unitsSold[item.name] =
                        (unitsSold[item.name] ?? 0) + item.quantity;
                    revByProduct[item.name] =
                        (revByProduct[item.name] ?? 0) + item.totalPrice;
                    final cost = costByProductId[item.productId] ?? 0;
                    final itemProfit = (item.price - cost) * item.quantity;
                    profitByProduct[item.name] =
                        (profitByProduct[item.name] ?? 0) + itemProfit;
                    totalProfit += itemProfit;
                  }
                }
                final top5 =
                    (unitsSold.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value)))
                        .take(5)
                        .toList();

                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8F9FB),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                      ),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sales Report',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Merchandise Performance',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: orders.isEmpty
                                ? null
                                : () => _exportReport(context, orders),
                            icon: const Icon(Icons.download_outlined, size: 15),
                            label: Text(
                              'Export CSV',
                              style: GoogleFonts.beVietnamPro(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: UpriseColors.primaryDark,
                              side: BorderSide(color: UpriseColors.primaryDark),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: orders.isEmpty
                                ? null
                                : () => _exportReportPdf(context, orders),
                            icon: const Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 15,
                            ),
                            label: Text(
                              'Export PDF',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: Color(0xFF64748B),
                            ),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('Overview'),
                            const SizedBox(height: 10),
                            // Two cards, not five. The three count-only
                            // stats (sales, completed, processing) say more
                            // as one text line than as three more bordered
                            // boxes; the two the original already marked as
                            // highlighted are the money figures, so those
                            // are the ones that stay as cards.
                            StatCardsRow(
                              isMobile: false,
                              gap: 12,
                              cards: [
                                StatCard(
                                  label: 'Total Revenue',
                                  value:
                                      '₱${NumberFormat('#,###').format(totalRevenue)}',
                                  icon: Icons.payments_outlined,
                                  color: UpriseColors.primaryDark,
                                ),
                                StatCard(
                                  label: 'Total Profit',
                                  value:
                                      '₱${NumberFormat('#,###').format(totalProfit)}',
                                  icon: Icons.trending_up_rounded,
                                  color: UpriseColors.success,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            StatStrip(
                              items: [
                                StatStripItem.count(
                                  label: 'Total sales',
                                  count: orders.length,
                                ),
                                StatStripItem.count(
                                  label: 'Completed',
                                  count: completed,
                                ),
                                StatStripItem.count(
                                  label: 'Processing',
                                  count: processing,
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _sectionTitle('Monthly Revenue'),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 180,
                              child: months.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No data yet',
                                        style: GoogleFonts.beVietnamPro(
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                    )
                                  : BarChart(
                                      BarChartData(
                                        alignment:
                                            BarChartAlignment.spaceAround,
                                        maxY:
                                            monthly.values.reduce(
                                              (a, b) => a > b ? a : b,
                                            ) *
                                            1.2,
                                        barGroups: months
                                            .asMap()
                                            .entries
                                            .map(
                                              (e) => BarChartGroupData(
                                                x: e.key,
                                                barRods: [
                                                  BarChartRodData(
                                                    toY: monthly[e.value] ?? 0,
                                                    color: UpriseColors
                                                        .primaryDark,
                                                    width: 20,
                                                    borderRadius:
                                                        const BorderRadius.vertical(
                                                          top: Radius.circular(
                                                            4,
                                                          ),
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            )
                                            .toList(),
                                        titlesData: FlTitlesData(
                                          bottomTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              getTitlesWidget: (v, m) {
                                                final i = v.toInt();
                                                if (i >= 0 && i < months.length)
                                                  return Text(
                                                    DateFormat('MMM').format(
                                                      DateTime.parse(
                                                        '${months[i]}-01',
                                                      ),
                                                    ),
                                                    style:
                                                        GoogleFonts.beVietnamPro(
                                                          fontSize: 10,
                                                        ),
                                                  );
                                                return const Text('');
                                              },
                                            ),
                                          ),
                                          leftTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              reservedSize: 48,
                                              getTitlesWidget: (v, m) => Text(
                                                '₱${NumberFormat.compact().format(v)}',
                                                style: GoogleFonts.beVietnamPro(
                                                  fontSize: 9,
                                                  color: const Color(
                                                    0xFF64748B,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          topTitles: const AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ),
                                          rightTitles: const AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ),
                                        ),
                                        gridData: FlGridData(
                                          show: true,
                                          drawVerticalLine: false,
                                          getDrawingHorizontalLine: (v) =>
                                              FlLine(
                                                color: const Color(0xFFE2E6EA),
                                                strokeWidth: 0.8,
                                              ),
                                        ),
                                        borderData: FlBorderData(show: false),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 20),
                            _sectionTitle('Popular Items'),
                            const SizedBox(height: 10),
                            if (top5.isEmpty)
                              Text(
                                'No product sales yet',
                                style: GoogleFonts.beVietnamPro(
                                  color: const Color(0xFF64748B),
                                  fontSize: 12,
                                ),
                              )
                            else
                              ...top5.map((entry) {
                                final rev = revByProduct[entry.key] ?? 0;
                                final profit = profitByProduct[entry.key] ?? 0;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: UpriseColors.primaryDark
                                              .withAlpha(20),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.shopping_bag_outlined,
                                          size: 18,
                                          color: UpriseColors.primaryDark,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              entry.key,
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              '${entry.value} units sold',
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 11,
                                                color: const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: UpriseColors.primaryDark
                                                  .withAlpha(20),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '₱${NumberFormat('#,###').format(rev)}',
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: UpriseColors.primaryDark,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: UpriseColors.success
                                                  .withAlpha(26),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              'Profit ₱${NumberFormat('#,###').format(profit)}',
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: UpriseColors.success,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFE8ECF0)),
                        ),
                        color: Color(0xFFF8F9FB),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(18),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: UpriseColors.primaryDark,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                            ),
                            child: Text(
                              'Done',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: GoogleFonts.beVietnamPro(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF1A202C),
    ),
  );
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
    );
  }

  // Falls back to the single main photo when no dedicated photo set was
  // uploaded, so the gallery always has at least one image to show.
  List<String> get displayPhotos => rotationPhotos.isNotEmpty
      ? rotationPhotos
      : (imageBase64 != null && imageBase64!.isNotEmpty ? [imageBase64!] : []);
}

class OrderItem {
  final String productId;
  final String name;
  final int quantity;
  final double price;
  final double totalPrice;
  final String imageBase64;

  OrderItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.price,
    required this.totalPrice,
    this.imageBase64 = '',
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
    productId: map['productId'] ?? '',
    name: map['name'] ?? '',
    quantity: map['quantity'] ?? 0,
    price: (map['price'] ?? 0).toDouble(),
    totalPrice: (map['totalPrice'] ?? 0).toDouble(),
    imageBase64: map['imageBase64'] ?? '',
  );
}

class OrderModel {
  final String id;
  final String orderId;
  final String orgId;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final String customerAddress;
  final List<OrderItem> items;
  final double total;
  final String paymentMethod;
  final String status;
  final Timestamp createdAt;
  final String bundleId;
  final String section;
  final String pickupStatus;
  final String gcashReferenceNumber;
  final String gcashProofBase64;
  final String gcashProofFormat;
  final bool paymentVerified;

  OrderModel({
    required this.id,
    required this.orderId,
    required this.orgId,
    required this.customerName,
    required this.customerEmail,
    required this.customerPhone,
    required this.customerAddress,
    required this.items,
    required this.total,
    required this.paymentMethod,
    required this.status,
    required this.createdAt,
    required this.bundleId,
    this.section = '',
    this.pickupStatus = 'Pending',
    this.gcashReferenceNumber = '',
    this.gcashProofBase64 = '',
    this.gcashProofFormat = '',
    this.paymentVerified = false,
  });

  factory OrderModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawItems = (d['items'] as List?) ?? [];
    return OrderModel(
      id: doc.id,
      orderId: d['orderId'] ?? 'ORD-${doc.id.substring(0, 6).toUpperCase()}',
      orgId: d['orgId'] ?? '',
      customerName: d['customerName'] ?? '',
      customerEmail: d['customerEmail'] ?? '',
      customerPhone: d['customerPhone'] ?? '',
      customerAddress: d['customerAddress'] ?? '',
      items: rawItems
          .map((i) => OrderItem.fromMap(i as Map<String, dynamic>))
          .toList(),
      total: (d['total'] ?? 0).toDouble(),
      paymentMethod: d['paymentMethod'] ?? '',
      status: d['status'] ?? 'pending',
      createdAt: d['createdAt'] as Timestamp,
      bundleId: d['bundleId'] ?? '',
      section: d['section'] ?? '',
      pickupStatus: d['pickupStatus'] ?? 'Pending',
      gcashReferenceNumber: d['gcashReferenceNumber'] ?? '',
      gcashProofBase64: d['gcashProofBase64'] ?? '',
      gcashProofFormat: d['gcashProofFormat'] ?? '',
      paymentVerified: d['paymentVerified'] as bool? ?? false,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// GCash Settings Dialog
// ─────────────────────────────────────────────────────────────
class _GcashSettingsDialog extends StatefulWidget {
  final String orgId;
  const _GcashSettingsDialog({required this.orgId});

  @override
  State<_GcashSettingsDialog> createState() => _GcashSettingsDialogState();
}

class _GcashSettingsDialogState extends State<_GcashSettingsDialog> {
  final _numberCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadGcashInfo();
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGcashInfo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        setState(() {
          _numberCtrl.text = data['gcashNumber'] as String? ?? '';
          _nameCtrl.text = data['gcashName'] as String? ?? '';
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveGcashInfo() async {
    final number = _numberCtrl.text.trim();
    if (number.isEmpty) {
      _showSnack('Please enter a GCash number.');
      return;
    }
    if (!RegExp(r'^09\d{9}$').hasMatch(number)) {
      _showSnack('Enter a valid 11-digit GCash number (e.g., 09171234567).');
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      _showSnack('Please enter the GCash account name.');
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .update({
            'gcashNumber': _numberCtrl.text.trim(),
            'gcashName': _nameCtrl.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      if (mounted) {
        _showSnack('GCash settings saved successfully!', isSuccess: true);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.beVietnamPro()),
        backgroundColor: isSuccess ? UpriseColors.success : UpriseColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        width: 480,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: UpriseColors.primaryDark.withAlpha(18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: UpriseColors.primaryDark,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'GCash Payment Settings',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Close',
                  onPressed: _saving ? null : () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the GCash account details that students will pay to.',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              TextFormField(
                controller: _numberCtrl,
                decoration: _DS.inputDecoration(
                  'GCash Number',
                  hint: 'e.g., 09171234567',
                  icon: Icons.phone_android_outlined,
                ),
                style: GoogleFonts.beVietnamPro(fontSize: 13),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: _DS.inputDecoration(
                  'GCash Account Name',
                  hint: 'e.g., Juan Dela Cruz',
                  icon: Icons.person_outline_rounded,
                ),
                style: GoogleFonts.beVietnamPro(fontSize: 13),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE2E6EA)),
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
                      style: GoogleFonts.beVietnamPro(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _saveGcashInfo,
                    icon: _saving
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
                      _saving ? 'Saving...' : 'Save Settings',
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
