// lib/screens/student/student_merchandise_screen.dart
// UPRISE - Student Merchandise Catalog
// Display-only promotional catalog. No cart, checkout, order, or payment flow.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../widgets/student/app_colors.dart';
import '../../widgets/student/app_image.dart';
import '../../widgets/student/student_app_bar.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/product_photo_gallery.dart';

// ─────────────────────────────────────────────────────────────
// Design tokens
//
// This screen used to repeat the same hex literals, radii and shadows inline
// at every call site, so the catalog and the details sheet slowly drifted out
// of step with each other — same idea in two slightly different greys. One
// local token class, matching the `_DS` convention the org-side merchandise
// screen already uses.
//
// Values alias the shared student palette (AppColors) rather than carrying
// their own slate greys and a private orange, so this screen reads as part of
// the same app as everything around it.
// ─────────────────────────────────────────────────────────────
class _DS {
  static const Color ink = AppColors.textPrimary; // headings
  static const Color body = AppColors.textSecondary; // body copy
  static const Color muted = AppColors.textMuted; // labels, hints
  static const Color brand = AppColors.primaryDark; // price, selected states
  static const Color brandSoft = AppColors.primarySoft; // active tints
  static const Color line = AppColors.divider; // hairline borders
  static const Color well = AppColors.surfaceTint; // image backgrounds
  static const Color success = AppColors.success;
  static const Color successBg = AppColors.successBg;
  static const Color danger = AppColors.error;
  static const Color dangerBg = AppColors.errorBg;
  static const Color heart = danger; // liked state

  static const double radiusSm = 12;
  static const double radiusMd = 18;
  static const double radiusLg = 24;
  static const double radiusXl = 26;
  static const double radiusPill = 100;

  static const double gutter = 16;
  static const double controlHeight = 44; // search field, filter button
  static const double pillHeight = 34; // category pills

  // Catalog grid. Cards carry a hairline and no shadow: the warm photo wells
  // already separate one tile from the next.
  static const double gridMaxExtent = 220;
  static const double gridTileHeight = 290;
  static const double gridGapX = 12;
  static const double gridGapY = 16;
  static const double tileInset = 6; // photo inset inside a card
  static const double cardInfoHeight = 90; // name + price block under photo

  /// ~60% desaturation for photos of unavailable items.
  static const ColorFilter unavailablePhoto = ColorFilter.matrix(<double>[
    0.5276, 0.4291, 0.0433, 0, 0, //
    0.1276, 0.8291, 0.0433, 0, 0, //
    0.1276, 0.4291, 0.4433, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  // Details sheet.
  static const double sheetHeightFactor = .9;
  static const double galleryHeight = 330;

  /// Small sentence-case label, e.g. the category above a product name.
  /// Replaces the old tracked-out all-caps style.
  static const TextStyle label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: body,
  );
}

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

  /// The product photo as a URL, for products stored that way instead of
  /// inline. org_merchandise.dart writes `imageBase64: ''` for such a product,
  /// so without this field the photo never reached the catalog.
  final String imageUrl;
  final String status;
  final List<ProductVariant> variants;
  final List<String> rotationPhotos;

