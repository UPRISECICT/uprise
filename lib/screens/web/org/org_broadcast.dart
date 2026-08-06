// lib/screens/web/org/org_broadcast.dart
// Private messaging inbox — one thread per student, replacing the old
// org-wide broadcast channel. Messages are filtered for profanity before
// being stored. Mirrors lib/screens/student/student_broadcast_screen.dart,
// which renders the student side of the same `conversations` collection.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/notification_service.dart';
import '../../../utils/profanity_filter.dart';
import '../../../theme/org_theme.dart' as theme;
import 'export_util.dart';

class _C {
  // Was a stale, more-vivid orange (0xFFEA580C) that didn't match the
  // deepened brand primary the rest of the org portal was moved to — same
  // drift bug fixed elsewhere (org_events_schedule.dart, org_reports.dart,
  // org_profile.dart) this session.
  static const Color primaryDark = theme.UpriseColors.primaryDark;
  static const Color white = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8F9FB);
  static const Color pageBg = Color(0xFFFBFCFE);
  static const Color border = Color(0xFFE8ECF0);
  static const Color charcoal = Color(0xFF1A202C);
  static const Color darkGray = Color(0xFF64748B);
  static const Color textFaint = Color(0xFF9AA5B4);
}

// MemoryImage's cache key is the decoded bytes object itself, not the
// source string — calling base64Decode() fresh on every build (which
// happens on every message-list rebuild, e.g. after sending, blocking, or
// archiving) produced a *new* Uint8List each time, which Flutter's image
// cache can never recognize as "the same image already loaded." That forced
// a full re-decode + repaint from scratch on every action, which is exactly
// what showed up as photos visibly glitching/reloading. Caching the decoded
// MemoryImage per source string means the same object is reused, so the
// cache actually hits — mirrors org_profile.dart's identical fix.
final Map<String, MemoryImage> _memoryImageCache = {};

ImageProvider _imageProviderFromBase64(String data) {
  return _memoryImageCache.putIfAbsent(data, () {
    final base64Part = data.contains(',') ? data.split(',').last : data;
    return MemoryImage(base64Decode(base64Part));
  });
}

String _mimeTypeFromFileName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'ppt':
      return 'application/vnd.ms-powerpoint';
    case 'pptx':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case 'zip':
      return 'application/zip';
    case 'txt':
      return 'text/plain';
    default:
      return 'application/octet-stream';
  }
}

IconData _iconForFileName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return Icons.picture_as_pdf_rounded;
    case 'doc':
    case 'docx':
      return Icons.description_rounded;
    case 'xls':
    case 'xlsx':
      return Icons.table_chart_rounded;
    case 'ppt':
    case 'pptx':
      return Icons.slideshow_rounded;
    case 'zip':
    case 'rar':
      return Icons.folder_zip_rounded;
    default:
      return Icons.insert_drive_file_rounded;
  }
}

Uint8List _bytesFromBase64(String data) {
  final base64Part = data.contains(',') ? data.split(',').last : data;
  return base64Decode(base64Part);
}

// Web download for a received file attachment — mirrors every other
// "Export" button in the org portal (OrgExportUtil.saveBytes).
Future<void> _downloadFileAttachment(
  BuildContext context,
  String fileBase64,
  String fileName,
) async {
  try {
    final bytes = _bytesFromBase64(fileBase64);
    await OrgExportUtil.saveBytes(
      bytes,
      fileName,
      mimeType: _mimeTypeFromFileName(fileName),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not download file: $e')));
    }
  }
}

final RegExp _urlPattern = RegExp(
  r'((https?:\/\/|www\.)[^\s]+)',
  caseSensitive: false,
);

Future<void> _openLink(BuildContext context, String rawUrl) async {
  final url = rawUrl.toLowerCase().startsWith('http')
      ? rawUrl
      : 'https://$rawUrl';
  final uri = Uri.tryParse(url);
  final opened = uri != null && await canLaunchUrl(uri)
      ? await launchUrl(uri, mode: LaunchMode.externalApplication)
      : false;
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open that link.')));
  }
}

