// lib/screens/student/student_merchandise_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/product_photo_gallery.dart';
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────────────────────
// Models (kept for display purposes)
// ─────────────────────────────────────────────────────────────
class ProductVariant {
  final String id;
  final String size;
  final String color;
  final int stock;
  final double? priceOffset;

  const ProductVariant({
    required this.id,
    required this.size,
    required this.color,
    required this.stock,
    this.priceOffset,
  });

  factory ProductVariant.fromMap(Map<String, dynamic> m) => ProductVariant(
    id: m['id'] as String? ?? '',
    size: m['size'] as String? ?? '',
    color: m['color'] as String? ?? '',
    stock: ((m['stock'] ?? 0) as num).toInt(),
    priceOffset: m['priceOffset'] != null
        ? (m['priceOffset'] as num).toDouble()
        : null,
  );
}

class _Product {
  final String id;
  final String orgId;
  final String name;
  final String description;
  final String category;
  final double price;
  final int stock;
  final String imageBase64;
  final String imageFormat;
  final String status;
  final List<ProductVariant> variants;
  final List<String> rotationPhotos;

  const _Product({
    required this.id,
    required this.orgId,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.stock,
    required this.imageBase64,
    required this.imageFormat,
    this.status = 'available',
    this.variants = const [],
    this.rotationPhotos = const [],
  });

  List<String> get displayPhotos => rotationPhotos.isNotEmpty
      ? rotationPhotos
      : (imageBase64.isNotEmpty ? [imageBase64] : []);

  factory _Product.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;

    String imageBase64 = d['imageBase64'] as String? ?? '';
    String imageFormat = d['imageFormat'] as String? ?? 'jpg';

    String imageDataUrl = '';
    if (imageBase64.isNotEmpty) {
      if (imageBase64.startsWith('data:image')) {
        imageDataUrl = imageBase64;
      } else {
        imageDataUrl = 'data:image/$imageFormat;base64,$imageBase64';
      }
    }

    return _Product(
      id: doc.id,
      orgId: d['orgId'] as String? ?? '',
      name: d['name'] as String? ?? '',
      description: d['description'] as String? ?? '',
      category: d['category'] as String? ?? '',
      price: (d['price'] ?? 0).toDouble(),
      stock: (d['stock'] ?? 0) as int,
      imageBase64: imageDataUrl,
      imageFormat: imageFormat,
      status: d['status'] as String? ?? 'available',
      variants: (d['variants'] is List)
          ? (d['variants'] as List)
                .whereType<Map<String, dynamic>>()
                .map(ProductVariant.fromMap)
                .toList()
          : const [],
      rotationPhotos: ((d['rotationPhotos'] as List?) ?? []).cast<String>(),
    );
  }

  bool get inStock {
    if (variants.isNotEmpty) return variants.any((v) => v.stock > 0);
    return stock > 0;
  }
}

