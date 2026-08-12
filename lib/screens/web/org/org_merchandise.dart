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
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/product_photo_gallery.dart';
import '../../../widgets/org_action_icon_button.dart';
import '../admin/export_util.dart';
import '../admin/export_pdf.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (mirrors student accounts)
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const double radiusSm = 8;
  static const double radiusPill = 100;

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
      prefixIcon: icon != null
          ? Icon(icon, size: 18, color: const Color(0xFF9AA5B4))
          : null,
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

// A fixed color per known category (falls back to a hash-based pick from
// the same palette for custom "Others" text) so the catalog reads more
// like a tagged shop than a flat list — each category is recognizable by
// color at a glance, not just by its label.
const Map<String, Color> _categoryColors = {
  'T-Shirts / Uniforms': Color(0xFF2563EB),
  'Lanyards / IDs': Color(0xFF7C3AED),
  'Stickers / Pins': Color(0xFFDB2777),
  'Tumblers / Water Bottles': Color(0xFF0D9488),
  'Notebooks / Planners': Color(0xFFB45309),
};
const List<Color> _fallbackCategoryColors = [
  Color(0xFF2563EB),
  Color(0xFF7C3AED),
  Color(0xFFDB2777),
  Color(0xFF0D9488),
  Color(0xFFB45309),
  Color(0xFF059669),
];