// Splits message text on URLs and renders each match as tappable, launchable
// text — same tap-to-open treatment as org_profile.dart's social links —
// instead of a link sitting in a message as inert plain text.
Widget _linkifiedText(
  BuildContext context,
  String text, {
  required TextStyle style,
  required Color linkColor,
}) {
  final matches = _urlPattern.allMatches(text).toList();
  if (matches.isEmpty) return Text(text, style: style);

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    final url = match.group(0)!;
    spans.add(
      TextSpan(
        text: url,
        style: style.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => _openLink(context, url),
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return Text.rich(TextSpan(style: style, children: spans));
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// A pending server timestamp reads as null for the brief moment before it
// round-trips — falls back to "now" for grouping purposes only, so a
// just-sent message doesn't briefly float without a date header.
String _formatDateSeparator(DateTime d) {
  final now = DateTime.now();
  final diff = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('MMMM d, yyyy').format(d);
}

// Marks where a date separator belongs in the interleaved message list —
// see the "chronological grouping" comment in _ChatThreadState.build().
class _DateSeparator {
  final DateTime date;
  const _DateSeparator(this.date);
}

Widget _dateSeparatorPill(DateTime date) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: _C.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _C.border),
        ),
        child: Text(
          _formatDateSeparator(date),
          style: GoogleFonts.beVietnamPro(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _C.darkGray,
          ),
        ),
      ),
    ),
  );
}

// Long-press action sheet — Reply is always offered; Report or Delete is
// whichever one applies to that message (never both, since you can't report
// your own message or delete someone else's).
void _showMessageActions(
  BuildContext context, {
  required VoidCallback onReply,
  VoidCallback? onReport,
  VoidCallback? onDelete,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: _C.primaryDark),
              title: Text(
                'Reply',
                style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onReply();
              },
            ),
            if (onReport != null)
              ListTile(
                leading: const Icon(
                  Icons.flag_outlined,
                  color: Color(0xFFDC2626),
                ),
                title: Text(
                  'Report',
                  style: GoogleFonts.beVietnamPro(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFDC2626),
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onReport();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFDC2626),
                ),
                title: Text(
                  'Delete',
                  style: GoogleFonts.beVietnamPro(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFDC2626),
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

// Full-size, pinch-to-zoom image viewer — tapping a photo message used to do
// nothing, the 200px thumbnail was the only way to see it.
void _showImagePreview(BuildContext context, String imageBase64) {
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: Image(image: _imageProviderFromBase64(imageBase64)),
              ),
            ),
          ),
        ),
        Positioned(
          top: 24,
          right: 24,
          child: IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () => Navigator.pop(ctx),
          ),
        ),
      ],
    ),
  );
}

const List<String> _reportReasons = [
  'Spam',
  'Inappropriate content',
  'Harassment',
  'Other',
];

// Shared by both sides of this chat (org here, student in
// student_broadcast_screen.dart) — writes to `message_reports` for later
// admin review. There's no report-review queue UI yet; this is the
// reporting mechanism itself.
Future<void> showReportMessageDialog(
  BuildContext context, {
  required String conversationId,
  required String messageId,
  required String messageText,
  required String reporterRole,
  required String reportedUserId,
  required String reportedUserRole,
}) async {
  String selectedReason = _reportReasons.first;
  final detailsCtrl = TextEditingController();
  final submitted = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(
          'Report message',
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Why are you reporting this message?',
                style: GoogleFonts.beVietnamPro(fontSize: 13),
              ),
              const SizedBox(height: 8),
              for (final reason in _reportReasons)
                RadioListTile<String>(
                  value: reason,
                  groupValue: selectedReason,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    reason,
                    style: GoogleFonts.beVietnamPro(fontSize: 13),
                  ),
                  onChanged: (v) => setDialogState(() => selectedReason = v!),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: detailsCtrl,
                maxLines: 2,
                style: GoogleFonts.beVietnamPro(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Additional details (optional)',
                  hintStyle: GoogleFonts.beVietnamPro(fontSize: 12),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Report'),
          ),
        ],
      ),
    ),
  );
  if (submitted != true) return;

  final reporter = FirebaseAuth.instance.currentUser;
  try {
    await FirebaseFirestore.instance.collection('message_reports').add({
      'conversationId': conversationId,
      'messageId': messageId,
      'messageText': messageText,
      'reporterId': reporter?.uid ?? '',
      'reporterRole': reporterRole,
      'reportedUserId': reportedUserId,
      'reportedUserRole': reportedUserRole,
      'reason': selectedReason,
      'details': detailsCtrl.text.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message reported. Thanks for flagging it.'),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not submit report: $e')));
    }
  }
}

