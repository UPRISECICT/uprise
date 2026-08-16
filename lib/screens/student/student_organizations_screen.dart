// lib/screens/student/student_organizations_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';
import '../../widgets/student/app_image.dart';
import '../../widgets/common/loading_widget.dart';
import 'student_organization_details_screen.dart';

class _MyOrgInfo {
  final String orgId;
  final bool isOfficer;
  const _MyOrgInfo({required this.orgId, required this.isOfficer});
}

// ─────────────────────────────────────────────────────────────
// Shared style tokens (kept consistent with the rest of the app)
// ─────────────────────────────────────────────────────────────
class _UiTokens {
  // Thin aliases onto the shared AppColors scale — kept so existing call
  // sites in this file don't all need renaming, but the actual values now
  // come from one place instead of drifting independently.
  static const Color divider = AppColors.divider;
  static const Color cardBorder = AppColors.divider;
  static const Color mutedText = AppColors.textSecondary;
  static const Color headingText = AppColors.textPrimary;

  static List<BoxShadow> get subtleShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────
//  MAIN ORGANIZATIONS SCREEN
// ─────────────────────────────────────────────────────────────
class StudentOrganizationsScreen extends StatefulWidget {
  const StudentOrganizationsScreen({super.key});

  @override
  State<StudentOrganizationsScreen> createState() =>
      _StudentOrganizationsScreenState();
}

class _StudentOrganizationsScreenState extends State<StudentOrganizationsScreen>
    with SingleTickerProviderStateMixin {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // ── View format toggle (grid / list), same idea as the Events tab ──
  bool _gridView = true;

  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  // Membership is still a single orgId on students/{uid} today, not an
  // array — wrapped as a 0-1 item "my organizations" list here so this
  // screen is already shaped for multiple memberships whenever the
  // backend actually supports it, without inventing a new field now.
  late final Future<_MyOrgInfo?> _myOrgFuture = _loadMyOrg();

  Future<_MyOrgInfo?> _loadMyOrg() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final orgId = (data?['orgId'] ?? '').toString();
      if (orgId.isEmpty) return null;
      return _MyOrgInfo(orgId: orgId, isOfficer: data?['isOrgOfficer'] == true);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: StudentAppBar(
        title: 'Organizations',
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryDark,
          labelColor: AppColors.primaryDark,
          unselectedLabelColor: Colors.black45,
          indicatorWeight: 3,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'My Organizations'),
            Tab(text: 'All Organizations'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildMyOrganizationsTab(), _buildDiscoverTab()],
      ),
    );
  }

  Widget _buildMyOrganizationsTab() {
    return FutureBuilder<_MyOrgInfo?>(
      future: _myOrgFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: SkeletonLoader(count: 1, height: 96),
          );
        }
        final myOrg = snap.data;
        if (myOrg == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark.withOpacity(0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.groups_outlined,
                      size: 42,
                      color: AppColors.primaryDark.withOpacity(0.45),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'You haven\'t joined any organizations yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _UiTokens.headingText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Browse All Organizations to see who\'s recognized at CICT.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          );
        }
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('organizations')
              .doc(myOrg.orgId)
              .snapshots(),
          builder: (context, orgSnap) {
            if (!orgSnap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: SkeletonLoader(count: 1, height: 96),
              );
            }
            final org = orgSnap.data!.data() as Map<String, dynamic>?;
            if (org == null) return const SizedBox.shrink();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              children: [
                _OrganizationListCard(
                  id: myOrg.orgId,
                  name: org['name'] ?? 'Organization',
                  description: org['description'] ?? '',
                  logoUrl: org['logoUrl'] as String?,
                  category: org['category'] ?? '',
                  membershipLabel: myOrg.isOfficer ? 'Officer' : 'Member',
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDiscoverTab() {
    return Column(
      children: [
        // ── Search Bar ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _searchQuery.isNotEmpty
                    ? AppColors.primaryDark.withOpacity(0.5)
                    : _UiTokens.divider,
                width: 1.2,
              ),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Search organizations',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: _searchQuery.isNotEmpty
                      ? AppColors.primaryDark
                      : Colors.grey.shade500,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear_rounded,
                          size: 18,
                          color: AppColors.primaryDark,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.transparent,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),

        // ── Organizations Grid / List ──
        Expanded(
          child: FutureBuilder<_MyOrgInfo?>(
            future: _myOrgFuture,
            builder: (context, myOrgSnap) {
              final myOrg = myOrgSnap.data;
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('organizations')
                    .where('status', isEqualTo: 'active')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting ||
                      !snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: SkeletonLoader(count: 4, height: 96),
                    );
                  }

                  var docs = snapshot.data!.docs;

                  if (_searchQuery.isNotEmpty) {
                    docs = docs.where((doc) {
                      final org = doc.data() as Map<String, dynamic>;
                      final name = (org['name'] ?? '').toLowerCase();
                      final description = (org['description'] ?? '')
                          .toLowerCase();
                      return name.contains(_searchQuery) ||
                          description.contains(_searchQuery);
                    }).toList();
                  }

                  if (docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: AppColors.primaryDark.withOpacity(0.06),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _searchQuery.isNotEmpty
                                    ? Icons.search_off_rounded
                                    : Icons.business_outlined,
                                size: 42,
                                color: AppColors.primaryDark.withOpacity(0.45),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No organizations found'
                                  : 'No organizations available',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _UiTokens.headingText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'Try a different search term'
                                  : 'Check back later',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: [
                      // ── Count + view-format toggle (grid / list) ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: Row(
                          children: [
                            Text(
                              '${docs.length} organization${docs.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _UiTokens.mutedText,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(
                                _gridView
                                    ? Icons.view_list_rounded
                                    : Icons.grid_view_rounded,
                                color: AppColors.primaryDark,
                              ),
                              tooltip: _gridView
                                  ? 'Switch to list view'
                                  : 'Switch to grid view',
                              onPressed: () {
                                setState(() => _gridView = !_gridView);
                              },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _gridView
                            ? _buildGrid(docs, myOrg)
                            : _buildList(docs, myOrg),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(List<QueryDocumentSnapshot> docs, _MyOrgInfo? myOrg) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final org = doc.data() as Map<String, dynamic>;
        final name = org['name'] ?? 'Organization';
        final description = org['description'] ?? '';
        final logoUrl = org['logoUrl'] as String?;
        final category = org['category'] ?? '';

        return _OrganizationCard(
          id: doc.id,
          name: name,
          description: description,
          logoUrl: logoUrl,
          category: category,
          membershipLabel: myOrg?.orgId == doc.id
              ? (myOrg!.isOfficer ? 'Officer' : 'Member')
              : null,
        );
      },
    );
  }

  Widget _buildList(List<QueryDocumentSnapshot> docs, _MyOrgInfo? myOrg) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final org = doc.data() as Map<String, dynamic>;
        final name = org['name'] ?? 'Organization';
        final description = org['description'] ?? '';
        final logoUrl = org['logoUrl'] as String?;
        final category = org['category'] ?? '';

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _OrganizationListCard(
            id: doc.id,
            name: name,
            description: description,
            logoUrl: logoUrl,
            category: category,
            membershipLabel: myOrg?.orgId == doc.id
                ? (myOrg!.isOfficer ? 'Officer' : 'Member')
                : null,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ORGANIZATION CARD (grid layout)
// ─────────────────────────────────────────────────────────────
class _OrganizationCard extends StatelessWidget {
  final String id;
  final String name;
  final String description;
  final String? logoUrl;
  final String category;
  // Set only on the All Organizations tab when this card matches the
  // student's own org — 'Member' or 'Officer'. Null otherwise.
  final String? membershipLabel;

  const _OrganizationCard({
    required this.id,
    required this.name,
    required this.description,
    required this.logoUrl,
    required this.category,
    this.membershipLabel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentOrganizationsDetailsScreen(orgId: id),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _UiTokens.cardBorder, width: 1),
          boxShadow: _UiTokens.subtleShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Logo / Image Section ──
            SizedBox(
              height: 96,
              width: double.infinity,
              child: AppImage.provider(logoUrl ?? '') != null
                  ? Image(
                      image: AppImage.provider(logoUrl ?? '')!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(),
                    )
                  : _buildPlaceholder(),
            ),

            // ── Content ──
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Name ──
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: _UiTokens.headingText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (membershipLabel != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryDark,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            membershipLabel!.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 4),

                  // ── Description ──
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: _UiTokens.mutedText,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 8),

                  // ── Category Badge ──
                  if (category.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryDark.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.primaryDark.withOpacity(0.16),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        category,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: AppColors.primaryDark,
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

  Widget _buildPlaceholder() {
    return Container(
      height: 96,
      width: double.infinity,
      color: AppColors.primaryDark.withOpacity(0.06),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark.withOpacity(0.35),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ORGANIZATION LIST CARD (list layout)
// ─────────────────────────────────────────────────────────────
class _OrganizationListCard extends StatelessWidget {
  final String id;
  final String name;
  final String description;
  final String? logoUrl;
  final String category;
  // Set only on the My Organizations tab — 'Member' or 'Officer'. Null on
  // the All Organizations tab (that card doesn't know membership there).
  final String? membershipLabel;

  const _OrganizationListCard({
    required this.id,
    required this.name,
    required this.description,
    required this.logoUrl,
    required this.category,
    this.membershipLabel,
  });

  Widget _buildAvatarPlaceholder() {
    return Container(
      height: 64,
      width: 64,
      color: AppColors.primaryDark.withOpacity(0.06),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark.withOpacity(0.35),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logoImage = AppImage.provider(logoUrl ?? '');

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentOrganizationsDetailsScreen(orgId: id),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _UiTokens.cardBorder, width: 1),
          boxShadow: _UiTokens.subtleShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Logo / Avatar ──
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
              child: SizedBox(
                height: 96,
                width: 64,
                child: logoImage != null
                    ? Image(
                        image: logoImage,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildAvatarPlaceholder(),
                      )
                    : _buildAvatarPlaceholder(),
              ),
            ),

            // ── Content ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _UiTokens.headingText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (membershipLabel != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryDark,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              membershipLabel!.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _UiTokens.mutedText,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (category.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryDark.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primaryDark.withOpacity(0.16),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          category,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Chevron ──
            const Padding(
              padding: EdgeInsets.only(right: 12, top: 38),
              child: Icon(
                Icons.chevron_right_rounded,
                color: _UiTokens.mutedText,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
