// lib/screens/student/student_organizations_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/event_model.dart';
import '../../widgets/student/app_colors.dart';
import '../../widgets/student/student_app_bar.dart';
import '../../widgets/student/app_image.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/feed_cards.dart';
import '../../widgets/common/org_browsing_config.dart';
import '../../services/membership_store.dart';
import 'student_organization_details_screen.dart';
import 'student_merchandise_screen.dart';
import 'student_broadcast_screen.dart';

// Who the viewer is, org-wise, now lives in services/membership_store.dart as
// the public `MyOrgInfo` — the guest shell shares these screens and needs the
// same shape backed by a different (empty) source.
typedef _MyOrgInfo = MyOrgInfo;

/// Which slice of the feed is showing.
enum _FeedFilter { all, events, announcements, media }

/// One entry in the merged org feed. Events and announcements are unioned
/// into this rather than kept in separate lists, so the feed can interleave
/// them in one reverse-chronological scroll.
class _FeedItem {
  final String id;
  final String orgId;
  final bool isEvent;
  final String title;
  final String snippet;
  final String imageSource;
  final String category;

  /// What the feed sorts on: event date, or announcement timestamp.
  final DateTime sortDate;

  const _FeedItem({
    required this.id,
    required this.orgId,
    required this.isEvent,
    required this.title,
    required this.snippet,
    required this.imageSource,
    required this.category,
    required this.sortDate,
  });
}

/// Minimal org identity for the avatar rail and feed card headers.
class _OrgBrief {
  final String name;
  final String logoUrl;
  const _OrgBrief({required this.name, required this.logoUrl});
}

/// "x ago" — matches the wording used by the announcements feed. There are
/// five private copies of this across the repo and none is importable; this
/// is the sixth rather than reaching outside this task's file list.
String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
  return DateFormat('MMM dd, yyyy').format(dt);
}

// ─────────────────────────────────────────────────────────────
// Shared style tokens (kept consistent with the rest of the app).
// The details screen mirrors this class so both org screens match.
// ─────────────────────────────────────────────────────────────
class _UiTokens {
  // Thin aliases onto the shared AppColors scale — kept so existing call
  // sites in this file don't all need renaming, but the actual values now
  // come from one place instead of drifting independently.
  static const Color divider = AppColors.divider;
  static const Color cardBorder = AppColors.divider;
  static const Color mutedText = AppColors.textSecondary;
  static const Color headingText = AppColors.textPrimary;

  static const double radius = 14;

