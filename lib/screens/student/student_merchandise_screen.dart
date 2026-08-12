// lib/screens/student/student_merchandise_screen.dart
// UPRISE - Student Merchandise Catalog
// Display-only promotional catalog. No cart, checkout, order, or payment flow.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/product_photo_gallery.dart';

// ─────────────────────────────────────────────────────────────
// Models
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

  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    return ProductVariant(
      id: map['id'] as String? ?? '',
      size: map['size'] as String? ?? '',
      color: map['color'] as String? ?? '',
      stock: ((map['stock'] ?? 0) as num).toInt(),
      priceOffset: map['priceOffset'] != null
          ? (map['priceOffset'] as num).toDouble()
          : null,
    );
  }
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
    final data = doc.data() as Map<String, dynamic>;

    final rawImage = data['imageBase64'] as String? ?? '';
    final imageFormat = data['imageFormat'] as String? ?? 'jpg';

    String imageDataUrl = '';
    if (rawImage.isNotEmpty) {
      imageDataUrl = rawImage.startsWith('data:image')
          ? rawImage
          : 'data:image/$imageFormat;base64,$rawImage';
    }

    final rawVariants = data['variants'];
    final variants = rawVariants is List
        ? rawVariants
            .whereType<Map>()
            .map((v) => ProductVariant.fromMap(
                  Map<String, dynamic>.from(v),
                ))
            .toList()
        : <ProductVariant>[];

    final rawRotationPhotos = data['rotationPhotos'];
    final rotationPhotos = rawRotationPhotos is List
        ? rawRotationPhotos.whereType<String>().toList()
        : <String>[];

    return _Product(
      id: doc.id,
      orgId: data['orgId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      category: data['category'] as String? ?? '',
      price: ((data['price'] ?? 0) as num).toDouble(),
      stock: ((data['stock'] ?? 0) as num).toInt(),
      imageBase64: imageDataUrl,
      imageFormat: imageFormat,
      status: data['status'] as String? ?? 'available',
      variants: variants,
      rotationPhotos: rotationPhotos,
    );
  }

  bool get inStock {
    if (variants.isNotEmpty) {
      return variants.any((variant) => variant.stock > 0);
    }
    return stock > 0;
  }

  int get totalStock {
    if (variants.isNotEmpty) {
      return variants.fold<int>(
        0,
        (total, variant) => total + variant.stock,
      );
    }
    return stock;
  }
}

// ─────────────────────────────────────────────────────────────
// Main Screen
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
// Promotional Catalog
// ─────────────────────────────────────────────────────────────
class _ProductsTab extends StatefulWidget {
  const _ProductsTab();

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  final TextEditingController _searchController = TextEditingController();

  late final Stream<QuerySnapshot> _productsStream = FirebaseFirestore.instance
      .collection('products')
      .where('isArchived', isEqualTo: false)
      .snapshots();

  String _search = '';
  String _selectedCategory = 'All';
  String _selectedOrg = 'All';

