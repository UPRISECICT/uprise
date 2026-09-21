// lib/screens/guest/guest_merchandise_screen.dart
//
// View-only merchandise catalog for guests — mirrors
// student_merchandise_screen.dart's showcase model (no cart/checkout,
// browsing only) and its visual design, with the guest scope's own token
// class rather than importing the student screen's private one.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../widgets/product_photo_gallery.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/app_image.dart';
import '../../widgets/student/student_app_bar.dart';

// ─────────────────────────────────────────────────────────────
// Design tokens — same values as the student catalog's `_DS`, so the two
// screens read as one product. Aliases the shared AppColors palette.
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

  static const double radiusSm = 12;
  static const double radiusMd = 18;
  static const double radiusLg = 24;
  static const double radiusXl = 26;
  static const double radiusPill = 100;

  static const double gutter = 16;
  static const double controlHeight = 44; // search field, filter buttons
  static const double pillHeight = 34; // category pills

  // Catalog grid. Hairline cards, no shadow — the warm photo wells already
  // separate one tile from the next.
  static const double gridMaxExtent = 220;
  static const double gridTileHeight = 310;
  static const double gridGapX = 12;
  static const double gridGapY = 16;
  static const double tileInset = 6; // photo inset inside a card
  // Name, price and availability. Sized for the whole block at 1.3x text
  // scale, since the price and availability lines are stacked now.
  static const double cardInfoHeight = 110;

  /// ~60% desaturation for photos of unavailable items.
  static const ColorFilter unavailablePhoto = ColorFilter.matrix(<double>[
    0.5276, 0.4291, 0.0433, 0, 0, //
    0.1276, 0.8291, 0.0433, 0, 0, //
    0.1276, 0.4291, 0.4433, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  static const double galleryHeight = 200; // details sheet photo

  /// Small sentence-case label, e.g. the category under a product name.
  static const TextStyle label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: body,
  );
}

// ─────────────────────────────────────────────────────────────
// Models (display-only)
// ─────────────────────────────────────────────────────────────
class _ProductVariant {
  final String size;
  final String color;
  final int stock;
  final double? priceOffset;

  const _ProductVariant({
    required this.size,
    required this.color,
    required this.stock,
    this.priceOffset,
  });

  factory _ProductVariant.fromMap(Map<String, dynamic> m) => _ProductVariant(
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

  /// The product photo as a URL, for products stored that way instead of
  /// inline. A real field on the document — merchandise_model.dart maps it too
  /// — and org_merchandise.dart writes `imageBase64: ''` for such a product, so
  /// this is the only place its photo lives.
  final String imageUrl;
  final String status;
  final List<_ProductVariant> variants;
  final List<String> rotationPhotos;

  /// UIDs of students who liked this product. Guests can see the count but
  /// not add to it — liking is a student action on the student catalog.
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
    this.imageUrl = '',
    this.status = 'available',
    this.variants = const [],
    this.rotationPhotos = const [],
    this.likedBy = const [],
  });

  List<String> get displayPhotos {
    if (rotationPhotos.isNotEmpty) return rotationPhotos;
    final single = firstNonEmptyImageSource([imageBase64, imageUrl]);
    return single.isNotEmpty ? [single] : [];
  }

  factory _Product.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;

    String imageBase64 = d['imageBase64'] as String? ?? '';
    final imageFormat = d['imageFormat'] as String? ?? 'jpg';
    String imageDataUrl = '';
    if (imageBase64.isNotEmpty) {
      imageDataUrl = imageBase64.startsWith('data:image')
          ? imageBase64
          : 'data:image/$imageFormat;base64,$imageBase64';
    }

    final rawLikedBy = d['likedBy'];

    return _Product(
      id: doc.id,
      orgId: d['orgId'] as String? ?? '',
      name: d['name'] as String? ?? '',
      description: d['description'] as String? ?? '',
      category: d['category'] as String? ?? '',
      price: (d['price'] ?? 0).toDouble(),
      stock: (d['stock'] ?? 0) as int,
      imageBase64: imageDataUrl,
      imageUrl: d['imageUrl'] as String? ?? '',
      status: d['status'] as String? ?? 'available',
      variants: (d['variants'] is List)
          ? (d['variants'] as List)
                .whereType<Map<String, dynamic>>()
                .map(_ProductVariant.fromMap)
                .toList()
          : const [],
      rotationPhotos: ((d['rotationPhotos'] as List?) ?? []).cast<String>(),
      likedBy: rawLikedBy is List
          ? rawLikedBy.whereType<String>().toList()
          : const [],
    );
  }

  int get likeCount => likedBy.length;

  bool get inStock {
    if (variants.isNotEmpty) return variants.any((v) => v.stock > 0);
    return stock > 0;
  }

  int get totalStock {
    if (variants.isNotEmpty) {
      return variants.fold<int>(0, (total, v) => total + v.stock);
    }
    return stock;
  }

  /// Lowest and highest price a buyer could actually pay, variants included.
  ///
  /// The catalog used to print the base price flat, so a product whose
  /// variants carry a `priceOffset` advertised ₱120 and turned out to cost
  /// ₱180 on the details sheet.
  double get minPrice {
    if (variants.isEmpty) return price;
    return variants
        .map((v) => price + (v.priceOffset ?? 0))
        .reduce((a, b) => a < b ? a : b);
  }

  double get maxPrice {
    if (variants.isEmpty) return price;
    return variants
        .map((v) => price + (v.priceOffset ?? 0))
        .reduce((a, b) => a > b ? a : b);
  }

  bool get hasPriceRange => maxPrice - minPrice > 0.009;

  bool get isDiscontinued => status == 'discontinued';

  bool get available => inStock && !isDiscontinued;

  /// One availability sentence, shared by the card and the details sheet on
  /// both the student and guest catalogs — they used to disagree, one saying
  /// "In stock" where the other said "23 in stock".
  String get availabilityLabel {
    if (isDiscontinued) return 'No longer available';
    if (!inStock) return 'Out of stock';
    final left = totalStock;
    if (left > 0 && left <= 5) return 'Only $left left';
    return 'In stock';
  }
}

