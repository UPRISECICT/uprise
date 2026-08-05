// lib/screens/student/student_broadcast_screen.dart
// Two-way private message thread between this student and their org. Each
// student has exactly one thread per org, so there's a single persistent
// view (no inbox needed here). Mirrors lib/screens/web/org/org_broadcast.dart,
// which renders the org side of the same `conversations` collection.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../widgets/student/app_colors.dart';
import '../../services/notification_service.dart';
import '../../utils/profanity_filter.dart';

ImageProvider _imageProviderFromBase64(String data) {
  final base64Part = data.contains(',') ? data.split(',').last : data;
  return MemoryImage(base64Decode(base64Part));
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

// Mirrors showReportMessageDialog in org_broadcast.dart — writes to
// `message_reports` for later admin review. There's no report-review queue
// UI yet; this is the reporting mechanism itself.
Future<void> _showReportMessageDialog(
  BuildContext context, {
  required String conversationId,
  required String messageId,
  required String messageText,
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
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 360,
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

  final reporter = FirebaseAuth.instance.currentUser;
  try {
    await FirebaseFirestore.instance.collection('message_reports').add({
      'conversationId': conversationId,
      'messageId': messageId,
      'messageText': messageText,
      'reporterId': reporter?.uid ?? '',
      'reporterRole': 'student',
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
      final name = (studentDoc.data()?['name'] as String? ?? '').trim();
      if (name.isNotEmpty) _studentName = name;

      final ref = FirebaseFirestore.instance
          .collection('conversations')
          .doc(_conversationDocId);
      final existing = await ref.get();
      if (existing.exists) {
        await ref.update({'unreadForStudent': false});
      }
    } catch (_) {
      // Non-fatal — the thread still renders either way.
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _sendMessage({String? imageBase64}) async {
    final rawText = _textCtrl.text.trim();
    if (rawText.isEmpty && imageBase64 == null) return;
    final text = ProfanityFilter.filter(rawText);
    setState(() => _sending = true);
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

      await ref.collection('messages').add({
        'senderId': _studentId,
        'senderRole': 'student',
        'senderName': _studentName,
        'text': text,
        'imageBase64': imageBase64,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await ref.update({
        'lastMessage': text.isEmpty ? 'Sent an image' : text,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderRole': 'student',
        'unreadForOrg': true,
      });
      await NotificationService.sendToOrgMembers(
        orgId: widget.orgId,
        title: _studentName,
        body: text.isEmpty ? 'Sent an image' : text,
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
                          return ListView.builder(
                            controller: _scrollCtrl,
                            reverse: true,
                            padding: const EdgeInsets.all(16),
                            itemCount: docs.length,
                            itemBuilder: (context, i) {
                              final data =
                                  docs[i].data() as Map<String, dynamic>;
                              final isFromStudent =
                                  data['senderRole'] == 'student';
                              final text = (data['text'] ?? '').toString();
                              final image = data['imageBase64'] as String?;
                              final ts = (data['timestamp'] as Timestamp?)
                                  ?.toDate();
                              return _MessageBubble(
                                isMe: isFromStudent,
                                text: text,
                                imageBase64: image,
                                time: ts != null
                                    ? DateFormat('h:mm a').format(ts)
                                    : '',
                                onReport: isFromStudent
                                    ? null
                                    : () => _showReportMessageDialog(
                                        context,
                                        conversationId: _conversationDocId,
                                        messageId: docs[i].id,
                                        messageText: text,
                                        reportedUserId: widget.orgId,
                                        reportedUserRole: 'org',
                                      ),
                              );
                            },
                          );
                        },
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
  final String time;
  // Only set for the other person's messages — reporting your own message
  // makes no sense, so the long-press menu simply doesn't appear on isMe
  // bubbles.
  final VoidCallback? onReport;

  const _MessageBubble({
    required this.isMe,
    required this.text,
    required this.imageBase64,
    required this.time,
    this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isMe ? AppColors.primaryDark : Colors.white;
    final fg = isMe ? Colors.white : Colors.black87;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onReport,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageBase64 != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image(
                          image: _imageProviderFromBase64(imageBase64!),
                          width: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (text.isNotEmpty) const SizedBox(height: 6),
                    ],
                    if (text.isNotEmpty)
                      Text(
                        text,
                        style: GoogleFonts.poppins(fontSize: 13.5, color: fg),
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