  /// UIDs of students who liked this product. The count is derived from it,
  /// so there's no separate counter to drift out of sync.
  final List<String> likedBy;

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
    this.imageUrl = '',
    this.status = 'available',
    this.variants = const [],
    this.rotationPhotos = const [],
    this.likedBy = const [],
  });

  // First non-empty of the inline photo and the URL — same order the guest
  // catalog uses. ProductPhotoGallery renders either kind via AppImage.
  List<String> get displayPhotos {
    if (rotationPhotos.isNotEmpty) return rotationPhotos;
    final single = firstNonEmptyImageSource([imageBase64, imageUrl]);
    return single.isNotEmpty ? [single] : [];
  }

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

    final rawLikedBy = data['likedBy'];
    final likedBy = rawLikedBy is List
        ? rawLikedBy.whereType<String>().toList()
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
      imageUrl: data['imageUrl'] as String? ?? '',
      status: data['status'] as String? ?? 'available',
      variants: variants,
      rotationPhotos: rotationPhotos,
      likedBy: likedBy,
    );
  }

  int get likeCount => likedBy.length;

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

  /// Trending re-orders whatever the filters already let through; it never
  /// hides anything.
  bool _sortTrending = false;

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

  /// Most-liked first. Dart's sort isn't stable, so ties fall back to name
  /// then id — otherwise equal-liked items would shuffle on every snapshot.
  List<_Product> _sortByLikes(List<_Product> products) {
    return [...products]..sort((a, b) {
        final byLikes = b.likeCount.compareTo(a.likeCount);
        if (byLikes != 0) return byLikes;
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (byName != 0) return byName;
        return a.id.compareTo(b.id);
      });
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
        final shownProducts = _sortTrending
            ? _sortByLikes(filteredProducts)
            : filteredProducts;

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
                  : _buildCatalog(shownProducts),
            ),
          ],
        );
      },
    );
  }

  // Header and search read as one white surface with a single hairline under
  // it, instead of two stacked blocks.
  Widget _buildCatalogHeader() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(_DS.gutter, 14, _DS.gutter, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _DS.brandSoft,
              borderRadius: BorderRadius.circular(_DS.radiusSm),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: _DS.brand,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Official Merchandise',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: _DS.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Explore official and promotional items from CICT student organizations.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: _DS.body,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      borderSide: const BorderSide(color: _DS.line),
    );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _DS.line)),
      ),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _DS.gutter),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: _DS.controlHeight,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() => _search = value);
                      },
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(fontSize: 13, color: _DS.ink),
                      decoration: InputDecoration(
                        hintText: 'Search merchandise',
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: _DS.muted,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: _DS.muted,
                        ),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 17,
                                  color: _DS.body,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _search = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: _DS.well,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        border: searchBorder,
                        enabledBorder: searchBorder,
                        focusedBorder: searchBorder.copyWith(
                          borderSide: const BorderSide(
                            color: _DS.brand,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _TrendingToggle(
                  active: _sortTrending,
                  onTap: () {
                    setState(() => _sortTrending = !_sortTrending);
                  },
                ),
                const SizedBox(width: 8),
                // Capped so the search field keeps usable width on a 320dp
                // phone with both controls showing.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: _FilterButton(
                    icon: Icons.groups_outlined,
                    active: _selectedOrg != 'All',
                    label: _selectedOrg,
                    onTap: _showOrganizationFilter,
                    onClear: () {
                      setState(() => _selectedOrg = 'All');
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Height is held while the categories load, so the grid doesn't
          // jump down a row when they arrive.
          SizedBox(
            height: _DS.pillHeight,
            child: _loadingFilters
                ? null
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    // Pills start on the gutter but scroll off the true edge.
                    padding: const EdgeInsets.symmetric(
                      horizontal: _DS.gutter,
                    ),
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 7),
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final selected = category == _selectedCategory;

                      return Semantics(
                        selected: selected,
                        button: true,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: () {
                              setState(() => _selectedCategory = category);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected ? _DS.brand : Colors.white,
                                borderRadius: BorderRadius.circular(
                                  _DS.radiusPill,
                                ),
                                border: Border.all(
                                  color: selected ? _DS.brand : _DS.line,
                                ),
                              ),
                              child: Text(
                                category,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selected ? Colors.white : _DS.body,
                                ),
                              ),
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
    // One uniform grid, no hero. The "featured" slot was just whichever
    // product happened to sort first, and because the grid below still built
    // from index 0 that same product was rendered twice — once as the banner,
    // once as the first card. A catalog reads better as one consistent rack
    // anyway, so the reader can compare items instead of being sold one.
    final count = products.length;
    final countLabel = count == 1 ? '1 item' : '$count items';

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(_DS.gutter, 14, _DS.gutter, 10),
          sliver: SliverToBoxAdapter(
            child: Text(
              // Says the order out loud when Trending changed it, since the
              // flame toggle up top is icon-only.
              _sortTrending ? '$countLabel, most liked first' : countLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _DS.body,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(_DS.gutter, 0, _DS.gutter, 28),
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
              maxCrossAxisExtent: _DS.gridMaxExtent,
              mainAxisExtent: _DS.gridTileHeight,
              crossAxisSpacing: _DS.gridGapX,
              mainAxisSpacing: _DS.gridGapY,
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
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(_DS.radiusLg),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Filter by organization',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: _DS.ink,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Show merchandise from one organization.',
                            style: TextStyle(fontSize: 12, color: _DS.body),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedOrg != 'All')
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: _DS.brand,
                        ),
                        onPressed: () {
                          setState(() => _selectedOrg = 'All');
                          Navigator.pop(sheetContext);
                        },
                        child: const Text('Clear'),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_loadingFilters)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: CircularProgressIndicator(color: _DS.brand),
                    ),
                  )
                else
                  // Flexible + shrinkWrap: the sheet sizes to a short list but
                  // scrolls a long one instead of overflowing.
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _organizations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 2),
                      itemBuilder: (context, index) {
                        final organization = _organizations[index];
                        final selected = organization == _selectedOrg;

                        return _OrganizationOption(
                          // 'All' stays the stored value; only the row reads
                          // as a sentence.
                          label: organization == 'All'
                              ? 'All organizations'
                              : organization,
                          selected: selected,
                          onTap: () {
                            setState(() => _selectedOrg = organization);
                            Navigator.pop(sheetContext);
                          },
                        );
                      },
                    ),
                  ),
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

    final Widget photo = photos.isEmpty
        ? const _NoPhoto()
        : ProductPhotoGallery(
            photosBase64: photos,
            height: double.infinity,
          );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_DS.radiusLg),
          border: Border.all(color: _DS.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The photo takes whatever the fixed info block leaves, rather
            // than a fixed aspect ratio: every tile is already the same size,
            // so photos line up, and a ratio tied to tile width would overflow
            // at the wider tiles the grid can hand out.
            //
            // Inset on the warm well with its own corners, like an item set
            // down on a table, instead of bleeding to the card edge.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  _DS.tileInset,
                  _DS.tileInset,
                  _DS.tileInset,
                  0,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_DS.radiusMd),
                  child: ColoredBox(
                    color: _DS.well,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Unavailable items fade toward grey, so a sold-out
                        // item reads at a glance without covering the photo.
                        available
                            ? photo
                            : ColorFiltered(
                                colorFilter: _DS.unavailablePhoto,
                                child: photo,
                              ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _SmallBadge(
                            text: product.category.isEmpty
                                ? 'Merchandise'
                                : product.category,
                          ),
                        ),
                        // Hidden at zero so an unliked item's photo stays
                        // clean; liking itself happens in the details sheet.
                        if (product.likeCount > 0)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: _LikeCount(likedBy: product.likedBy),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: _DS.cardInfoHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Two lines reserved whether or not the name needs them,
                    // so the price sits at the same height on every card.
                    SizedBox(
                      height: 34,
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _DS.ink,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            '₱${NumberFormat('#,##0.##').format(product.price)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: available ? _DS.brand : _DS.muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // A dot carries availability at this size better than
                        // an icon and a word that had to ellipsize anyway.
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: available ? _DS.success : _DS.danger,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          available ? 'In stock' : 'Unavailable',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: _DS.body,
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
      height: MediaQuery.of(context).size.height * _DS.sheetHeightFactor,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_DS.radiusXl),
        ),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: _SheetHandle(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The old "Merchandise Details" title row only restated what
                  // the sheet obviously was; the close button now floats on
                  // the photo, top-left, clear of the gallery's own n/N
                  // counter at top-right.
                  Container(
                    height: _DS.galleryHeight,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: _DS.well,
                      borderRadius: BorderRadius.circular(_DS.radiusLg),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        photos.isEmpty
                            ? const _NoPhoto()
                            : ProductPhotoGallery(
                                photosBase64: photos,
                                height: _DS.galleryHeight,
                              ),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: _SheetCloseButton(
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (photos.length > 1) ...[
                    const SizedBox(height: 9),
                    const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swipe_rounded,
                            size: 15,
                            color: _DS.muted,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Swipe to explore different angles',
                            style: TextStyle(fontSize: 11, color: _DS.body),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Category → name → price + availability read as one header
                  // block, with the like button riding alongside the name the
                  // way a favourite sits beside a product title.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.category.isEmpty
                                  ? 'Official merchandise'
                                  : product.category,
                              style: _DS.label,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              product.name,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: _DS.ink,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Liking lives here rather than on the card, where a
                      // heart sharing the photo with the tap-to-open target
                      // was easy to hit by accident.
                      _LikeButton(
                        productId: product.id,
                        likedBy: product.likedBy,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          '₱${NumberFormat('#,##0.##').format(product.price)}',
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            color: _DS.brand,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _AvailabilityPill(available: available),
                    ],
                  ),
                  if (product.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const _SectionTitle(title: 'About this merchandise'),
                    const SizedBox(height: 8),
                    Text(
                      product.description,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: _DS.body,
                      ),
                    ),
                  ],
                  if (product.variants.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const _SectionTitle(title: 'Available variants'),
                    const SizedBox(height: 10),
                    // One panel with hairlines between rows reads as a single
                    // list, where separate bordered tiles read as N buttons.
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: _DS.well,
                        borderRadius: BorderRadius.circular(_DS.radiusMd),
                        border: Border.all(color: _DS.line),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < product.variants.length; i++) ...[
                            if (i > 0)
                              const Divider(
                                height: 1,
                                thickness: 1,
                                color: _DS.line,
                              ),
                            _VariantRow(
                              productPrice: product.price,
                              variant: product.variants[i],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Demoted to a quiet footnote: as a filled orange panel this
                  // competed with the price for attention, even though it's
                  // boilerplate that's identical on every product.
                  const Divider(height: 1, color: _DS.line),
                  const SizedBox(height: 14),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: _DS.muted,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This catalog is for viewing and promotional purposes '
                          'only. Coordinate directly with the organization for '
                          'availability and purchase arrangements.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.45,
                            color: _DS.body,
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
    );
  }
}

/// Close button that floats over the details photo. The frosted white disc
/// keeps it legible on both light product shots and dark ones.
class _SheetCloseButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _SheetCloseButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withAlpha(235),
      shape: const CircleBorder(side: BorderSide(color: _DS.line)),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: 'Close',
        onPressed: onPressed,
        icon: const Icon(Icons.close_rounded, size: 20, color: _DS.ink),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.isEmpty ? 'Standard' : label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _DS.ink,
              ),
            ),
          ),
          Text(
            variant.stock > 0
                ? '${variant.stock} available'
                : 'Out of stock',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: variant.stock > 0 ? _DS.success : _DS.danger,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '₱${NumberFormat('#,##0.##').format(price)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _DS.brand,
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
/// Opens the organization sheet. Once an organization is picked it widens to
/// show which one, with its own ✕ — a colour change alone never said *which*
/// organization was narrowing the catalog.
class _FilterButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String? label;
  final VoidCallback? onClear;

  const _FilterButton({
    required this.icon,
    required this.active,
    required this.onTap,
    this.label,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = active ? _DS.brand : _DS.body;
    final showLabel = active && label != null;

    return Material(
      color: active ? _DS.brandSoft : _DS.well,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        side: BorderSide(color: active ? _DS.brand : _DS.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: _DS.controlHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InkWell(
                onTap: onTap,
                child: Semantics(
                  button: true,
                  label: showLabel
                      ? 'Organization filter: $label'
                      : 'Filter by organization',
                  excludeSemantics: true,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: showLabel ? 11 : 12,
                      right: showLabel ? 4 : 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 20, color: foreground),
                        if (showLabel) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              label!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: foreground,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (showLabel && onClear != null)
              InkWell(
                onTap: onClear,
                child: Semantics(
                  button: true,
                  label: 'Clear organization filter',
                  excludeSemantics: true,
                  child: SizedBox(
                    width: 32,
                    height: _DS.controlHeight,
                    child: Icon(Icons.close_rounded, size: 16, color: foreground),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One row of the organization sheet. Single-select: the picked row is tinted
/// and carries a check, the rest stay plain.
class _OrganizationOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OrganizationOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? _DS.brandSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(_DS.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_DS.radiusSm),
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? _DS.brand : _DS.ink,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: _DS.brand,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The heart-and-number pill, shared by the card's read-only count and the
/// details sheet's like button so the two always look like the same thing.
class _HeartPill extends StatelessWidget {
  final bool liked;
  final int count;
  final bool large;

  const _HeartPill({
    required this.liked,
    required this.count,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = liked ? _DS.heart : _DS.body;

    return Container(
      height: large ? 38 : 26,
      padding: EdgeInsets.only(
        left: large ? 12 : 7,
        right: count > 0 ? (large ? 14 : 9) : (large ? 12 : 7),
      ),
      decoration: BoxDecoration(
        color: large
            ? (liked ? _DS.dangerBg : Colors.white)
            : Colors.white.withAlpha(240),
        borderRadius: BorderRadius.circular(_DS.radiusPill),
        border: Border.all(
          color: large && liked ? _DS.heart.withAlpha(90) : _DS.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(liked),
              size: large ? 20 : 14,
              color: color,
            ),
          ),
          if (count > 0) ...[
            SizedBox(width: large ? 6 : 4),
            Text(
              NumberFormat.compact().format(count),
              style: TextStyle(
                fontSize: large ? 13 : 10.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _likesLabel(int count) => count == 1 ? '1 like' : '$count likes';

/// Read-only like count on a catalog card. Liking happens in the details
/// sheet; here the heart only reports, and fills if the viewer has liked it.
class _LikeCount extends StatelessWidget {
  final List<String> likedBy;

  const _LikeCount({required this.likedBy});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final liked = uid != null && likedBy.contains(uid);

    return Semantics(
      label: _likesLabel(likedBy.length),
      excludeSemantics: true,
      child: _HeartPill(liked: liked, count: likedBy.length),
    );
  }
}

/// Like button in the details sheet. Tapping toggles the signed-in user's uid
/// in the product's `likedBy` array — one arrayUnion/arrayRemove write, which
/// the catalog's existing products stream then reflects back onto the cards.
///
/// The toggle is optimistic: the heart flips immediately and snaps back (with
/// a SnackBar) only if the write is rejected. The sheet is built from a
/// snapshot and doesn't listen for updates, so this local state is what keeps
/// the heart right while the sheet stays open.
class _LikeButton extends StatefulWidget {
  final String productId;
  final List<String> likedBy;

  const _LikeButton({
    required this.productId,
    required this.likedBy,
  });

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  late bool _liked;
  late int _count;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  void _syncFromWidget() {
    _liked = _uid != null && widget.likedBy.contains(_uid);
    _count = widget.likedBy.length;
  }

  Future<void> _toggle() async {
    final uid = _uid;
    if (uid == null) return;

    final nowLiked = !_liked;
    setState(() {
      _liked = nowLiked;
      _count += nowLiked ? 1 : -1;
    });
    if (nowLiked) HapticFeedback.lightImpact();

    try {
      await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.productId)
          .update({
        'likedBy': nowLiked
            ? FieldValue.arrayUnion([uid])
            : FieldValue.arrayRemove([uid]),
      });
    } catch (_) {
      if (!mounted) return;
      // Back to what the sheet was opened with, which the failed write never
      // changed.
      setState(_syncFromWidget);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("Couldn't save your like. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _count < 0 ? 0 : _count;
    final pill = _HeartPill(liked: _liked, count: count, large: true);

    if (_uid == null) {
      return Semantics(
        label: _likesLabel(count),
        excludeSemantics: true,
        child: pill,
      );
    }

    return Semantics(
      button: true,
      toggled: _liked,
      label: '${_liked ? 'Unlike' : 'Like'}, ${_likesLabel(count)}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: _toggle,
          child: pill,
        ),
      ),
    );
  }
}

/// Sort toggle beside the search field. Icon-only to leave the search field
/// its width; the tooltip and semantics carry the name.
class _TrendingToggle extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _TrendingToggle({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active ? 'Showing most liked first' : 'Sort by most liked',
      child: Semantics(
        button: true,
        toggled: active,
        label: 'Trending: sort by most liked',
        excludeSemantics: true,
        child: Material(
          color: active ? _DS.brand : _DS.well,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
            side: BorderSide(color: active ? _DS.brand : _DS.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: _DS.controlHeight,
              height: _DS.controlHeight,
              child: Icon(
                Icons.local_fire_department_rounded,
                size: 20,
                color: active ? Colors.white : _DS.body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  final String text;

  const _SmallBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      // Long category names ellipsize instead of running across the photo.
      constraints: const BoxConstraints(maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(235),
        borderRadius: BorderRadius.circular(_DS.radiusPill),
        // Photos are often white-backed product shots; the hairline keeps the
        // badge from dissolving into them.
        border: Border.all(color: _DS.line),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: _DS.body,
        ),
      ),
    );
  }
}

class _AvailabilityPill extends StatelessWidget {
  final bool available;

  const _AvailabilityPill({required this.available});

  @override
  Widget build(BuildContext context) {
    final color = available ? _DS.success : _DS.danger;

    // Same dot the product card uses, so availability reads the same way on
    // the rack and in the details sheet.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: available ? _DS.successBg : _DS.dangerBg,
        borderRadius: BorderRadius.circular(_DS.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            available ? 'Available' : 'Unavailable',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: _DS.ink,
      ),
    );
  }
}

/// Drag handle shared by both bottom sheets, so they can't drift apart.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: _DS.line,
          borderRadius: BorderRadius.circular(_DS.radiusPill),
        ),
      ),
    );
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _DS.well,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 40,
          color: _DS.muted,
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _DS.well,
                  borderRadius: BorderRadius.circular(_DS.radiusMd),
                  border: Border.all(color: _DS.line),
                ),
                child: Icon(icon, size: 26, color: _DS.muted),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _DS.ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: _DS.body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