/// The selling organization, as the catalog needs to show it.
///
/// A promotional catalog that never names the seller leaves the reader with
/// nothing to act on — the details sheet even said "coordinate directly with
/// the organization" without saying which one. Organizations are already
/// loaded here for the org filter, so attribution costs no extra read.
class _OrgBrief {
  final String id;
  final String name;
  final String shortName;
  final String logoUrl;

  const _OrgBrief({
    required this.id,
    required this.name,
    this.shortName = '',
    this.logoUrl = '',
  });

  factory _OrgBrief.fromDoc(String id, Map<String, dynamic> data) {
    String read(String key) => (data[key] ?? '').toString().trim();
    final name = read('name').isNotEmpty ? read('name') : read('orgName');
    return _OrgBrief(
      id: id,
      name: name,
      shortName: read('shortName'),
      logoUrl: read('logoUrl'),
    );
  }

  /// What fits on a product tile: the acronym when the org has one, since the
  /// full name rarely fits a chip at grid width.
  String get displayName => shortName.isNotEmpty ? shortName : name;

  /// Only worth showing under the short name when it adds something.
  bool get hasDistinctFullName =>
      shortName.isNotEmpty && name.isNotEmpty && name != shortName;
}

// ─────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────
class GuestMerchandiseScreen extends StatelessWidget {
  const GuestMerchandiseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      appBar: StudentAppBar(title: 'Merchandise'),
      body: _ProductsTab(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Products Tab — catalogue with search, categories, org filter
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

  /// Trending re-orders whatever the filters already let through; it never
  /// hides anything.
  bool _sortTrending = false;

  final Map<String, String> _orgIdMap = {};

  /// Active organizations by id — the source for naming the seller on every
  /// card and in the details sheet.
  final Map<String, _OrgBrief> _orgsById = {};
  bool _loadingFilters = true;
  // Null until _loadFilters() resolves — only then do we know which orgs are
  // active, so the product grid isn't briefly emptied by filtering against
  // an empty set on first frame.
  Set<String>? _activeOrgIds;

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Loads organizations only.
  ///
  /// This used to also `.get()` the entire products collection a
  /// second time
  /// just to list the categories — while [_stream] was already streaming
  /// those same documents, photos and all, since product images are stored
  /// inline as base64. That was the whole catalog downloaded twice on a phone
  /// connection. Categories are derived from the stream instead.
  Future<void> _loadOrganizations() async {
    try {
      final orgSnapshot = await FirebaseFirestore.instance
          .collection('organizations')
          .where('status', isEqualTo: 'active')
          .get();

      _orgIdMap.clear();
      _orgsById.clear();

      for (final doc in orgSnapshot.docs) {
        final brief = _OrgBrief.fromDoc(doc.id, doc.data());
        if (brief.name.isEmpty) continue;
        _orgIdMap[brief.name] = doc.id;
        _orgsById[doc.id] = brief;
      }

      if (!mounted) return;
      setState(() {
        _activeOrgIds = _orgsById.keys.toSet();
        _loadingFilters = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFilters = false);
    }
  }

  late final Stream<QuerySnapshot> _stream = FirebaseFirestore.instance
      .collection('products')
      .where('isArchived', isEqualTo: false)
      .snapshots();

  bool get _hasOrgFilter => _selectedOrg != 'All';

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
    // The filter row used to sit outside the stream, so it could only offer
    // categories from a second, separate fetch. Everything is built from one
    // snapshot now.
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Column(
            children: [
              _buildSearchAndFilters(
                categories: const ['All'],
                organizations: const ['All'],
              ),
              Expanded(
                child: _EmptyHint(
                  icon: Icons.error_outline,
                  title: 'Something went wrong',
                  subtitle: snap.error.toString(),
                ),
              ),
            ],
          );
        }

        final loading = snap.connectionState == ConnectionState.waiting;

        var products = (snap.data?.docs ?? [])
            .map((d) => _Product.fromFirestore(d))
            .toList();

        final activeOrgIds = _activeOrgIds;
        if (activeOrgIds != null) {
          // Hide merch from organizations the admin has deactivated.
          products = products
              .where((p) => activeOrgIds.contains(p.orgId))
              .toList();
        }

        // Categories and the organization list come from the catalog itself,
        // so a filter can never offer something that matches nothing.
        final categories = <String>{
          for (final p in products)
            if (p.category.trim().isNotEmpty) p.category.trim(),
        }.toList()..sort();
        final orgNames = <String>{
          for (final p in products)
            if (_orgsById[p.orgId] != null) _orgsById[p.orgId]!.name,
        }.toList()..sort();

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
          products = products.where((p) {
            final org = _orgsById[p.orgId];
            return p.name.toLowerCase().contains(q) ||
                p.description.toLowerCase().contains(q) ||
                p.category.toLowerCase().contains(q) ||
                // Searching by organization is the other obvious way to look
                // for merch, now that the seller is on every card.
                (org?.name.toLowerCase().contains(q) ?? false) ||
                (org?.shortName.toLowerCase().contains(q) ?? false);
          }).toList();
        }

