// lib/screens/student/student_broadcast_screen.dart
// One-way private message thread from this student's org — the org can
// send messages here, but the student can only view them (no reply). Each
// student has exactly one thread per org, so there's a single persistent
// view (no inbox needed here). Mirrors lib/screens/web/org/org_broadcast.dart,
// which renders the org side (the one that can actually send) of the same
// `conversations` collection.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../widgets/student/app_colors.dart';

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
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _conversationDocId = _conversationId(widget.orgId, uid);
    _markRead();
  }

  Future<void> _markRead() async {
    // Students can't start a conversation anymore (the org does, via "New
    // message" on its side) — so if this doc doesn't exist yet, there's
    // simply nothing to show, and we shouldn't create one here.
    try {
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.orgName,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Announcements only · you can\'t reply here',
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
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
          : StreamBuilder<QuerySnapshot>(
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
                            Icons.campaign_outlined,
                            size: 40,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${widget.orgName} hasn\'t sent you any messages yet.',
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
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    // Historical messages from the brief period this thread
                    // was two-way may still have senderRole == 'student' —
                    // kept left/right-aligned as they were sent so old
                    // threads don't look broken, even though students can no
                    // longer send new ones.
                    final isFromStudent = data['senderRole'] == 'student';
                    final text = (data['text'] ?? '').toString();
                    final image = data['imageBase64'] as String?;
                    final ts = (data['timestamp'] as Timestamp?)?.toDate();
                    return _MessageBubble(
                      isMe: isFromStudent,
                      text: text,
                      imageBase64: image,
                      time: ts != null ? DateFormat('h:mm a').format(ts) : '',
                    );
                  },
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

  const _MessageBubble({
    required this.isMe,
    required this.text,
    required this.imageBase64,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isMe ? AppColors.primaryDark : Colors.white;
    final fg = isMe ? Colors.white : Colors.black87;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
    );
  }
}