Color _categoryColor(String category) {
  final known = _categoryColors[category];
  if (known != null) return known;
  return _fallbackCategoryColors[category.hashCode.abs() %
      _fallbackCategoryColors.length];
}

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
  late final TabController _tabController;
  late final Stream<QuerySnapshot> _productsStream = FirebaseFirestore.instance
      .collection('products')
      .where('orgId', isEqualTo: widget.orgId)
      .where('isArchived', isEqualTo: false)
      .snapshots();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
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
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(isMobile),
          const SizedBox(height: 14),
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

  Widget _buildHeader(bool isMobile) {
    return StreamBuilder<QuerySnapshot>(
      stream: _productsStream,
      builder: (context, snapshot) {
        final products = snapshot.data?.docs ?? [];
        final totalProducts = products.length;
        final availableProducts = products.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final stock = d['stock'];
          return stock is num && stock > 0;
        }).length;

        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1E8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: Color(0xFFC9480A),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 11),
                Text(
                  'Official Merchandise',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: isMobile ? 20 : 22,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF172033),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              'Showcase your organization\'s official merchandise and promotional items.',
              style: GoogleFonts.beVietnamPro(
                fontSize: 11.5,
                color: const Color(0xFF64748B),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InlineStat(
                  icon: Icons.shopping_bag_outlined,
                  text: '$totalProducts item${totalProducts == 1 ? '' : 's'}',
                  color: UpriseColors.info,
                ),
                _InlineStat(
                  icon: Icons.check_circle_outline_rounded,
                  text: '$availableProducts available',
                  color: UpriseColors.success,
                ),
              ],
            ),
          ],
        );

        final actions = Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            AdminExportButton(
              onSelected: _exportProducts,
            ),
            ElevatedButton.icon(
              onPressed: () => _openAddProductModal(context),
              icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
              label: Text(
                'Add Merchandise',
                style: GoogleFonts.beVietnamPro(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: UpriseColors.primaryDark,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        );

        return Container(
          width: double.infinity,
          margin: EdgeInsets.fromLTRB(
            isMobile ? 14 : 24,
            isMobile ? 14 : 22,
            isMobile ? 14 : 24,
            0,
          ),
          padding: EdgeInsets.fromLTRB(
            isMobile ? 16 : 24,
            isMobile ? 17 : 22,
            isMobile ? 16 : 24,
            isMobile ? 17 : 22,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE7ECF2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(7),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: 17),
                    actions,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 20),
                    actions,
                  ],
                ),
        );
      },
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
      _showSnack('No merchandise to export', UpriseColors.warning);
      return;
    }

    final now = DateFormat('yyyyMMdd').format(DateTime.now());
    if (format == 'csv') {
      final buf = StringBuffer();
      buf.writeln('Product Name,Category,Price,Stock,Sold');
      for (final doc in docs) {
        final d = doc.data();
        buf.writeln(
          '"${d['name'] ?? ''}","${d['category'] ?? ''}","${d['price'] ?? 0}","${d['stock'] ?? 0}","${d['sold'] ?? 0}"',
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
          '${d['name'] ?? ''}',
          '${d['category'] ?? ''}',
          '${d['price'] ?? 0}',
          '${d['stock'] ?? 0}',
          '${d['sold'] ?? 0}',
        ];
      }).toList();

      final pdfBytes = await AdminExportPdf.generateTablePdf(
        title: 'Merchandise Catalog',
        headers: const ['Name', 'Category', 'Price', 'Stock', 'Sold'],
        rows: rows,
      );
      await AdminExportUtil.saveBytes(
        pdfBytes,
        'products_$now.pdf',
        mimeType: 'application/pdf',
      );
    }

    _showSnack('Merchandise exported', UpriseColors.success);
  }

  void _openAddProductModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProductModal(
        orgId: widget.orgId,
        onProductSaved: () => setState(() {}),
      ),
    );
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.beVietnamPro()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
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
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        // Stream will automatically update via Firestore listener
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
        const SizedBox(height: 12),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 28),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Browse your organization's merchandise collection",
              style: GoogleFonts.beVietnamPro(
                fontSize: 11.5,
                color: const Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .where('orgId', isEqualTo: widget.orgId)
                .where('isArchived', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error}', style: GoogleFonts.beVietnamPro()),
                );
              }
              
              final docs = snapshot.data?.docs ?? [];
              final products = docs.map((d) => ProductModel.fromFirestore(d)).toList();
              
              if (products.isEmpty) {
                return _buildEmptyState(
                  Icons.inventory_2_outlined,
                  'No merchandise found',
                  'Add your first item to start your merchandise showcase.',
                );
              }
              
              return _buildGridView(products, isMobile);
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildGridView(List<ProductModel> products, bool isMobile) {
    return GridView.builder(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 28),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: isMobile ? 480 : 280,
        crossAxisSpacing: 20,
        mainAxisSpacing: 28,
        childAspectRatio: 0.68,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        return _ProductCard(
          product: products[index],
          alwaysShowActions: isMobile,
          onTap: () => showDialog(
            context: context,
            builder: (_) => _ProductDetailsModal(product: products[index]),
          ),
          onArchive: () => _archiveProduct(products[index]),
          onEdit: () => showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => _ProductModal(
              orgId: widget.orgId,
              existingProduct: products[index],
              onProductSaved: () {
                // Refresh will happen via stream update
              },
            ),
          ),
        );
      },
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
                      },
                    ),
                  ),
                ],
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
                },
              ),
              const Spacer(),
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

  Widget _buildEmptyState(IconData icon, String message, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  UpriseColors.primaryDark.withAlpha(22),
                  const Color(0xFFF59E0B).withAlpha(18),
                ],
              ),
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
            message,
            style: GoogleFonts.beVietnamPro(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A202C),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
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
    final safeValue = items.contains(value) ? value : items.first;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E6EA)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: GoogleFonts.beVietnamPro(
            fontSize: 12.5,
            color: const Color(0xFF334155),
            fontWeight: FontWeight.w500,
          ),
          hint: Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
              const SizedBox(width: 7),
              Text(hint),
            ],
          ),
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Row(
                    children: [
                      Icon(icon, size: 15, color: const Color(0xFF94A3B8)),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          item,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
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
    if (oldWidget.product.imageBase64 != widget.product.imageBase64) {
      _decodeImage();
    }
  }

  void _decodeImage() {
    final b64 = widget.product.imageBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        _decodedImage = base64Decode(b64);
        return;
      } catch (_) {}
    }
    _decodedImage = null;
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final categoryColor = _categoryColor(product.category);
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
    final statusColor = (isOutOfStock || isDiscontinued)
        ? const Color(0xFFDC2626)
        : UpriseColors.primaryDark;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
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
                      if (statusLabel != null)
                        Positioned(
                          left: 10,
                          top: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(235),
                              borderRadius: BorderRadius.circular(
                                _DS.radiusPill,
                              ),
                            ),
                            child: Text(
                              statusLabel.toUpperCase(),
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
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
                                  icon: Icons.archive_outlined,
                                  tooltip: 'Archive',
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: categoryColor.withAlpha(24),
                borderRadius: BorderRadius.circular(_DS.radiusPill),
              ),
              child: Text(
                product.category,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: categoryColor,
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
                    color: UpriseColors.primaryDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    totalStock > 0 ? '$totalStock available' : 'Currently unavailable',
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            UpriseColors.primaryDark.withAlpha(14),
            const Color(0xFFF8F9FB),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 30,
            color: UpriseColors.primaryDark.withAlpha(130),
          ),
          const SizedBox(height: 6),
          Text(
            'No photo',
            style: GoogleFonts.beVietnamPro(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: UpriseColors.primaryDark.withAlpha(150),
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
      if (p.imageBase64 != null && p.imageBase64!.isNotEmpty) {
        try {
          _imageBytes = base64Decode(p.imageBase64!);
        } catch (_) {
          _imageBytes = null;
        }
      }

      // ── LOAD EXISTING ROTATION PHOTOS ──
      for (final photo in p.rotationPhotos) {
        try {
          _rotationPhotoBytes.add(base64Decode(photo));
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
                          base64Decode(existingBase64),
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

  Widget _sectionLabel(String text, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: UpriseColors.darkGray),
            const SizedBox(width: 8),
          ],
          Text(
            text,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: UpriseColors.charcoal,
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
    final photos = product.displayPhotos;
    final productId = 'PRD-${product.id.substring(0, 4).toUpperCase()}';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 620,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 18, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    UpriseColors.primaryDark.withAlpha(24),
                    Colors.white,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: const Border(
                  bottom: BorderSide(color: Color(0xFFEEF0F3)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: UpriseColors.primaryDark.withAlpha(28),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.storefront_outlined,
                      color: UpriseColors.primaryDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Merchandise Details',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product.name,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A202C),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(product.status),
                  const SizedBox(width: 2),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(context),
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
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 390),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: photos.isNotEmpty
                              ? ProductPhotoGallery(
                                  photosBase64: photos,
                                  height: 270,
                                )
                              : _buildNetworkImage(),
                        ),
                      ),
                    ),
                    if (photos.length > 1) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Swipe or drag to view other product angles',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 10.5,
                            color: const Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _categoryColor(product.category).withAlpha(22),
                                  borderRadius: BorderRadius.circular(_DS.radiusPill),
                                ),
                                child: Text(
                                  product.category,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _categoryColor(product.category),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                product.name,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1A202C),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Text(
                          '₱${NumberFormat('#,###.##').format(product.price)}',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: UpriseColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                    if (product.description.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        product.description,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: const Color(0xFF475569),
                          height: 1.55,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _detailCard(
                            'Availability',
                            totalStock > 0 ? '$totalStock units available' : 'Currently unavailable',
                            Icons.inventory_2_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _detailCard(
                            'Status',
                            product.status == 'available'
                                ? 'Available'
                                : product.status.replaceAll('_', ' '),
                            Icons.verified_outlined,
                          ),
                        ),
                      ],
                    ),
                    if (product.variants.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _sectionTitle('Available Variants', Icons.tune_rounded),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE8ECF0)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF8F9FB),
                                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
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
                                      : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(flex: 2, child: _variantValue(v.size.isEmpty ? '—' : v.size)),
                                    Expanded(flex: 2, child: _variantValue(v.color.isEmpty ? '—' : v.color)),
                                    Expanded(flex: 1, child: _variantValue('${v.stock}')),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '₱${NumberFormat('#,###.##').format(effectivePrice)}',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: UpriseColors.primaryDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text(
                        'Inventory History',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF334155),
                        ),
                      ),
                      leading: Icon(Icons.history_rounded, size: 18, color: UpriseColors.primaryDark),
                      children: [
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
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            final logs = snap.data?.docs ?? [];
                            if (logs.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'No stock changes recorded yet.',
                                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: const Color(0xFF94A3B8)),
                                  ),
                                ),
                              );
                            }
                            return Column(
                              children: logs.map((doc) {
                                final d = doc.data() as Map<String, dynamic>;
                                final ts = d['timestamp'] as Timestamp?;
                                final date = ts != null
                                    ? DateFormat('MMM d, yyyy h:mm a').format(ts.toDate())
                                    : '—';
                                final oldS = d['oldStock'] ?? 0;
                                final newS = d['newStock'] ?? 0;
                                final reason = (d['reason'] ?? '').toString();
                                final by = d['changedBy'] ?? '—';
                                final isIncrease = newS > oldS;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8F9FB),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isIncrease ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                        size: 16,
                                        color: isIncrease ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '$oldS → $newS units · $reason · $date · $by',
                                          style: GoogleFonts.beVietnamPro(fontSize: 10.5, color: const Color(0xFF64748B)),
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
                    // Keep the existing product ID available to organization users,
                    // but visually de-emphasize it as administrative metadata.
                    const SizedBox(height: 10),
                    Text(
                      productId,
                      style: GoogleFonts.beVietnamPro(fontSize: 9.5, color: const Color(0xFFCBD5E1)),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
                color: Color(0xFFF8F9FB),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Close', style: GoogleFonts.beVietnamPro(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkImage() {
    if (product.imageUrl.isNotEmpty) {
      return Container(
        height: 270,
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          product.imageUrl,
          width: double.infinity,
          height: 270,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _NoPhotoPlaceholder(),
        ),
      );
    }
    return const _NoPhotoPlaceholder();
  }

  Widget _detailCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: UpriseColors.primaryDark),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.beVietnamPro(fontSize: 10, color: const Color(0xFF94A3B8))),
                const SizedBox(height: 3),
                Text(value, style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 17, color: UpriseColors.primaryDark),
        const SizedBox(width: 7),
        Text(title, style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
      ],
    );
  }

  Widget _variantHeader(String text) => Text(
        text,
        style: GoogleFonts.beVietnamPro(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
      );

  Widget _variantValue(String text) => Text(
        text,
        style: GoogleFonts.beVietnamPro(fontSize: 11.5, color: const Color(0xFF334155)),
      );
}
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