// ─────────────────────────────────────────────────────────────
// Main Screen (promotional catalogue – no purchase flow)
// ─────────────────────────────────────────────────────────────
class StudentMerchandiseScreen extends StatelessWidget {
  const StudentMerchandiseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const StudentAppBar(title: 'Merchandise'),
      body: const _ProductsTab(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Products Tab – catalogue with search, categories, org filter
// ─────────────────────────────────────────────────────────────
class _ProductsTab extends StatefulWidget {
  const _ProductsTab();

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  String _search = '';
  String _selectedCategory = 'All';
  String _selectedOrg = 'All';
  final _searchCtrl = TextEditingController();

  List<String> _categories = ['All'];
  List<String> _orgs = ['All'];
  final Map<String, String> _orgIdMap = {};
  bool _loadingFilters = true;
  // Null until _loadFilters() resolves — only then do we know which orgs are
  // active, so the product grid isn't briefly emptied by filtering against
  // an empty set on first frame.
  Set<String>? _activeOrgIds;

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    try {
      final orgSnapshot = await FirebaseFirestore.instance
          .collection('organizations')
          .where('status', isEqualTo: 'active')
          .get();

      for (final doc in orgSnapshot.docs) {
        final name = doc.data()['name'] as String? ?? '';
        if (name.isNotEmpty) {
          _orgIdMap[name] = doc.id;
        }
      }

      final productsSnap = await FirebaseFirestore.instance
          .collection('products')
          .where('isArchived', isEqualTo: false)
          .get();

      final categories =
          productsSnap.docs
              .map((d) => d.data()['category'] as String? ?? '')
              .where((cat) => cat.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      final productOrgIds = productsSnap.docs
          .map((d) => d.data()['orgId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final filteredOrgs =
          _orgIdMap.entries
              .where((entry) => productOrgIds.contains(entry.value))
              .map((entry) => entry.key)
              .toList()
            ..sort();

      setState(() {
        _categories = ['All', ...categories];
        _orgs = ['All', ...filteredOrgs];
        _activeOrgIds = _orgIdMap.values.toSet();
        _loadingFilters = false;
      });
    } catch (_) {
      setState(() => _loadingFilters = false);
    }
  }

  late final Stream<QuerySnapshot> _stream = FirebaseFirestore.instance
      .collection('products')
      .where('isArchived', isEqualTo: false)
      .snapshots();

  bool get _hasOrgFilter => _selectedOrg != 'All';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Search Bar with Filter Icon ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search merchandise…',
                    hintStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 18,
                      color: Colors.black38,
                    ),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showOrgFilterDialog,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _hasOrgFilter
                        ? AppColors.primaryDark.withOpacity(0.1)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _hasOrgFilter
                          ? AppColors.primaryDark
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.filter_list_rounded,
                    size: 22,
                    color: _hasOrgFilter
                        ? AppColors.primaryDark
                        : Colors.black38,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Category Chips Row ──
        if (!_loadingFilters && _categories.isNotEmpty)
          Container(
            color: Colors.white,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (_, i) {
                final cat = _categories[i];
                final sel = cat == _selectedCategory;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primaryDark : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: sel ? AppColors.primaryDark : Colors.black12,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: sel ? Colors.white : Colors.black54,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _stream,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: SkeletonLoader(count: 4, height: 100),
                );
              }
              if (snap.hasError) {
                return _EmptyHint(
                  icon: Icons.error_outline,
                  title: 'Something went wrong',
                  subtitle: snap.error.toString(),
                );
              }

              var products = (snap.data?.docs ?? [])
                  .map((d) => _Product.fromFirestore(d))
                  .toList();

              final activeOrgIds = _activeOrgIds;
              if (activeOrgIds != null) {
                // Hide merch from organizations the admin has deactivated —
                // otherwise a suspended org's catalog stays fully visible to
                // students, it just becomes unreachable via the org filter.
                products = products
                    .where((p) => activeOrgIds.contains(p.orgId))
                    .toList();
              }

              if (_selectedCategory != 'All') {
                products = products
                    .where((p) => p.category == _selectedCategory)
                    .toList();
              }

              if (_selectedOrg != 'All') {
                final orgId = _orgIdMap[_selectedOrg];
                if (orgId != null) {
                  products = products.where((p) => p.orgId == orgId).toList();
                }
              }

              if (_search.isNotEmpty) {
                final q = _search.toLowerCase();
                products = products
                    .where(
                      (p) =>
                          p.name.toLowerCase().contains(q) ||
                          p.description.toLowerCase().contains(q),
                    )
                    .toList();
              }

              if (products.isEmpty) {
                return _EmptyHint(
                  icon: Icons.storefront_outlined,
                  title: 'No products found',
                  subtitle: _search.isNotEmpty
                      ? 'Try a different search term.'
                      : _hasOrgFilter
                      ? 'No products from $_selectedOrg organization.'
                      : 'No merchandise available yet.',
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                // A fixed 2-column count looks fine on a typical phone but
                // leaves cards oddly narrow on a small phone and wastes
                // space on a tablet/landscape/foldable — max-extent lets
                // the column count adapt to whatever width is actually
                // available instead of a single hardcoded number.
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 0.72,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: products.length,
                itemBuilder: (ctx, i) => _ProductCard(product: products[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showOrgFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filter by Organization',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_hasOrgFilter)
                  TextButton(
                    onPressed: () {
                      setState(() => _selectedOrg = 'All');
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            if (_loadingFilters)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_orgs.isEmpty || _orgs.length == 1)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'No organizations available',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ..._orgs.map((org) {
                final isSelected = org == _selectedOrg;
                return ListTile(
                  leading: Radio<String>(
                    value: org,
                    groupValue: _selectedOrg,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedOrg = value);
                        Navigator.pop(context);
                      }
                    },
                    activeColor: AppColors.primaryDark,
                  ),
                  title: Text(
                    org,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected
                          ? AppColors.primaryDark
                          : Colors.black87,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(
                          Icons.check_circle,
                          color: AppColors.primaryDark,
                          size: 20,
                        )
                      : null,
                  onTap: () {
                    setState(() => _selectedOrg = org);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Product Card (no cart interaction)
// ─────────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final _Product product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final hasVariants = product.variants.isNotEmpty;
    return GestureDetector(
      onTap: () => _showDetails(context),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF0F0F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              // A fixed 120px image height inside a grid whose card width
              // already varies (2 columns on a small phone, more on a
              // tablet) meant the photo's proportions shifted from card to
              // card instead of staying consistent — square keeps it tied
              // to the card's own width instead.
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildProductImage(),
                    if (product.status == 'discontinued' || !product.inStock)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black45,
                          child: Center(
                            child: Text(
                              product.status == 'discontinued'
                                  ? 'DISCONTINUED'
                                  : 'OUT OF STOCK',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: _StatusBadge(status: product.status),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      product.category.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 7),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasVariants)
                              Text(
                                'Starts at',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            Text(
                              '₱${fmt.format(product.price)}',
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: product.inStock
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          product.inStock
                              ? Icons.inventory_2_outlined
                              : Icons.block_rounded,
                          size: 10,
                          color: product.inStock
                              ? Colors.green.shade700
                              : Colors.redAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          product.inStock
                              ? '${product.variants.isNotEmpty ? product.variants.fold<int>(0, (sum, v) => sum + v.stock) : product.stock} in stock'
                              : 'Out of stock',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: product.inStock
                                ? Colors.green.shade700
                                : Colors.redAccent,
                          ),
                        ),
                      ],
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
    final imageData = product.imageBase64;

    if (imageData.isEmpty) {
      return _imgPlaceholder(product.name);
    }

    try {
      // No fixed height/width here — the parent AspectRatio + Stack(fit:
      // StackFit.expand) already sizes this to fill the square photo area,
      // whatever that ends up being for the current card width.
      if (imageData.startsWith('data:image')) {
        final base64String = imageData.split(',').last;
        final bytes = base64Decode(base64String);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          cacheWidth: 400,
          errorBuilder: (_, __, ___) => _imgPlaceholder(product.name),
        );
      } else {
        final bytes = base64Decode(imageData);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          cacheWidth: 400,
          errorBuilder: (_, __, ___) => _imgPlaceholder(product.name),
        );
      }
    } catch (e) {
      return _imgPlaceholder(product.name);
    }
  }

  Widget _imgPlaceholder(String name) => Container(
    color: AppColors.primaryDark.withOpacity(0.1),
    child: Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 36,
          color: AppColors.primaryDark,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );

  void _showDetails(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            controller: ctrl,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildDetailImage(),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(status: product.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  product.category,
                  style: const TextStyle(fontSize: 12, color: Colors.black38),
                ),
                const SizedBox(height: 10),
                Text(
                  '₱${fmt.format(product.price)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  product.description.isNotEmpty
                      ? product.description
                      : 'No description provided.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _DetailChip(
                      icon: Icons.inventory_2_outlined,
                      label:
                          '${product.variants.isNotEmpty ? product.variants.fold<int>(0, (sum, v) => sum + v.stock) : product.stock} in stock',
                    ),
                  ],
                ),
                if (product.variants.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Variants',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  _VariantsTable(product: product, basePrice: product.price),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailImage() {
    final photos = product.displayPhotos;
    if (photos.isEmpty) return _detailPlaceholder();
    return ProductPhotoGallery(photosBase64: photos, height: 200);
  }

  Widget _detailPlaceholder() => Container(
    height: 200,
    decoration: BoxDecoration(
      color: AppColors.primaryDark.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.image_not_supported_outlined,
          size: 48,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 8),
        Text(
          'No Image Available',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Variant info shown in detail sheet (no cart action)
// ─────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final String label;
    switch (status) {
      case 'out_of_stock':
        bg = Colors.red.shade600;
        label = 'OUT OF STOCK';
        break;
      case 'discontinued':
        bg = Colors.grey.shade600;
        label = 'DISCONTINUED';
        break;
      default:
        bg = Colors.green.shade600;
        label = 'AVAILABLE';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _DetailChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.black45),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _VariantsTable extends StatelessWidget {
  final _Product product;
  final double basePrice;
  const _VariantsTable({required this.product, required this.basePrice});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.5),
          1: FlexColumnWidth(1.5),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(1.8),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: AppColors.background),
            children: [
              _cell('SIZE', header: true),
              _cell('COLOR', header: true),
              _cell('STOCK', header: true),
              _cell('PRICE', header: true),
            ],
          ),
          for (final v in product.variants)
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
              ),
              children: [
                _cell(v.size.isNotEmpty ? v.size : '—'),
                _cell(v.color.isNotEmpty ? v.color : '—'),
                _cell(
                  v.stock > 0 ? '${v.stock}' : 'Out',
                  color: v.stock > 0 ? Colors.green.shade600 : Colors.redAccent,
                ),
                _cell('₱${fmt.format(basePrice + (v.priceOffset ?? 0))}'),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(String text, {bool header = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: header ? 11 : 12,
        fontWeight: header ? FontWeight.w700 : FontWeight.normal,
        color: color ?? (header ? Colors.black54 : Colors.black87),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Generic empty state
// ─────────────────────────────────────────────────────────────
class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: Colors.black12),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black45,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.black38),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