  static List<BoxShadow> get subtleShadow => const [
    BoxShadow(
      color: Color(0x0D000000), // black @ 5%
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// The one card surface shared by the feed and both org card layouts.
  static BoxDecoration card({double radiusOverride = radius}) => BoxDecoration(
    color: AppColors.cardBg,
    borderRadius: BorderRadius.circular(radiusOverride),
    border: Border.all(color: cardBorder),
    boxShadow: subtleShadow,
  );
}

// ─────────────────────────────────────────────────────────────
//  MAIN ORGANIZATIONS SCREEN
// ─────────────────────────────────────────────────────────────
class StudentOrganizationsScreen extends StatefulWidget {
  /// How this role browses orgs — where membership is read from, visibility
  /// gates, and which detail screens open. Defaults to full student access,
  /// so every existing student call site is unchanged.
  final OrgBrowsingConfig config;

  const StudentOrganizationsScreen({
    super.key,
    this.config = OrgBrowsingConfig.student,
  });

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

  // Membership is a single orgId on students/{uid}. It no longer decides
  // *what* the feed shows — that is every active org now — only what gets
  // pinned to the top of it, and where the Member/Officer pill appears.
  late final Future<_MyOrgInfo> _myOrgFuture = _loadMyOrg();

  _FeedFilter _feedFilter = _FeedFilter.all;

  // Feed queries, memoized on the resolved membership — same discipline as
  // the streams below: rebuilding these on a pill tap or a search keystroke
  // would re-hit Firestore and flash the spinner.
  String? _feedKey;
  Future<List<_FeedItem>>? _feedFuture;

  // Merchandise backs the "Media" pill. Fetched lazily so the default feed
  // path costs nothing extra for students who never open that tab.
  String? _mediaKey;
  Future<List<QueryDocumentSnapshot>>? _mediaFuture;

  // Cached once — it used to be created inline inside the
  // _buildMyOrganizationsTab()/_buildDiscoverTab() methods called from
  // build(), so typing in search or toggling grid/list view (both call
  // setState on this screen) resubscribed every stream and flashed the
  // loading spinner on both tabs, not just the one being interacted with.
  late final Stream<QuerySnapshot> _activeOrgsStream = FirebaseFirestore
      .instance
      .collection('organizations')
      .where('status', isEqualTo: 'active')
      .snapshots();

  // ...but caching it is only half the job. Both tabs need this data, and
  // TabBarView disposes the off-screen tab — so with a StreamBuilder per tab
  // the shared stream lost its last listener on every tab switch. Firestore's
  // snapshots() is a broadcast stream: the resubscribing builder gets no
  // replay of the snapshot already delivered, so the rebuilt tab sat at
  // ConnectionState.waiting until the next server-side change. That is both
  // reported symptoms — All Organizations stuck on its skeleton, and the
  // rail's logos vanishing because `briefs` came back empty.
  //
  // One subscription owned by the State instead, started in initState and
  // cancelled only in dispose, so neither tab's lifecycle can tear it down.
  QuerySnapshot? _orgsSnapshot;
  StreamSubscription<QuerySnapshot>? _orgsSub;

  @override
  void initState() {
    super.initState();
    _orgsSub = _activeOrgsStream.listen((snap) {
      if (mounted) setState(() => _orgsSnapshot = snap);
    });
  }

  /// Org identities for the rail, feed card headers, and the discover grid.
  Map<String, _OrgBrief> get _orgBriefs {
    final briefs = <String, _OrgBrief>{};
    for (final doc in _orgsSnapshot?.docs ?? const <QueryDocumentSnapshot>[]) {
      final data = doc.data() as Map<String, dynamic>;
      briefs[doc.id] = _OrgBrief(
        name: (data['name'] ?? 'Organization').toString(),
        logoUrl: (data['logoUrl'] ?? '').toString(),
      );
    }
    return briefs;
  }

  Future<_MyOrgInfo> _loadMyOrg() => widget.config.membershipStore.load();

  /// The viewer's own org, or null — the single input to every "prioritized"
  /// rule on this screen (pinned feed block, first avatar in the rail, first
  /// card in the directory). Guests always get null.
  String? _myOrgId(_MyOrgInfo info) =>
      widget.config.showMembership && info.hasMembership ? info.orgId : null;

  /// Every active org, with the viewer's own first. The rail used to hold
  /// only followed/member orgs; now that the feed spans the whole campus the
  /// rail does too, so membership shows up as position rather than presence.
  List<String> _railOrgIds(String? myOrgId) {
    final ids = _orgBriefs.keys.toList();
    if (myOrgId == null || !ids.remove(myOrgId)) return ids;
    return [myOrgId, ...ids];
  }

  /// Where the avatar rail goes. A member lands straight in *their own* org's
  /// message thread; every other org opens its profile. Broadcast is a
  /// member-only channel, so it can't be the destination for an org the
  /// viewer merely browses — and the rail now lists all of them.
  void _openOrgFromRail(String id, String name, String? myOrgId) {
    final isOwn = id == myOrgId;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => widget.config.enableBroadcast && isOwn
            ? StudentBroadcastScreen(orgId: id, orgName: name)
            : StudentOrganizationsDetailsScreen(
                orgId: id,
                config: widget.config,
              ),
      ),
    );
  }