        final Widget body;
        if (loading) {
          body = const Center(
            child: CircularProgressIndicator(color: _DS.brand),
          );
        } else if (products.isEmpty) {
          body = _EmptyHint(
            icon: Icons.storefront_outlined,
            title: 'No merchandise found',
            subtitle: _search.isNotEmpty
                ? 'Try a different search term.'
                : _hasOrgFilter
                ? 'No merchandise from $_selectedOrg yet.'
                : 'No merchandise is available yet.',
          );
        } else {
          body = _buildCatalog(
            _sortTrending ? _sortByLikes(products) : products,
          );
        }

        return Column(
          children: [
            _buildSearchAndFilters(
              categories: ['All', ...categories],
              organizations: ['All', ...orgNames],
            ),
            Expanded(child: body),
          ],
        );
      },
    );
  }

  Widget _buildSearchAndFilters({
    required List<String> categories,
    required List<String> organizations,
  }) {
    final searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_DS.radiusSm),
      borderSide: const BorderSide(color: _DS.line),
    );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _DS.line)),
      ),
      padding: const EdgeInsets.only(top: 12, bottom: 12),
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
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _search = v),
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
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 17,
                                  color: _DS.body,
                                ),
                                onPressed: () {
                                  _searchCtrl.clear();
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
                    icon: Icons.filter_list_rounded,
                    active: _hasOrgFilter,
                    label: _selectedOrg,
                    onTap: () => _showOrgFilterDialog(organizations),
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
            child: _loadingFilters || categories.length <= 1
                ? null
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    // Pills start on the gutter but scroll off the true edge.
                    padding: const EdgeInsets.symmetric(horizontal: _DS.gutter),
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 7),
                    itemBuilder: (_, i) {
                      final cat = categories[i];
                      final sel = cat == _selectedCategory;

                      return Semantics(
                        selected: sel,
                        button: true,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: () =>
                                setState(() => _selectedCategory = cat),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: sel ? _DS.brand : Colors.white,
                                borderRadius: BorderRadius.circular(
                                  _DS.radiusPill,
                                ),
                                border: Border.all(
                                  color: sel ? _DS.brand : _DS.line,
                                ),
                              ),
                              child: Text(
                                cat,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: sel ? Colors.white : _DS.body,
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
            delegate: SliverChildBuilderDelegate((ctx, i) {
              final product = products[i];
              final org = _orgsById[product.orgId];
              return _ProductCard(
                product: product,
                org: org,
                onViewOrg: org == null
                    ? null
                    : () => setState(() => _selectedOrg = org.name),
              );
            }, childCount: products.length),
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

  void _showOrgFilterDialog(List<String> organizations) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
                  if (_hasOrgFilter)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: _DS.brand),
                      onPressed: () {
                        setState(() => _selectedOrg = 'All');
                        Navigator.pop(context);
                      },
                      child: const Text('Clear'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (_loadingFilters)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: _DS.brand),
                  ),
                )
              else if (organizations.length <= 1)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'No organizations available',
                      style: TextStyle(fontSize: 13, color: _DS.body),
                    ),
                  ),
                )
              else
                // Flexible + shrinkWrap: the sheet sizes to a short list but
                // scrolls a long one instead of overflowing.
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: organizations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (_, i) {
                      final org = organizations[i];
                      return _OrganizationOption(
                        // 'All' stays the stored value; only the row reads
                        // as a sentence.
                        label: org == 'All' ? 'All organizations' : org,
                        selected: org == _selectedOrg,
                        onTap: () {
                          setState(() => _selectedOrg = org);
                          Navigator.pop(context);
                        },
                      );
                    },
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
// Product Card (view-only)
// ─────────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final _Product product;
  final _OrgBrief? org;

  /// Filters the catalog to this organization. Guests have no membership, so
  /// "everything else they sell" is the useful next step from a product.
  final VoidCallback? onViewOrg;

  const _ProductCard({
    required this.product,
    required this.org,
    this.onViewOrg,
  });

  @override
  Widget build(BuildContext context) {
    final available = product.available;

    return GestureDetector(
      onTap: () => _showDetails(context),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_DS.radiusLg),
          border: Border.all(color: _DS.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo inset on the warm well with its own corners, taking
            // whatever height the fixed info block leaves.
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
                        // Unavailable items fade toward grey instead of being
                        // covered by a dark overlay.
                        available
                            ? _buildProductImage()
                            : ColorFiltered(
                                colorFilter: _DS.unavailablePhoto,
                                child: _buildProductImage(),
                              ),
                        // Who is selling it — the one fact the catalog never
                        // showed. The category used to sit here, repeating
                        // the filter pill already selected above the grid.
                        //
                        // `right` keeps it clear of the photo gallery's own
                        // n/N counter in that corner.
                        if (org != null)
                          Positioned(
                            top: 8,
                            left: 8,
                            right: 44,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _OrgChip(org: org!),
                            ),
                          ),
                        // Moved out of the top-right corner, where it used to
                        // sit directly on top of the gallery's photo counter.
                        if (!available)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: _StatusChip(
                              label: product.isDiscontinued
                                  ? 'No longer available'
                                  : 'Out of stock',
                            ),
                          ),
                        if (product.likeCount > 0)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: _LikeCount(count: product.likeCount),
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
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (product.hasPriceRange)
                          const Text(
                            'From ',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: _DS.body,
                            ),
                          ),
                        Flexible(
                          child: Text(
                            _formatPeso(product.minPrice),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: available ? _DS.brand : _DS.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: available ? _DS.success : _DS.danger,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            product.availabilityLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
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
      ),
    );
  }

  Widget _buildProductImage() {
    // Both fields, first non-empty wins: org_merchandise.dart writes an
    // explicit `imageBase64: ''` for a product photographed by URL, so reading
    // imageBase64 alone showed a letter placeholder for every such product.
    // AppImage then handles the URL, which the old base64-only decode couldn't.
    //
    // The main photo is optional in the org form, so a product can carry its
    // pictures only in `rotationPhotos`; fall back to the first of those.
    final imageData = firstNonEmptyImageSource([
      product.imageBase64,
      product.imageUrl,
      if (product.rotationPhotos.isNotEmpty) product.rotationPhotos.first,
    ]);
    if (imageData.isEmpty) return _imgPlaceholder(product.name);

    return AppImage(
      source: imageData,
      fit: BoxFit.cover,
      showLoadingIndicator: false,
      placeholder: _imgPlaceholder(product.name),
    );
  }

  Widget _imgPlaceholder(String name) => ColoredBox(
    color: _DS.brandSoft,
    child: Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 36,
          color: _DS.brand,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );

  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(_DS.radiusXl),
            ),
          ),
          child: SingleChildScrollView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 14),
                _buildDetailImage(),
                if (product.displayPhotos.length > 1) ...[
                  const SizedBox(height: 9),
                  const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swipe_rounded, size: 15, color: _DS.muted),
                        SizedBox(width: 5),
                        Text(
                          'Swipe to explore different angles',
                          style: TextStyle(fontSize: 11, color: _DS.body),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                // Who is selling it, with a way to see the rest of their
                // merchandise. The sheet never named the organization before.
                if (org != null) ...[
                  _OrgHeaderRow(
                    org: org!,
                    onTap: onViewOrg == null
                        ? null
                        : () {
                            Navigator.pop(sheetContext);
                            onViewOrg!();
                          },
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.category.isNotEmpty) ...[
                            Text(product.category, style: _DS.label),
                            const SizedBox(height: 4),
                          ],
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _DS.ink,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (product.likeCount > 0) ...[
                      const SizedBox(width: 10),
                      _LikeCount(count: product.likeCount),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // Price and availability sit together, and say the same thing
                // the product tile said — the two used to disagree on format
                // and on how stock was worded.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.hasPriceRange
                                ? '${_formatPeso(product.minPrice)} – '
                                      '${_formatPeso(product.maxPrice)}'
                                : _formatPeso(product.price),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: _DS.brand,
                            ),
                          ),
                          if (product.hasPriceRange)
                            const Text(
                              'Price depends on the variant',
                              style: TextStyle(fontSize: 11, color: _DS.body),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _AvailabilityPill(
                      available: product.available,
                      label: product.availabilityLabel,
                    ),
                  ],
                ),
                if (product.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'About this merchandise',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _DS.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _DS.body,
                      height: 1.6,
                    ),
                  ),
                ],
                if (product.variants.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Available variants',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _DS.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _VariantsTable(product: product, basePrice: product.price),
                ],
                const SizedBox(height: 22),
                const Divider(height: 1, color: _DS.line),
                const SizedBox(height: 14),
                // The same footnote the student catalog carries, so both
                // audiences are told the same thing about how to actually buy.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: _DS.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        org == null
                            ? 'This catalog is for viewing and promotional '
                                  'purposes only. Coordinate directly with the '
                                  'organization for availability and purchase '
                                  'arrangements.'
                            : 'This catalog is for viewing and promotional '
                                  'purposes only. Message ${org!.displayName} '
                                  'directly to ask about availability and how '
                                  'to order.',
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.45,
                          color: _DS.body,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
    return ProductPhotoGallery(
      photosBase64: photos,
      height: _DS.galleryHeight,
      borderRadius: BorderRadius.circular(_DS.radiusLg),
    );
  }

  Widget _detailPlaceholder() => Container(
    height: _DS.galleryHeight,
    decoration: BoxDecoration(
      color: _DS.well,
      borderRadius: BorderRadius.circular(_DS.radiusLg),
    ),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_not_supported_outlined, size: 40, color: _DS.muted),
        SizedBox(height: 8),
        Text(
          'No Image Available',
          style: TextStyle(fontSize: 13, color: _DS.body),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────

/// Read-only heart and count. Guests can see what students like but can't
/// like themselves, so there is no tap target here.
/// Seller row at the top of the details sheet: logo, organization name, and —
/// for a guest, who has no membership to manage — a way to see the rest of
/// what that organization sells.
///
/// The sheet used to show no organization at all.
class _OrgHeaderRow extends StatelessWidget {
  final _OrgBrief org;
  final VoidCallback? onTap;

  const _OrgHeaderRow({required this.org, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _DS.well,
      borderRadius: BorderRadius.circular(_DS.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(_DS.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              _OrgAvatar(org: org, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sold by',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _DS.muted,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      org.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _DS.ink,
                      ),
                    ),
                    if (org.hasDistinctFullName)
                      Text(
                        org.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: _DS.body),
                      ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                const Text(
                  'See all',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _DS.brand,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: _DS.brand,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Availability, worded exactly as the product tile words it.
class _AvailabilityPill extends StatelessWidget {
  final bool available;
  final String label;

  const _AvailabilityPill({required this.available, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = available ? _DS.success : _DS.danger;
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
            label,
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

class _LikeCount extends StatelessWidget {
  final int count;
  const _LikeCount({required this.count});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: count == 1 ? '1 like' : '$count likes',
      excludeSemantics: true,
      child: Container(
        height: 26,
        padding: const EdgeInsets.only(left: 7, right: 9),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(240),
          borderRadius: BorderRadius.circular(_DS.radiusPill),
          border: Border.all(color: _DS.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.favorite_border_rounded,
              size: 14,
              color: _DS.body,
            ),
            const SizedBox(width: 4),
            Text(
              NumberFormat.compact().format(count),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: _DS.body,
              ),
            ),
          ],
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

/// Opens the organization sheet. Once an organization is picked it widens to
/// show which one, with its own ✕.
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
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: foreground,
                    ),
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
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? _DS.brand : _DS.ink,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_rounded, size: 20, color: _DS.brand),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag handle shared by both bottom sheets.
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

/// One peso format for the whole catalog — and the same one the organization
/// portal uses. The two mobile catalogs used to disagree (₱800 here, ₱800.00
/// on the guest side) about the same product.
String _formatPeso(num amount) => '₱${NumberFormat('#,##0.##').format(amount)}';

/// The selling organization's logo, or its initials when it has none.
class _OrgAvatar extends StatelessWidget {
  final _OrgBrief org;
  final double size;

  const _OrgAvatar({required this.org, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final provider = org.logoUrl.isEmpty
        ? null
        : AppImage.provider(org.logoUrl);

    if (provider != null) {
      return ClipOval(
        child: Image(
          image: provider,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initials(),
        ),
      );
    }
    return _initials();
  }

  Widget _initials() {
    final source = org.displayName.trim();
    final letters = source.isEmpty
        ? '?'
        : source
              .split(RegExp(r'[\s\-]+'))
              .where((word) => word.isNotEmpty)
              .take(2)
              .map((word) => word[0].toUpperCase())
              .join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _DS.brandSoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        letters,
        style: TextStyle(
          fontSize: size * .44,
          fontWeight: FontWeight.w800,
          color: _DS.brand,
          height: 1,
        ),
      ),
    );
  }
}

/// Seller attribution on a product tile: logo plus the org's acronym, since
/// a full organization name does not fit a chip at grid width.
class _OrgChip extends StatelessWidget {
  final _OrgBrief org;

  const _OrgChip({required this.org});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 9, 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(240),
        borderRadius: BorderRadius.circular(_DS.radiusPill),
        // Photos are often white-backed product shots; the hairline keeps the
        // chip from dissolving into them.
        border: Border.all(color: _DS.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OrgAvatar(org: org, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              org.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _DS.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// States an unavailable item outright instead of leaving a greyed photo to
/// imply it.
class _StatusChip extends StatelessWidget {
  final String label;

  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _DS.dangerBg,
        borderRadius: BorderRadius.circular(_DS.radiusPill),
        border: Border.all(color: _DS.danger.withAlpha(60)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: _DS.danger,
        ),
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_DS.radiusMd),
        border: Border.all(color: _DS.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.5),
          1: FlexColumnWidth(1.5),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(1.8),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: _DS.well),
            children: [
              _cell('Size', header: true),
              _cell('Color', header: true),
              _cell('Stock', header: true),
              _cell('Price', header: true),
            ],
          ),
          for (final v in product.variants)
            TableRow(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _DS.line)),
              ),
              children: [
                _cell(v.size.isNotEmpty ? v.size : '—'),
                _cell(v.color.isNotEmpty ? v.color : '—'),
                _cell(
                  v.stock > 0 ? '${v.stock}' : 'Out',
                  color: v.stock > 0 ? _DS.success : _DS.danger,
                ),
                _cell(
                  _formatPeso(basePrice + (v.priceOffset ?? 0)),
                  color: _DS.brand,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(String text, {bool header = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: header ? 11.5 : 12.5,
        fontWeight: header ? FontWeight.w700 : FontWeight.w500,
        color: color ?? (header ? _DS.body : _DS.ink),
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