  List<String> _categories = const ['All'];
  List<String> _organizations = const ['All'];
  final Map<String, String> _organizationIds = {};
  Set<String>? _activeOrganizationIds;
  bool _loadingFilters = true;

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    try {
      final organizationSnapshot = await FirebaseFirestore.instance
          .collection('organizations')
          .where('status', isEqualTo: 'active')
          .get();

      _organizationIds.clear();

      for (final doc in organizationSnapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String? ?? '';
        if (name.trim().isNotEmpty) {
          _organizationIds[name.trim()] = doc.id;
        }
      }

      final productSnapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('isArchived', isEqualTo: false)
          .get();

      final categories = productSnapshot.docs
          .map((doc) => doc.data()['category'] as String? ?? '')
          .where((category) => category.trim().isNotEmpty)
          .map((category) => category.trim())
          .toSet()
          .toList()
        ..sort();

      final productOrganizationIds = productSnapshot.docs
          .map((doc) => doc.data()['orgId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final organizations = _organizationIds.entries
          .where((entry) => productOrganizationIds.contains(entry.value))
          .map((entry) => entry.key)
          .toList()
        ..sort();

      if (!mounted) return;

      setState(() {
        _categories = ['All', ...categories];
        _organizations = ['All', ...organizations];
        _activeOrganizationIds = _organizationIds.values.toSet();
        _loadingFilters = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFilters = false);
    }
  }

  List<_Product> _filterProducts(List<_Product> products) {
    var result = products;

    if (_activeOrganizationIds != null) {
      result = result
          .where((product) =>
              _activeOrganizationIds!.contains(product.orgId))
          .toList();
    }

    if (_selectedCategory != 'All') {
      result = result
          .where((product) => product.category == _selectedCategory)
          .toList();
    }

    if (_selectedOrg != 'All') {
      final orgId = _organizationIds[_selectedOrg];
      if (orgId != null) {
        result = result.where((product) => product.orgId == orgId).toList();
      }
    }

    final query = _search.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((product) {
        return product.name.toLowerCase().contains(query) ||
            product.description.toLowerCase().contains(query) ||
            product.category.toLowerCase().contains(query);
      }).toList();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _productsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: SkeletonLoader(count: 4, height: 120),
          );
        }

        if (snapshot.hasError) {
          return _EmptyHint(
            icon: Icons.error_outline_rounded,
            title: 'Something went wrong',
            subtitle: 'Merchandise could not be loaded right now.',
          );
        }

        final products = (snapshot.data?.docs ?? [])
            .map(_Product.fromFirestore)
            .toList();

        final filteredProducts = _filterProducts(products);

        return Column(
          children: [
            _buildCatalogHeader(),
            _buildSearchAndFilters(),
            Expanded(
              child: filteredProducts.isEmpty
                  ? _EmptyHint(
                      icon: Icons.storefront_outlined,
                      title: 'No merchandise found',
                      subtitle: _search.trim().isNotEmpty
                          ? 'Try a different search term.'
                          : 'No merchandise is available yet.',
                    )
                  : _buildCatalog(filteredProducts),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCatalogHeader() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1E8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: Color(0xFFC9480A),
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Official Merchandise',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172033),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Explore official and promotional items from CICT student organizations.',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() => _search = value);
                  },
                  decoration: InputDecoration(
                    hintText: 'Search merchandise...',
                    hintStyle: const TextStyle(fontSize: 12.5),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: Color(0xFF94A3B8),
                    ),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 17),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _FilterButton(
                icon: Icons.groups_outlined,
                active: _selectedOrg != 'All',
                onTap: _showOrganizationFilter,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!_loadingFilters)
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final selected = category == _selectedCategory;

                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedCategory = category);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFC9480A)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFFC9480A)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        category,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCatalog(List<_Product> products) {
    final featured = products.first;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _FeaturedProduct(
            product: featured,
            onTap: () => _showProductDetails(featured),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final product = products[index];
                return _ProductCard(
                  product: product,
                  onTap: () => _showProductDetails(product),
                );
              },
              childCount: products.length,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 210,
              mainAxisExtent: 285,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
          ),
        ),
      ],
    );
  }

  void _showOrganizationFilter() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Filter by Organization',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF172033),
                        ),
                      ),
                    ),
                    if (_selectedOrg != 'All')
                      TextButton(
                        onPressed: () {
                          setState(() => _selectedOrg = 'All');
                          Navigator.pop(sheetContext);
                        },
                        child: const Text('Clear'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loadingFilters)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  ..._organizations.map((organization) {
                    final selected = organization == _selectedOrg;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: selected
                            ? const Color(0xFFC9480A)
                            : const Color(0xFFCBD5E1),
                      ),
                      title: Text(
                        organization,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? const Color(0xFFC9480A)
                              : const Color(0xFF334155),
                        ),
                      ),
                      onTap: () {
                        setState(() => _selectedOrg = organization);
                        Navigator.pop(sheetContext);
                      },
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showProductDetails(_Product product) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductDetailsSheet(product: product),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Featured Product
// ─────────────────────────────────────────────────────────────
class _FeaturedProduct extends StatelessWidget {
  final _Product product;
  final VoidCallback onTap;

  const _FeaturedProduct({
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final photos = product.displayPhotos;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 210,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              photos.isEmpty
                  ? const _NoPhoto()
                  : ProductPhotoGallery(
                      photosBase64: photos,
                      height: 210,
                    ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withAlpha(180),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 15,
                bottom: 14,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
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
                              color: Colors.white.withAlpha(235),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Text(
                              'FEATURED MERCH',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .7,
                              ),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₱${NumberFormat('#,##0.##').format(product.price)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Product Card
// ─────────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final _Product product;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final photos = product.displayPhotos;
    final available = product.inStock && product.status != 'discontinued';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE7ECF2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(7),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  photos.isEmpty
                      ? const _NoPhoto()
                      : ProductPhotoGallery(
                          photosBase64: photos,
                          height: double.infinity,
                        ),
                  Positioned(
                    top: 9,
                    left: 9,
                    child: _SmallBadge(
                      text: product.category.isEmpty
                          ? 'Merchandise'
                          : product.category,
                    ),
                  ),
                  if (photos.length > 1)
                    Positioned(
                      right: 9,
                      bottom: 9,
                      child: _SmallBadge(
                        text: '${photos.length} views',
                        dark: true,
                        icon: Icons.collections_outlined,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF172033),
                        height: 1.25,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '₱${NumberFormat('#,##0.##').format(product.price)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFC9480A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          available
                              ? Icons.check_circle_outline_rounded
                              : Icons.remove_circle_outline_rounded,
                          size: 12,
                          color: available
                              ? const Color(0xFF059669)
                              : const Color(0xFFDC2626),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            available
                                ? 'Available'
                                : 'Currently unavailable',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Product Details – display only
// ─────────────────────────────────────────────────────────────
class _ProductDetailsSheet extends StatelessWidget {
  final _Product product;

  const _ProductDetailsSheet({required this.product});

  @override
  Widget build(BuildContext context) {
    final photos = product.displayPhotos;
    final available = product.inStock && product.status != 'discontinued';

    return Container(
      height: MediaQuery.of(context).size.height * .9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(100),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Merchandise Details',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 330,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: photos.isEmpty
                        ? const _NoPhoto()
                        : ProductPhotoGallery(
                            photosBase64: photos,
                            height: 330,
                          ),
                  ),
                  if (photos.length > 1) ...[
                    const SizedBox(height: 9),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.swipe_rounded,
                            size: 15,
                            color: Color(0xFF94A3B8),
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Swipe to explore different angles',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    product.category.isEmpty
                        ? 'OFFICIAL MERCHANDISE'
                        : product.category.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF172033),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₱${NumberFormat('#,##0.##').format(product.price)}',
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFC9480A),
                    ),
                  ),
                  const SizedBox(height: 9),
                  _AvailabilityPill(available: available),
                  if (product.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const _SectionTitle(
                      icon: Icons.notes_rounded,
                      title: 'About this merchandise',
                    ),
                    const SizedBox(height: 9),
                    Text(
                      product.description,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.6,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                  if (product.variants.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const _SectionTitle(
                      icon: Icons.tune_rounded,
                      title: 'Available Variants',
                    ),
                    const SizedBox(height: 10),
                    ...product.variants.map(
                      (variant) => _VariantRow(
                        productPrice: product.price,
                        variant: variant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7F2),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: const Color(0xFFFFE2D0),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 17,
                          color: Color(0xFFC9480A),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This merchandise catalog is for viewing and promotional purposes. Please coordinate directly with the organization for availability and purchase arrangements.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.45,
                              color: Color(0xFF7C4A2D),
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
    );
  }
}

class _VariantRow extends StatelessWidget {
  final double productPrice;
  final ProductVariant variant;

  const _VariantRow({
    required this.productPrice,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    final price = productPrice + (variant.priceOffset ?? 0);
    final label = [
      if (variant.size.trim().isNotEmpty) variant.size,
      if (variant.color.trim().isNotEmpty) variant.color,
    ].join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.isEmpty ? 'Standard' : label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
          ),
          Text(
            variant.stock > 0
                ? '${variant.stock} available'
                : 'Out of stock',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: variant.stock > 0
                  ? const Color(0xFF059669)
                  : const Color(0xFFDC2626),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '₱${NumberFormat('#,##0.##').format(price)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFFC9480A),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Small UI helpers
// ─────────────────────────────────────────────────────────────
class _FilterButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _FilterButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? const Color(0xFFFFF1E8)
          : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? const Color(0xFFC9480A)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: active
                ? const Color(0xFFC9480A)
                : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  final String text;
  final bool dark;
  final IconData? icon;

  const _SmallBadge({
    required this.text,
    this.dark = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? Colors.black.withAlpha(125)
            : Colors.white.withAlpha(235),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 11,
              color: dark ? Colors.white : const Color(0xFF475569),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityPill extends StatelessWidget {
  final bool available;

  const _AvailabilityPill({required this.available});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: available
            ? const Color(0xFFECFDF5)
            : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        available ? 'Currently Available' : 'Currently Unavailable',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: available
              ? const Color(0xFF059669)
              : const Color(0xFFDC2626),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: const Color(0xFFC9480A),
        ),
        const SizedBox(width: 7),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
          ),
        ),
      ],
    );
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF1F5F9),
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          size: 48,
          color: Color(0xFFCBD5E1),
        ),
      ),
    );
  }
}

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
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                icon,
                size: 30,
                color: const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