  /// Events + announcements from *every* organization, merged into one list
  /// with [myOrgId]'s items pinned to the top.
  ///
  /// The feed used to be gated on a followed-org `whereIn`, which meant a
  /// student who had followed nothing saw an empty screen and one who had
  /// followed 30+ orgs silently lost their own org off the end of the cap.
  /// There is no org filter now — the two global queries are the feed, and
  /// membership only decides ordering.
  ///
  /// Every query here is single-field on purpose: a `where` on one field
  /// paired with an `orderBy` on another needs a composite index, which this
  /// codebase avoids (see the note in student_new_event_promo.dart). The
  /// events range+orderBy is on the same field, which does not.
  Future<List<_FeedItem>> _loadFeed(String? myOrgId) async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final db = FirebaseFirestore.instance;

    final results = await Future.wait([
      // Campus-wide. Same range+orderBy shape both Home screens use, so the
      // 60-doc budget is spent on upcoming events rather than an arbitrary
      // slice that the completed-event filter would then throw away.
      db
          .collection('events')
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday),
          )
          .orderBy('date')
          .limit(60)
          .get(),
      db
          .collection('announcements')
          .orderBy('timestamp', descending: true)
          .limit(60)
          .get(),
      // Own-org top-up, so the pinned block is complete even when the org's
      // posts fall outside the campus-wide 60. Deduped by doc id below.
      if (myOrgId != null)
        db
            .collection('events')
            .where('orgId', isEqualTo: myOrgId)
            .limit(40)
            .get(),
      if (myOrgId != null)
        db
            .collection('announcements')
            .where('orgId', isEqualTo: myOrgId)
            .limit(40)
            .get(),
    ]);

    final eventDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final announcementDocs =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in results[0].docs) {
      eventDocs[doc.id] = doc;
    }
    for (final doc in results[1].docs) {
      announcementDocs[doc.id] = doc;
    }
    if (results.length == 4) {
      for (final doc in results[2].docs) {
        eventDocs[doc.id] = doc;
      }
      for (final doc in results[3].docs) {
        announcementDocs[doc.id] = doc;
      }
    }

    final items = <_FeedItem>[];

    final audienceAllows = widget.config.audienceFilter;

    for (final doc in eventDocs.values) {
      final event = EventModel.fromFirestore(doc);
      if (event.status != 'approved') continue;
      if (event.timeStatus == EventTimeStatus.completed) continue;
      // Guests must never see CICT-Only / Members-Only events. Students pass
      // no filter and see everything any org publishes.
      if (audienceAllows != null && !audienceAllows(event.audience)) continue;
      items.add(
        _FeedItem(
          id: doc.id,
          orgId: event.orgId,
          isEvent: true,
          title: event.title,
          snippet: event.location.isNotEmpty
              ? event.location
              : event.description,
          imageSource: event.bannerUrl ?? '',
          category: event.category,
          sortDate: event.date,
        ),
      );
    }

    for (final doc in announcementDocs.values) {
      final data = doc.data();
      // Same predicate announcements_feed.dart uses — treat a missing flag
      // as published/not-archived rather than hiding legacy docs.
      if (data['isPublished'] == false) continue;
      if (data['isArchived'] == true) continue;
      // Guests only ever see Public announcements — the same rule
      // guest_announcements_screen.dart applies at the query level. A missing
      // tag is treated as Public so legacy docs stay visible.
      if (widget.config.publicAnnouncementsOnly &&
          (data['targetAudience'] ?? 'Public').toString() != 'Public') {
        continue;
      }
      final ts = data['timestamp'];
      items.add(
        _FeedItem(
          id: doc.id,
          orgId: (data['orgId'] ?? '').toString(),
          isEvent: false,
          title: (data['title'] ?? 'Untitled').toString(),
          snippet: (data['content'] ?? '').toString(),
          // First non-empty, not `??`: `??` falls through only on null, so an
          // empty imageBase64 used to beat a populated imageUrl.
          imageSource: firstNonEmptyImageSource([
            data['imageBase64']?.toString(),
            data['imageUrl']?.toString(),
          ]),
          category: (data['category'] ?? '').toString(),
          sortDate: ts is Timestamp ? ts.toDate() : DateTime.now(),
        ),
      );
    }

    // Two partitioned lists rather than one comparator with a membership
    // tie-break: List.sort() isn't stable, so a comparator would shuffle
    // same-timestamp items. Same reason student_announcements_screen.dart
    // partitions for pinned-first.
    if (myOrgId == null) {
      items.sort((a, b) => b.sortDate.compareTo(a.sortDate));
      return items;
    }
    final mine = items.where((i) => i.orgId == myOrgId).toList()
      ..sort((a, b) => b.sortDate.compareTo(a.sortDate));
    final rest = items.where((i) => i.orgId != myOrgId).toList()
      ..sort((a, b) => b.sortDate.compareTo(a.sortDate));
    return [...mine, ...rest];
  }

  Future<List<_FeedItem>> _getFeed(String? myOrgId) {
    final key = myOrgId ?? '';
    if (_feedFuture == null || _feedKey != key) {
      _feedKey = key;
      _feedFuture = _loadFeed(myOrgId);
    }
    return _feedFuture!;
  }

  /// The whole catalogue, own-org products first — the feed's org filter is
  /// gone, so the Media pill's is too.
  Future<List<QueryDocumentSnapshot>> _getMedia(String? myOrgId) {
    final key = myOrgId ?? '';
    if (_mediaFuture == null || _mediaKey != key) {
      _mediaKey = key;
      _mediaFuture = FirebaseFirestore.instance
          .collection('products')
          .limit(60)
          .get()
          // isArchived filtered client-side to keep this a single-field
          // query (no composite index needed).
          .then((s) {
            final docs = s.docs
                .where((d) => (d.data())['isArchived'] != true)
                .toList();
            if (myOrgId == null) return docs;
            return [
              ...docs.where((d) => (d.data())['orgId'] == myOrgId),
              ...docs.where((d) => (d.data())['orgId'] != myOrgId),
            ];
          });
    }
    return _mediaFuture!;
  }

  @override
  void dispose() {
    _orgsSub?.cancel();
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
            Tab(text: 'Feed'),
            Tab(text: 'All Organizations'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildFeedTab(), _buildDiscoverTab()],
      ),
    );
  }

  /// The campus feed. There is no "you follow nothing" empty state any more —
  /// every viewer sees every org — so this only waits on membership to know
  /// what to pin, then hands off.
  Widget _buildFeedTab() {
    return FutureBuilder<_MyOrgInfo>(
      future: _myOrgFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: SkeletonLoader(count: 3, height: 220, borderRadius: 14),
          );
        }
        final myOrg = snap.data ?? const _MyOrgInfo();
        // Org identities for the rail + card headers come from the State's
        // own subscription — no extra query, no per-card lookup, and no
        // resubscription to go empty when this tab is rebuilt after a switch.
        return _buildFeedBody(_myOrgId(myOrg), _orgBriefs);
      },
    );
  }

  Widget _buildFeedBody(String? myOrgId, Map<String, _OrgBrief> briefs) {
    return FutureBuilder<List<_FeedItem>>(
      future: _getFeed(myOrgId),
      builder: (context, feedSnap) {
        if (feedSnap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: SkeletonLoader(count: 3, height: 220, borderRadius: 14),
          );
        }

        final all = feedSnap.data ?? const <_FeedItem>[];

        // The ring marks orgs that posted recently — the closest honest
        // stand-in for "unseen", since nothing tracks read state.
        final cutoff = DateTime.now().subtract(const Duration(hours: 48));
        final recentOrgIds = all
            .where((i) => i.sortDate.isAfter(cutoff))
            .map((i) => i.orgId)
            .toSet();

        final items = switch (_feedFilter) {
          _FeedFilter.all => all,
          _FeedFilter.events => all.where((i) => i.isEvent).toList(),
          _FeedFilter.announcements => all.where((i) => !i.isEvent).toList(),
          _FeedFilter.media => const <_FeedItem>[],
        };

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _OrgAvatarRail(
                orgIds: _railOrgIds(myOrgId),
                briefs: briefs,
                recentOrgIds: recentOrgIds,
                onTapOrg: (id, name) => _openOrgFromRail(id, name, myOrgId),
              ),
            ),
            SliverToBoxAdapter(
              child: _FeedFilterPills(
                selected: _feedFilter,
                onChanged: (f) => setState(() => _feedFilter = f),
              ),
            ),
            if (_feedFilter == _FeedFilter.media)
              _buildMediaSliver(myOrgId)
            else if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                  child: EmptyFeedSection(
                    icon: _feedFilter == _FeedFilter.events
                        ? Icons.event_busy_outlined
                        : Icons.campaign_outlined,
                    message: switch (_feedFilter) {
                      _FeedFilter.events => 'No upcoming events yet',
                      _FeedFilter.announcements => 'No announcements yet',
                      _ => 'Nothing here yet',
                    },
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return _OrgFeedCard(
                      item: item,
                      brief: briefs[item.orgId],
                      onTap: () => item.isEvent
                          ? (widget.config.onOpenEvent ?? openEventById)(
                              context,
                              item.id,
                            )
                          : (widget.config.onOpenAnnouncement ??
                                openAnnouncementById)(context, item.id),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  /// "Media" is the campus merchandise catalogue, shown as an image grid.
  Widget _buildMediaSliver(String? myOrgId) {
    return FutureBuilder<List<QueryDocumentSnapshot>>(
      future: _getMedia(myOrgId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: SkeletonLoader(count: 2, height: 140, borderRadius: 14),
            ),
          );
        }
        final docs = snap.data ?? const <QueryDocumentSnapshot>[];
        if (docs.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(20, 40, 20, 20),
              child: EmptyFeedSection(
                icon: Icons.shopping_bag_outlined,
                message: 'No merchandise yet',
              ),
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              return _MediaTile(
                // imageUrl as well as imageBase64: org_merchandise.dart writes
                // an explicit `imageBase64: ''` for a product photographed by
                // URL, so reading imageBase64 alone showed a placeholder for
                // every such product.
                imageSource: firstNonEmptyImageSource([
                  data['imageBase64']?.toString(),
                  data['imageUrl']?.toString(),
                ]),
                name: (data['name'] ?? '').toString(),
                price: ((data['price'] ?? 0) as num).toDouble(),
                onOpen: widget.config.onOpenMerch == null
                    ? null
                    : () => widget.config.onOpenMerch!(context),
              );
            }, childCount: docs.length),
          ),
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
                    ? AppColors.primaryDark.withAlpha(128)
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
                hintStyle: TextStyle(fontSize: 13, color: _UiTokens.mutedText),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: _searchQuery.isNotEmpty
                      ? AppColors.primaryDark
                      : _UiTokens.mutedText,
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
          child: FutureBuilder<_MyOrgInfo>(
            future: _myOrgFuture,
            builder: (context, myOrgSnap) {
              final myOrg = myOrgSnap.data ?? const _MyOrgInfo();

              // Reads the State's cached snapshot instead of subscribing to
              // _activeOrgsStream here — see the note on _orgsSub. This tab
              // is the one that was stuck on its skeleton after a tab switch.
              final snapshot = _orgsSnapshot;
              if (snapshot == null) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: SkeletonLoader(count: 4, height: 96),
                );
              }

              var docs = snapshot.docs;

              if (_searchQuery.isNotEmpty) {
                docs = docs.where((doc) {
                  final org = doc.data() as Map<String, dynamic>;
                  final name = (org['name'] ?? '').toLowerCase();
                  final description = (org['description'] ?? '').toLowerCase();
                  return name.contains(_searchQuery) ||
                      description.contains(_searchQuery);
                }).toList();
              }

              // Own org first, so "prioritized" holds in the directory and
              // not just the feed. Partitioned rather than sorted for the
              // same stability reason as the feed — the stream already
              // arrives in a meaningful order and a comparator would
              // reshuffle the rest of it.
              final myOrgId = _myOrgId(myOrg);
              if (myOrgId != null && docs.any((d) => d.id == myOrgId)) {
                docs = [
                  ...docs.where((d) => d.id == myOrgId),
                  ...docs.where((d) => d.id != myOrgId),
                ];
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
                            color: AppColors.primaryDark.withAlpha(15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _searchQuery.isNotEmpty
                                ? Icons.search_off_rounded
                                : Icons.business_outlined,
                            size: 42,
                            color: AppColors.primaryDark.withAlpha(115),
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
                            color: _UiTokens.mutedText,
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
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(List<QueryDocumentSnapshot> docs, _MyOrgInfo myOrg) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      // mainAxisExtent, not childAspectRatio: the card's content is a fixed
      // ~200px (96 image + 24 padding + name + 2-line description + badge),
      // so deriving the height from the tile width meant it fit on a 411dp
      // phone and overflowed by ~20px on a 360dp one.
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 212,
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

        final isOwn = myOrg.orgId == doc.id;
        return _OrganizationCard(
          id: doc.id,
          name: name,
          description: description,
          logoUrl: logoUrl,
          category: category,
          config: widget.config,
          membershipLabel: isOwn && widget.config.showMembership
              ? myOrg.membershipLabel
              : null,
        );
      },
    );
  }

  Widget _buildList(List<QueryDocumentSnapshot> docs, _MyOrgInfo myOrg) {
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

        final isOwn = myOrg.orgId == doc.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _OrganizationListCard(
            id: doc.id,
            name: name,
            description: description,
            logoUrl: logoUrl,
            category: category,
            config: widget.config,
            membershipLabel: isOwn && widget.config.showMembership
                ? myOrg.membershipLabel
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

  /// Forwarded to the details screen so it browses under the same role
  /// rules this list does.
  final OrgBrowsingConfig config;

  const _OrganizationCard({
    required this.id,
    required this.name,
    required this.description,
    required this.logoUrl,
    required this.category,
    required this.config,
    this.membershipLabel,
  });

  @override
  Widget build(BuildContext context) {
    final logoImage = AppImage.provider(logoUrl ?? '');
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                StudentOrganizationsDetailsScreen(orgId: id, config: config),
          ),
        );
      },
      child: Container(
        decoration: _UiTokens.card(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Logo / Image Section ──
            Stack(
              children: [
                SizedBox(
                  height: 96,
                  width: double.infinity,
                  child: logoImage != null
                      ? Image(
                          image: logoImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                ),
              ],
            ),

            // ── Content ──
            // Expanded here (plus the Flexible description below) bounds the
            // text block to whatever the tile has left, so large system font
            // scaling clips the description instead of pushing the Column
            // past the tile and throwing a RenderFlex overflow.
            Expanded(
              child: Padding(
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
                    Flexible(
                      child: Text(
                        description,
                        style: TextStyle(
                          fontSize: 11,
                          color: _UiTokens.mutedText,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                          color: AppColors.primaryDark.withAlpha(20),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primaryDark.withAlpha(41),
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
      color: AppColors.primaryDark.withAlpha(15),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark.withAlpha(89),
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

  /// Forwarded to the details screen so it browses under the same role
  /// rules this list does.
  final OrgBrowsingConfig config;

  const _OrganizationListCard({
    required this.id,
    required this.name,
    required this.description,
    required this.logoUrl,
    required this.category,
    required this.config,
    this.membershipLabel,
  });

  Widget _buildAvatarPlaceholder() {
    return Container(
      height: 64,
      width: 64,
      color: AppColors.primaryDark.withAlpha(15),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark.withAlpha(89),
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
            builder: (_) =>
                StudentOrganizationsDetailsScreen(orgId: id, config: config),
          ),
        );
      },
      child: Container(
        decoration: _UiTokens.card(),
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
                          color: AppColors.primaryDark.withAlpha(20),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primaryDark.withAlpha(41),
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

// ─────────────────────────────────────────────────────────────
//  FEED PRIMITIVES
// ─────────────────────────────────────────────────────────────

/// Horizontal rail of every active org, the viewer's own first. The ring
/// marks orgs with content from the last 48h.
class _OrgAvatarRail extends StatelessWidget {
  final List<String> orgIds;
  final Map<String, _OrgBrief> briefs;
  final Set<String> recentOrgIds;

  /// What tapping an org opens. Injected so the rail doesn't have to know
  /// whether this viewer is allowed into the broadcast thread.
  final void Function(String orgId, String orgName) onTapOrg;

  const _OrgAvatarRail({
    required this.orgIds,
    required this.briefs,
    required this.recentOrgIds,
    required this.onTapOrg,
  });

  @override
  Widget build(BuildContext context) {
    if (orgIds.isEmpty) return const SizedBox.shrink();
    // 104 = 20 padding + 58 ring (50 avatar + 2 pad + 2 border, per side) +
    // 6 gap + the pinned 12.6 label line, leaving ~7px of slack for system
    // font scaling. At the old 96 the cell overflowed by ~1px at 1.0x.
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        itemCount: orgIds.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final id = orgIds[i];
          final brief = briefs[id];
          final name = brief?.name ?? 'Organization';
          final logo = AppImage.provider(brief?.logoUrl ?? '');
          final hasRecent = recentOrgIds.contains(id);

          return GestureDetector(
            onTap: () => onTapOrg(id, name),
            child: SizedBox(
              width: 64,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: hasRecent
                            ? AppColors.primaryDark
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 25,
                      backgroundColor: AppColors.primarySoft,
                      backgroundImage: logo,
                      child: logo == null
                          ? Text(
                              name.isEmpty ? '?' : name[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDark,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10.5,
                      // Pinned so the cell's height budget doesn't depend on
                      // Be Vietnam Pro's ~1.26 intrinsic line height.
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: _UiTokens.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Pill filter row. Styled on the category badge chip already used by the
/// org cards, with a solid fill for the selected state.
class _FeedFilterPills extends StatelessWidget {
  final _FeedFilter selected;
  final ValueChanged<_FeedFilter> onChanged;

  const _FeedFilterPills({required this.selected, required this.onChanged});

  static const _options = [
    (_FeedFilter.all, 'All'),
    (_FeedFilter.events, 'Events'),
    (_FeedFilter.announcements, 'Announcements'),
    (_FeedFilter.media, 'Media'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          for (final opt in _options) ...[
            _pill(opt.$1, opt.$2),
            if (opt != _options.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _pill(_FeedFilter value, String label) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryDark
              : AppColors.primaryDark.withAlpha(20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryDark
                : AppColors.primaryDark.withAlpha(41),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: isSelected ? Colors.white : AppColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

/// One post in the feed: banner + type badge, a compact org header row, then
/// title and snippet.
class _OrgFeedCard extends StatelessWidget {
  final _FeedItem item;
  final _OrgBrief? brief;
  final VoidCallback onTap;

  const _OrgFeedCard({
    required this.item,
    required this.brief,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // The card style itself now lives in feed_cards.dart as CompactFeedCard,
    // so Home's announcements render from the same widget. This stays as the
    // thin mapping from _FeedItem/_OrgBrief onto it.
    return CompactFeedCard(
      imageSource: item.imageSource,
      orgName: brief?.name ?? 'Organization',
      orgLogoUrl: brief?.logoUrl ?? '',
      badgeLabel: item.isEvent ? 'EVENT' : 'ANNOUNCEMENT',
      badgeColor: item.isEvent ? AppColors.primaryDark : AppColors.accent,
      title: item.title,
      snippet: item.snippet,
      timeAgo: _timeAgo(item.sortDate),
      onTap: onTap,
    );
  }
}

/// One merchandise image in the Media grid.
class _MediaTile extends StatelessWidget {
  final String imageSource;
  final String name;
  final double price;

  /// Where the tile goes. Injected so guests land on their own view-only
  /// catalog instead of the student one.
  final VoidCallback? onOpen;

  const _MediaTile({
    required this.imageSource,
    required this.name,
    required this.price,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap:
          onOpen ??
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StudentMerchandiseScreen()),
          ),
      child: Container(
        decoration: _UiTokens.card(radiusOverride: 12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: AppImage(
                  source: imageSource,
                  fit: BoxFit.cover,
                  showLoadingIndicator: false,
                  placeholderIcon: Icons.shopping_bag_outlined,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _UiTokens.headingText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₱${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
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
}