String _conversationId(String orgId, String studentId) => '${orgId}_$studentId';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

String _relativeTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat('MMM d').format(dt);
}

class OrgBroadcastScreen extends StatefulWidget {
  final String orgId;
  final String orgName;
  const OrgBroadcastScreen({
    super.key,
    required this.orgId,
    this.orgName = 'Organization',
  });

  @override
  State<OrgBroadcastScreen> createState() => _OrgBroadcastScreenState();
}

class _OrgBroadcastScreenState extends State<OrgBroadcastScreen> {
  String? _selectedConversationId;
  Map<String, dynamic>? _selectedConversation;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _orgName = '';
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
      () =>
          setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase()),
    );
    _loadOrgName();
  }

  Future<void> _loadOrgName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .get();
      final data = doc.data();
      if (data != null && mounted) {
        setState(
          () => _orgName = data['name'] ?? data['orgName'] ?? widget.orgName,
        );
      }
    } catch (_) {
      _orgName = widget.orgName;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openConversation(String id, Map<String, dynamic> data) {
    setState(() {
      _selectedConversationId = id;
      _selectedConversation = data;
    });
    FirebaseFirestore.instance
        .collection('conversations')
        .doc(id)
        .update({'unreadForOrg': false})
        .catchError((_) {});
  }

  Future<void> _openNewMessageDialog() async {
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _StudentPickerDialog(orgId: widget.orgId),
    );
    if (picked == null) return;
    final studentId = picked['id'] as String;
    final studentName = picked['name'] as String;
    final id = _conversationId(widget.orgId, studentId);
    final ref = FirebaseFirestore.instance.collection('conversations').doc(id);
    try {
      final existing = await ref.get();
      if (!existing.exists) {
        await ref.set({
          'orgId': widget.orgId,
          'orgName': _orgName.isEmpty ? widget.orgName : _orgName,
          'studentId': studentId,
          'studentName': studentName,
          'lastMessage': '',
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastSenderRole': 'org',
          'unreadForOrg': false,
          'unreadForStudent': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      final fresh = await ref.get();
      if (!mounted) return;
      _openConversation(id, fresh.data() ?? {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\'t start conversation: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.pageBg,
      body: Row(
        children: [
          SizedBox(
            width: 340,
            child: _ConversationsList(
              orgId: widget.orgId,
              searchQuery: _searchQuery,
              searchController: _searchCtrl,
              selectedId: _selectedConversationId,
              onSelect: _openConversation,
              onNewMessage: _openNewMessageDialog,
              showArchived: _showArchived,
              onToggleArchivedView: () =>
                  setState(() => _showArchived = !_showArchived),
            ),
          ),
          const VerticalDivider(width: 1, color: _C.border),
          Expanded(
            child: _selectedConversationId == null
                ? const _EmptyThreadState()
                : _ChatThread(
                    key: ValueKey(_selectedConversationId),
                    conversationId: _selectedConversationId!,
                    conversation: _selectedConversation ?? {},
                    orgId: widget.orgId,
                    orgName: _orgName.isEmpty ? widget.orgName : _orgName,
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Conversations list (left panel)
// ─────────────────────────────────────────────────────────────────────────────
class _ConversationsList extends StatelessWidget {
  final String orgId;
  final String searchQuery;
  final TextEditingController searchController;
  final String? selectedId;
  final void Function(String id, Map<String, dynamic> data) onSelect;
  final VoidCallback onNewMessage;
  final bool showArchived;
  final VoidCallback onToggleArchivedView;

  const _ConversationsList({
    required this.orgId,
    required this.searchQuery,
    required this.searchController,
    required this.selectedId,
    required this.onSelect,
    required this.onNewMessage,
    required this.showArchived,
    required this.onToggleArchivedView,
  });

  Future<void> _toggleArchived(String conversationId, bool currentlyArchived) {
    return FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .update({'archivedByOrg': !currentlyArchived});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Messages',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _C.charcoal,
                  ),
                ),
              ),
              IconButton(
                onPressed: onToggleArchivedView,
                tooltip: showArchived ? 'Show active chats' : 'Show archived',
                icon: Icon(
                  showArchived ? Icons.inbox_rounded : Icons.archive_outlined,
                  color: showArchived ? _C.primaryDark : _C.darkGray,
                  size: 20,
                ),
              ),
              IconButton(
                onPressed: onNewMessage,
                tooltip: 'New message',
                icon: const Icon(
                  Icons.edit_square,
                  color: _C.primaryDark,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        if (showArchived)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Viewing archived conversations',
              style: GoogleFonts.beVietnamPro(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _C.darkGray,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: searchController,
              style: GoogleFonts.beVietnamPro(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search students…',
                hintStyle: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: _C.textFaint,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: _C.textFaint,
                ),
                filled: true,
                fillColor: _C.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('conversations')
                .where('orgId', isEqualTo: orgId)
                .orderBy('lastMessageAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                // Logged (not just swallowed) because the most common cause
                // on first deploy is a missing Firestore composite index —
                // the thrown error includes a direct link to auto-create it.
                debugPrint('conversations query error: ${snap.error}');
                return Center(
                  child: Text(
                    'Couldn\'t load conversations',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: _C.darkGray,
                    ),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: _C.primaryDark),
                );
              }
              var docs = snap.data!.docs.where((d) {
                final archived =
                    (d.data() as Map<String, dynamic>)['archivedByOrg'] == true;
                return showArchived ? archived : !archived;
              }).toList();
              if (searchQuery.isNotEmpty) {
                docs = docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final name = (data['studentName'] ?? '')
                      .toString()
                      .toLowerCase();
                  return name.contains(searchQuery);
                }).toList();
              }
              if (docs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      searchQuery.isNotEmpty
                          ? 'No students match your search.'
                          : (showArchived
                                ? 'No archived conversations.'
                                : 'No conversations yet.\nTap the compose icon to message a student.'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: _C.textFaint,
                      ),
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final isSelected = doc.id == selectedId;
                  final unread = data['unreadForOrg'] == true;
                  final lastAt = (data['lastMessageAt'] as Timestamp?)
                      ?.toDate();
                  final lastMsg = (data['lastMessage'] ?? '').toString();
                  final lastSenderRole = data['lastSenderRole'] ?? 'student';
                  final studentName = (data['studentName'] ?? 'Student')
                      .toString();

                  return InkWell(
                    onTap: () => onSelect(doc.id, data),
                    child: Container(
                      color: isSelected
                          ? _C.primaryDark.withAlpha(15)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: _C.primaryDark.withAlpha(28),
                            child: Text(
                              _initials(studentName),
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _C.primaryDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  studentName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13.5,
                                    fontWeight: unread
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: _C.charcoal,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  lastMsg.isEmpty
                                      ? 'No messages yet'
                                      : '${lastSenderRole == 'org' ? 'You: ' : ''}$lastMsg',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12,
                                    fontWeight: unread
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: unread ? _C.charcoal : _C.darkGray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (lastAt != null)
                                Text(
                                  _relativeTime(lastAt),
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 10.5,
                                    color: unread
                                        ? _C.primaryDark
                                        : _C.textFaint,
                                    fontWeight: unread
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              if (unread) ...[
                                const SizedBox(height: 5),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: _C.primaryDark,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Tooltip(
                            message: showArchived ? 'Unarchive' : 'Archive',
                            child: InkWell(
                              onTap: () =>
                                  _toggleArchived(doc.id, showArchived),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  showArchived
                                      ? Icons.unarchive_outlined
                                      : Icons.archive_outlined,
                                  size: 17,
                                  color: _C.textFaint,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyThreadState extends StatelessWidget {
  const _EmptyThreadState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _C.primaryDark.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 32,
              color: _C.primaryDark,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Select a conversation',
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _C.charcoal,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Send announcements straight to a student — they can\n'
            'view them here but can\'t reply.',
            textAlign: TextAlign.center,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12.5,
              color: _C.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Student picker (New Message)
// ─────────────────────────────────────────────────────────────────────────────
class _StudentPickerDialog extends StatefulWidget {
  final String orgId;
  const _StudentPickerDialog({required this.orgId});

  @override
  State<_StudentPickerDialog> createState() => _StudentPickerDialogState();
}

class _StudentPickerDialogState extends State<_StudentPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'New message',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                autofocus: true,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                style: GoogleFonts.beVietnamPro(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search students by name…',
                  hintStyle: GoogleFonts.beVietnamPro(fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  filled: true,
                  fillColor: _C.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('students')
                        .where('orgId', isEqualTo: widget.orgId)
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: CircularProgressIndicator(
                              color: _C.primaryDark,
                            ),
                          ),
                        );
                      }
                      var docs = snap.data!.docs;
                      docs = docs.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        final name = (data['fullName'] ?? '')
                            .toString()
                            .toLowerCase();
                        return _query.isEmpty || name.contains(_query);
                      }).toList();
                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'No students found',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                color: _C.textFaint,
                              ),
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final data = docs[i].data() as Map<String, dynamic>;
                          final name = (data['fullName'] ?? 'Student')
                              .toString();
                          final uid = (data['uid'] ?? docs[i].id).toString();
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _C.primaryDark.withAlpha(28),
                              child: Text(
                                _initials(name),
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _C.primaryDark,
                                ),
                              ),
                            ),
                            title: Text(
                              name,
                              style: GoogleFonts.beVietnamPro(fontSize: 13.5),
                            ),
                            subtitle: Text(
                              (data['course'] ?? '').toString(),
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11.5,
                                color: _C.textFaint,
                              ),
                            ),
                            onTap: () => Navigator.pop(context, {
                              'id': uid,
                              'name': name,
                            }),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat thread (right panel)
// ─────────────────────────────────────────────────────────────────────────────
class _ChatThread extends StatefulWidget {
  final String conversationId;
  final Map<String, dynamic> conversation;
  final String orgId;
  final String orgName;

  const _ChatThread({
    super.key,
    required this.conversationId,
    required this.conversation,
    required this.orgId,
    required this.orgName,
  });

  @override
  State<_ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<_ChatThread> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _sending = false;
  // Set via the long-press "Reply" action; cleared on send or by the X on
  // the reply preview bar above the input.
  Map<String, dynamic>? _replyingTo;

  String get _studentName =>
      (widget.conversation['studentName'] ?? 'Student').toString();
  String get _studentId => (widget.conversation['studentId'] ?? '').toString();

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _startReply(String messageId, String text, String senderName) {
    setState(() {
      _replyingTo = {
        'id': messageId,
        'text': text.isEmpty ? 'Attachment' : text,
        'senderName': senderName,
      };
    });
  }

  Future<void> _sendMessage({
    String? imageBase64,
    String? fileBase64,
    String? fileName,
  }) async {
    final rawText = _textCtrl.text.trim();
    if (rawText.isEmpty && imageBase64 == null && fileBase64 == null) return;
    final text = ProfanityFilter.filter(rawText);
    final replyingTo = _replyingTo;
    setState(() {
      _sending = true;
      _replyingTo = null;
    });
    _textCtrl.clear();

    final user = FirebaseAuth.instance.currentUser;
    final ref = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId);
    final previewText = text.isNotEmpty
        ? text
        : (imageBase64 != null ? 'Sent an image' : 'Sent a file: $fileName');
    try {
      await ref.collection('messages').add({
        'senderId': user?.uid ?? '',
        'senderRole': 'org',
        'senderName': widget.orgName,
        'text': text,
        'imageBase64': imageBase64,
        'fileBase64': fileBase64,
        'fileName': fileName,
        if (replyingTo != null) 'replyToMessageId': replyingTo['id'],
        if (replyingTo != null) 'replyToText': replyingTo['text'],
        if (replyingTo != null) 'replyToSenderName': replyingTo['senderName'],
        'timestamp': FieldValue.serverTimestamp(),
      });
      await ref.update({
        'lastMessage': previewText,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderRole': 'org',
        'unreadForStudent': true,
      });
      if (_studentId.isNotEmpty) {
        await NotificationService.sendToUser(
          userId: _studentId,
          title: widget.orgName,
          body: previewText,
          type: 'private_message',
          orgId: widget.orgId,
          orgName: widget.orgName,
        );
      }
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        _textCtrl.text = rawText;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Message failed to send: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleBlock(bool currentlyBlocked) async {
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .update({'blockedByOrg': !currentlyBlocked});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !currentlyBlocked
                ? '$_studentName is now blocked from messaging this org.'
                : '$_studentName can message this org again.',
          ),
        ),
      );
    }
  }

  Future<void> _confirmDeleteMessage(String messageId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete message?',
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This removes it for both you and $_studentName. This can\'t be undone.',
          style: GoogleFonts.beVietnamPro(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final ref = FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId);
      await ref.collection('messages').doc(messageId).delete();
      // The conversation list preview shows lastMessage/lastMessageAt — if
      // the deleted message was the latest one, recompute those from
      // whatever's now actually the newest remaining message instead of
      // leaving a stale preview of a message that no longer exists.
      final latestSnap = await ref
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      if (latestSnap.docs.isNotEmpty) {
        final latest = latestSnap.docs.first.data();
        final latestText = (latest['text'] ?? '').toString();
        final latestFileName = (latest['fileName'] ?? '').toString();
        final preview = latestText.isNotEmpty
            ? latestText
            : (latest['imageBase64'] != null
                  ? 'Sent an image'
                  : (latestFileName.isNotEmpty
                        ? 'Sent a file: $latestFileName'
                        : ''));
        await ref.update({
          'lastMessage': preview,
          'lastMessageAt': latest['timestamp'] ?? FieldValue.serverTimestamp(),
          'lastSenderRole': latest['senderRole'] ?? 'org',
        });
      } else {
        await ref.update({'lastMessage': '', 'lastSenderRole': 'org'});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete message: $e')));
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 80,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      // Firestore caps a single document at ~1MiB; base64 inflates the raw
      // bytes by ~33%, so keep a safety margin well under that ceiling
      // rather than let a large photo fail with a raw Firestore error.
      if (bytes.length > 700 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'That image is too large to send. Please choose a smaller photo.',
              ),
            ),
          );
        }
        return;
      }
      final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      await _sendMessage(imageBase64: b64);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Couldn\'t attach image: $e')));
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;
      // Same ceiling as images — Firestore caps a single document at ~1MiB
      // and base64 inflates raw bytes by ~33%.
      if (bytes.length > 700 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'That file is too large to send. Please choose a smaller file (under ~700KB).',
              ),
            ),
          );
        }
        return;
      }
      final mime = _mimeTypeFromFileName(file.name);
      final b64 = 'data:$mime;base64,${base64Encode(bytes)}';
      await _sendMessage(fileBase64: b64, fileName: file.name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Couldn\'t attach file: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Streamed (not read from widget.conversation, which is a one-time
    // snapshot from when the thread was opened) so a block/unblock toggle
    // reflects immediately without needing to reopen the conversation.
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .snapshots(),
      builder: (context, convoSnap) {
        final convoData = convoSnap.data?.data() as Map<String, dynamic>? ?? {};
        final blocked = convoData['blockedByOrg'] == true;
        final archived = convoData['archivedByOrg'] == true;
        return _buildBody(context, blocked, archived);
      },
    );
  }

  Future<void> _toggleArchived(bool currentlyArchived) async {
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .update({'archivedByOrg': !currentlyArchived});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !currentlyArchived
                ? 'Conversation archived.'
                : 'Conversation unarchived.',
          ),
        ),
      );
    }
  }

  Widget _buildBody(BuildContext context, bool blocked, bool archived) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            color: _C.white,
            border: Border(bottom: BorderSide(color: _C.border)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _C.primaryDark.withAlpha(28),
                child: Text(
                  _initials(_studentName),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _C.primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _studentName,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _C.charcoal,
                  ),
                ),
              ),
              if (blocked)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withAlpha(24),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Blocked',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ),
              IconButton(
                onPressed: () => _toggleArchived(archived),
                icon: Icon(
                  archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                  color: _C.darkGray,
                  size: 20,
                ),
                tooltip: archived ? 'Unarchive' : 'Archive',
              ),
              IconButton(
                onPressed: () => _toggleBlock(blocked),
                icon: Icon(
                  blocked ? Icons.lock_open_rounded : Icons.block_rounded,
                  color: blocked ? _C.darkGray : const Color(0xFFDC2626),
                  size: 20,
                ),
                tooltip: blocked
                    ? 'Unblock $_studentName'
                    : 'Block $_studentName',
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: _C.surface,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('conversations')
                  .doc(widget.conversationId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _C.primaryDark),
                  );
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet — say hello!',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: _C.textFaint,
                      ),
                    ),
                  );
                }
                // docs[0] is newest (query is descending); interleave a
                // date-separator marker right after the oldest message of
                // each day so it renders as a header above that day's group
                // once the reversed ListView lays it out bottom-to-top.
                final items = <Object>[];
                for (var i = 0; i < docs.length; i++) {
                  items.add(docs[i]);
                  final day =
                      ((docs[i].data() as Map<String, dynamic>)['timestamp']
                              as Timestamp?)
                          ?.toDate() ??
                      DateTime.now();
                  final nextDay = i + 1 < docs.length
                      ? ((docs[i + 1].data()
                                    as Map<String, dynamic>)['timestamp']
                                as Timestamp?)
                            ?.toDate()
                      : null;
                  if (nextDay == null || !_isSameDay(day, nextDay)) {
                    items.add(_DateSeparator(day));
                  }
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    if (item is _DateSeparator) {
                      return _dateSeparatorPill(item.date);
                    }
                    final doc = item as QueryDocumentSnapshot;
                    final data = doc.data() as Map<String, dynamic>;
                    final isOrg = data['senderRole'] == 'org';
                    final text = (data['text'] ?? '').toString();
                    final image = data['imageBase64'] as String?;
                    final fileBase64 = data['fileBase64'] as String?;
                    final fileName = data['fileName'] as String?;
                    final ts = (data['timestamp'] as Timestamp?)?.toDate();
                    final replyToText = data['replyToText'] as String?;
                    final replyToSenderName =
                        data['replyToSenderName'] as String?;
                    return _MessageBubble(
                      isMe: isOrg,
                      text: text,
                      imageBase64: image,
                      fileBase64: fileBase64,
                      fileName: fileName,
                      time: ts != null ? DateFormat('h:mm a').format(ts) : '',
                      replyToText: replyToText,
                      replyToSenderName: replyToSenderName,
                      onReport: isOrg
                          ? null
                          : () => showReportMessageDialog(
                              context,
                              conversationId: widget.conversationId,
                              messageId: doc.id,
                              messageText: text,
                              reporterRole: 'org',
                              reportedUserId: (data['senderId'] ?? '')
                                  .toString(),
                              reportedUserRole: 'student',
                            ),
                      onDelete: isOrg
                          ? () => _confirmDeleteMessage(doc.id)
                          : null,
                      onReply: () => _startReply(
                        doc.id,
                        text,
                        isOrg ? widget.orgName : _studentName,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        if (_replyingTo != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: _C.surface,
              border: Border(top: BorderSide(color: _C.border)),
            ),
            child: Row(
              children: [
                Container(width: 3, height: 30, color: _C.primaryDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Replying to ${_replyingTo!['senderName']}',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _C.primaryDark,
                        ),
                      ),
                      Text(
                        (_replyingTo!['text'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: _C.darkGray,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _replyingTo = null),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: _C.darkGray,
                  ),
                  tooltip: 'Cancel reply',
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: _C.white,
            border: Border(top: BorderSide(color: _C.border)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: _sending ? null : _pickImage,
                icon: const Icon(Icons.image_outlined, color: _C.darkGray),
                tooltip: 'Attach image',
              ),
              IconButton(
                onPressed: _sending ? null : _pickFile,
                icon: const Icon(Icons.attach_file_rounded, color: _C.darkGray),
                tooltip: 'Attach file',
              ),
              Expanded(
                child: TextField(
                  controller: _textCtrl,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  style: GoogleFonts.beVietnamPro(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Message $_studentName…',
                    hintStyle: GoogleFonts.beVietnamPro(
                      fontSize: 13.5,
                      color: _C.textFaint,
                    ),
                    filled: true,
                    fillColor: _C.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _sending ? null : () => _sendMessage(),
                style: IconButton.styleFrom(
                  backgroundColor: _C.primaryDark,
                  disabledBackgroundColor: _C.primaryDark.withAlpha(120),
                ),
                icon: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool isMe;
  final String text;
  final String? imageBase64;
  final String? fileBase64;
  final String? fileName;
  final String time;
  final String? replyToText;
  final String? replyToSenderName;
  // Only set for the other person's messages — reporting your own message
  // makes no sense, so the report option simply doesn't appear on isMe
  // bubbles' long-press menu.
  final VoidCallback? onReport;
  // Only set for your own messages — the counterpart of onReport.
  final VoidCallback? onDelete;
  final VoidCallback? onReply;

  const _MessageBubble({
    required this.isMe,
    required this.text,
    required this.imageBase64,
    this.fileBase64,
    this.fileName,
    required this.time,
    this.replyToText,
    this.replyToSenderName,
    this.onReport,
    this.onDelete,
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isMe ? _C.primaryDark : Colors.white;
    final fg = isMe ? Colors.white : _C.charcoal;
    final hasImage = imageBase64 != null;
    final hasFile = fileBase64 != null && fileName != null;
    final hasText = text.isNotEmpty;
    final hasReply = (replyToText ?? '').isNotEmpty;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 16),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onReply == null
            ? (onReport ?? onDelete)
            : () => _showMessageActions(
                context,
                onReply: onReply!,
                onReport: onReport,
                onDelete: onDelete,
              ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  // An image fills the bubble edge-to-edge like a real photo
                  // message instead of sitting inside a colored frame — the
                  // color only applies when there's no image, or as a
                  // caption strip below one. A file chip or reply quote
                  // always keeps the colored background, same as plain text.
                  color: hasImage && !hasText && !hasReply ? null : bg,
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasReply)
                      Container(
                        margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: (isMe ? Colors.white : _C.primaryDark)
                              .withAlpha(isMe ? 40 : 14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              color: isMe ? Colors.white : _C.primaryDark,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              replyToSenderName ?? '',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: fg,
                              ),
                            ),
                            Text(
                              replyToText!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11.5,
                                color: fg.withAlpha(210),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (hasImage)
                      GestureDetector(
                        onTap: () => _showImagePreview(context, imageBase64!),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Image(
                            image: _imageProviderFromBase64(imageBase64!),
                            width: 260,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    if (hasFile)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => _downloadFileAttachment(
                              context,
                              fileBase64!,
                              fileName!,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: (isMe ? Colors.white : _C.primaryDark)
                                    .withAlpha(isMe ? 40 : 14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _iconForFileName(fileName!),
                                    size: 20,
                                    color: fg,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      fileName!,
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: fg,
                                        decoration: TextDecoration.underline,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.download_rounded,
                                    size: 16,
                                    color: fg,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (hasText)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: _linkifiedText(
                          context,
                          text,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13.5,
                            color: fg,
                          ),
                          linkColor: isMe ? Colors.white : _C.primaryDark,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                time,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 10,
                  color: _C.textFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
