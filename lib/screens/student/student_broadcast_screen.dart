
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../widgets/student/app_colors.dart';
import '../../services/notification_service.dart';
import '../../services/activity_logger.dart' as activity_log;
import '../../utils/profanity_filter.dart';

// MemoryImage's cache key is the decoded bytes object itself, not the
// source string — calling base64Decode() fresh on every build (which
// happens on every message-list rebuild, e.g. after sending a message)
// produced a *new* Uint8List each time, which Flutter's image cache can
// never recognize as "the same image already loaded." That forced a full
// re-decode + repaint from scratch on every action, which is exactly what
// showed up as photos visibly glitching/reloading. Caching the decoded
// MemoryImage per source string means the same object is reused, so the
// cache actually hits — mirrors org_profile.dart's identical fix.
final Map<String, MemoryImage> _memoryImageCache = {};

ImageProvider _imageProviderFromBase64(String data) {
  return _memoryImageCache.putIfAbsent(data, () {
    final base64Part = data.contains(',') ? data.split(',').last : data;
    return MemoryImage(base64Decode(base64Part));
  });
}

Uint8List _bytesFromBase64(String data) {
  final base64Part = data.contains(',') ? data.split(',').last : data;
  return base64Decode(base64Part);
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

// Mobile has no "download" concept like a browser — write the bytes to a
// temp file and hand it to the OS share sheet, same pattern already used
// for attachment downloads in student_announcements_screen.dart. That lets
// the user save it, open it in another app, or share it onward.
Future<void> _openFileAttachment(
  BuildContext context,
  String fileBase64,
  String fileName,
) async {
  try {
    final bytes = _bytesFromBase64(fileBase64);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: fileName);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open file: $e')));
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
// see the "chronological grouping" comment in the messages StreamBuilder.
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Text(
          _formatDateSeparator(date),
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.reply_rounded,
                color: AppColors.primaryDark,
              ),
              title: Text(
                'Reply',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
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
                  style: GoogleFonts.poppins(
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
                  style: GoogleFonts.poppins(
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
// nothing, the thumbnail was the only way to see it.
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

String _conversationId(String orgId, String studentId) => '${orgId}_$studentId';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

const List<String> _reportReasons = [
  'Spam',
  'Inappropriate content',
  'Harassment',
  'Other',
];

// Mirrors showReportMessageDialog in org_broadcast.dart — logs straight to
// activity_logs so admins see reported messages in the existing Activity
// Logs page instead of a separate review queue.
Future<void> _showReportMessageDialog(
  BuildContext context, {
  required String conversationId,
  required String messageId,
  required String messageText,
  required String reportedUserId,
  required String reportedUserRole,
  required String orgId,
}) async {
  String selectedReason = _reportReasons.first;
  final detailsCtrl = TextEditingController();
  final submitted = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(
          'Report message',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          // AlertDialog's own default insetPadding already reserves ~40px
          // per side, so sizing against the full screen width (as the
          // previous hardcoded 360 effectively assumed on narrow phones)
          // pushed this past the actual available space.
          width: (MediaQuery.of(ctx).size.width - 80).clamp(0, 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Why are you reporting this message?',
                style: GoogleFonts.poppins(fontSize: 13),
              ),
              const SizedBox(height: 8),
              for (final reason in _reportReasons)
                RadioListTile<String>(
                  value: reason,
                  groupValue: selectedReason,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(reason, style: GoogleFonts.poppins(fontSize: 13)),
                  onChanged: (v) => setDialogState(() => selectedReason = v!),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: detailsCtrl,
                maxLines: 2,
                style: GoogleFonts.poppins(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Additional details (optional)',
                  hintStyle: GoogleFonts.poppins(fontSize: 12),
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

  try {
    await activity_log.ActivityLogger.log(
      action:
          'Reported a message from a ${reportedUserRole.isEmpty ? 'user' : reportedUserRole} ($selectedReason)',
      module: 'Message Reports',
      severity: 'warning',
      orgId: orgId,
      details: {
        'orgId': orgId,
        'conversationId': conversationId,
        'messageId': messageId,
        'messageText': messageText,
        'reporterRole': 'student',
        'reportedUserId': reportedUserId,
        'reportedUserRole': reportedUserRole,
        'reason': selectedReason,
        'details': detailsCtrl.text.trim(),
      },
    );
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

class StudentBroadcastScreen extends StatefulWidget {
  final String orgId;
  final String orgName;

  const StudentBroadcastScreen({
    super.key,
    required this.orgId,
    required this.orgName,
  });

  @override
  State<StudentBroadcastScreen> createState() => _StudentBroadcastScreenState();
}

class _StudentBroadcastScreenState extends State<StudentBroadcastScreen> {
  late final String _conversationDocId;
  late final String _studentId;
  bool _ready = false;
  bool _sending = false;
  String _studentName = 'Student';
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  // Set via the long-press "Reply" action; cleared on send or by the X on
  // the reply preview bar above the input.
  Map<String, dynamic>? _replyingTo;

  void _startReply(String messageId, String text, String senderName) {
    setState(() {
      _replyingTo = {
        'id': messageId,
        'text': text.isEmpty ? 'Attachment' : text,
        'senderName': senderName,
      };
    });
  }

  @override
  void initState() {
    super.initState();
    _studentId = FirebaseAuth.instance.currentUser?.uid ?? '';
    _conversationDocId = _conversationId(widget.orgId, _studentId);
    _init();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(_studentId)
          .get();
      final data = studentDoc.data();
      // students docs store the display name under `fullName` (with
      // `firstName`/`lastName` as a fallback for older records) everywhere
      // else in the app — this screen was the one place still reading a
      // `name` field that doesn't exist on this collection, so every
      // student showed up as the literal fallback "Student" in the org's
      // inbox instead of their actual name.
      final fullName = (data?['fullName'] ?? '').toString().trim();
      final firstName = (data?['firstName'] ?? '').toString().trim();
      final lastName = (data?['lastName'] ?? '').toString().trim();
      final resolvedName = fullName.isNotEmpty
          ? fullName
          : [firstName, lastName].where((s) => s.isNotEmpty).join(' ').trim();
      if (resolvedName.isNotEmpty) _studentName = resolvedName;

      final ref = FirebaseFirestore.instance
          .collection('conversations')
          .doc(_conversationDocId);
      final existing = await ref.get();
      if (existing.exists) {
        final updates = <String, dynamic>{'unreadForStudent': false};
        // Self-heal conversations created while the `name`-vs-`fullName`
        // bug above was live — those got stuck showing the generic
        // "Student" fallback in the org's inbox forever, since studentName
        // is only ever set once, at conversation creation.
        final storedName = (existing.data()?['studentName'] ?? '').toString();
        if (resolvedName.isNotEmpty && storedName != resolvedName) {
          updates['studentName'] = resolvedName;
        }
        await ref.update(updates);
      }
    } catch (_) {
      // Non-fatal — the thread still renders either way.
    } finally {
      if (mounted) setState(() => _ready = true);
    }
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

    final ref = FirebaseFirestore.instance
        .collection('conversations')
        .doc(_conversationDocId);
    try {
      final existing = await ref.get();
      if (!existing.exists) {
        await ref.set({
          'orgId': widget.orgId,
          'orgName': widget.orgName,
          'studentId': _studentId,
          'studentName': _studentName,
          'lastMessage': '',
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastSenderRole': 'student',
          'unreadForOrg': false,
          'unreadForStudent': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else if (existing.data()?['blockedByOrg'] == true) {
        // Guard against a stale UI (block toggled between screen-open and
        // send) — the input bar already hides itself when blocked, but this
        // closes the race.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This org has blocked you from sending messages.'),
            ),
          );
          _textCtrl.text = rawText;
        }
        return;
      }

      final previewText = text.isNotEmpty
          ? text
          : (imageBase64 != null ? 'Sent an image' : 'Sent a file: $fileName');
      await ref.collection('messages').add({
        'senderId': _studentId,
        'senderRole': 'student',
        'senderName': _studentName,
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
        'lastSenderRole': 'student',
        'unreadForOrg': true,
      });
      await NotificationService.sendToOrgAccount(
        orgId: widget.orgId,
        title: _studentName,
        body: previewText,
        type: 'private_message',
        data: {'studentId': _studentId},
      );
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

  Future<void> _confirmDeleteMessage(String messageId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete message?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This removes it for both you and ${widget.orgName}. This can\'t be undone.',
          style: GoogleFonts.poppins(fontSize: 13),
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
          .doc(_conversationDocId);
      await ref.collection('messages').doc(messageId).delete();
      // The org's conversation-list preview shows lastMessage/lastMessageAt
      // — if the deleted message was the latest one, recompute those from
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
        await ref.update({
          'lastMessage': latestText.isEmpty ? 'Sent an image' : latestText,
          'lastMessageAt': latest['timestamp'] ?? FieldValue.serverTimestamp(),
          'lastSenderRole': latest['senderRole'] ?? 'student',
        });
      } else {
        await ref.update({'lastMessage': '', 'lastSenderRole': 'student'});
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
      final b64 = 'data:application/octet-stream;base64,${base64Encode(bytes)}';
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
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.primaryDark.withAlpha(28),
              child: Text(
                _initials(widget.orgName),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.orgName,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: !_ready
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryDark),
            )
          // Streamed (not read once) so a block toggled by the org while
          // this screen is open disables the input bar immediately.
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('conversations')
                  .doc(_conversationDocId)
                  .snapshots(),
              builder: (context, convoSnap) {
                final convoData =
                    convoSnap.data?.data() as Map<String, dynamic>? ?? {};
                final blocked = convoData['blockedByOrg'] == true;
                return Column(
                  children: [
                    if (blocked)
                      Container(
                        width: double.infinity,
                        color: const Color(0xFFFEE2E2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          'This org has restricted messaging with you. You can still view past messages but can\'t send new ones.',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: const Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('conversations')
                            .doc(_conversationDocId)
                            .collection('messages')
                            .orderBy('timestamp', descending: true)
                            .snapshots(),
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primaryDark,
                              ),
                            );
                          }
                          final docs = snap.data!.docs;
                          if (docs.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      size: 40,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No messages yet — say hello to ${widget.orgName}!',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          // docs[0] is newest (query is descending);
                          // interleave a date-separator marker right after
                          // the oldest message of each day so it renders as
                          // a header above that day's group once the
                          // reversed ListView lays it out bottom-to-top.
                          final items = <Object>[];
                          for (var i = 0; i < docs.length; i++) {
                            items.add(docs[i]);
                            final day =
                                ((docs[i].data()
                                            as Map<
                                              String,
                                              dynamic
                                            >)['timestamp']
                                        as Timestamp?)
                                    ?.toDate() ??
                                DateTime.now();
                            final nextDay = i + 1 < docs.length
                                ? ((docs[i + 1].data()
                                              as Map<
                                                String,
                                                dynamic
                                              >)['timestamp']
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
                              final isFromStudent =
                                  data['senderRole'] == 'student';
                              final text = (data['text'] ?? '').toString();
                              final image = data['imageBase64'] as String?;
                              final fileBase64 = data['fileBase64'] as String?;
                              final fileName = data['fileName'] as String?;
                              final ts = (data['timestamp'] as Timestamp?)
                                  ?.toDate();
                              final replyToText =
                                  data['replyToText'] as String?;
                              final replyToSenderName =
                                  data['replyToSenderName'] as String?;
                              return _MessageBubble(
                                isMe: isFromStudent,
                                text: text,
                                imageBase64: image,
                                fileBase64: fileBase64,
                                fileName: fileName,
                                time: ts != null
                                    ? DateFormat('h:mm a').format(ts)
                                    : '',
                                replyToText: replyToText,
                                replyToSenderName: replyToSenderName,
                                onReport: isFromStudent
                                    ? null
                                    : () => _showReportMessageDialog(
                                        context,
                                        conversationId: _conversationDocId,
                                        messageId: doc.id,
                                        messageText: text,
                                        reportedUserId: widget.orgId,
                                        reportedUserRole: 'org',
                                        orgId: widget.orgId,
                                      ),
                                onDelete: isFromStudent
                                    ? () => _confirmDeleteMessage(doc.id)
                                    : null,
                                onReply: () => _startReply(
                                  doc.id,
                                  text,
                                  isFromStudent ? _studentName : widget.orgName,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    if (!blocked && _replyingTo != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F2F5),
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 30,
                              color: AppColors.primaryDark,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Replying to ${_replyingTo!['senderName']}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                  Text(
                                    (_replyingTo!['text'] ?? '').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _replyingTo = null),
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.grey.shade600,
                              ),
                              tooltip: 'Cancel reply',
                            ),
                          ],
                        ),
                      ),
                    if (!blocked)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: _sending ? null : _pickImage,
                                icon: Icon(
                                  Icons.image_outlined,
                                  color: Colors.grey.shade600,
                                ),
                                tooltip: 'Attach image',
                              ),
                              IconButton(
                                onPressed: _sending ? null : _pickFile,
                                icon: Icon(
                                  Icons.attach_file_rounded,
                                  color: Colors.grey.shade600,
                                ),
                                tooltip: 'Attach file',
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _textCtrl,
                                  minLines: 1,
                                  maxLines: 4,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _sendMessage(),
                                  style: GoogleFonts.poppins(fontSize: 13.5),
                                  decoration: InputDecoration(
                                    hintText: 'Message ${widget.orgName}…',
                                    hintStyle: GoogleFonts.poppins(
                                      fontSize: 13.5,
                                      color: Colors.grey.shade500,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF0F2F5),
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
                                onPressed: _sending
                                    ? null
                                    : () => _sendMessage(),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppColors.primaryDark,
                                  disabledBackgroundColor: AppColors.primaryDark
                                      .withAlpha(120),
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
                      ),
                  ],
                );
              },
            ),
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
    final bg = isMe ? AppColors.primaryDark : Colors.white;
    final fg = isMe ? Colors.white : Colors.black87;
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
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  // An image fills the bubble edge-to-edge like a real
                  // photo message instead of sitting inside a colored
                  // frame — the color only applies when there's no image,
                  // or as a caption strip below one. A file chip or reply
                  // quote always keeps the colored background, same as
                  // plain text.
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
                          color: (isMe ? Colors.white : AppColors.primaryDark)
                              .withAlpha(isMe ? 40 : 14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              color: isMe
                                  ? Colors.white
                                  : AppColors.primaryDark,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              replyToSenderName ?? '',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: fg,
                              ),
                            ),
                            Text(
                              replyToText!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
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
                        child: Image(
                          image: _imageProviderFromBase64(imageBase64!),
                          width: 220,
                          fit: BoxFit.cover,
                        ),
                      ),
                    if (hasFile)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: GestureDetector(
                          onTap: () => _openFileAttachment(
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
                              color:
                                  (isMe ? Colors.white : AppColors.primaryDark)
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
                                    style: GoogleFonts.poppins(
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
                    if (hasText)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: _linkifiedText(
                          context,
                          text,
                          style: GoogleFonts.poppins(fontSize: 13.5, color: fg),
                          linkColor: isMe
                              ? Colors.white
                              : AppColors.primaryDark,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                time,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
