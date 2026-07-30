// lib/screens/student/student_broadcast_screen.dart
// Private messaging thread between this student and their org — replaces the
// old org-wide broadcast/announcement channel. Each student has exactly one
// org, so there's a single persistent thread (no inbox needed here). Mirrors
// lib/screens/web/org/org_broadcast.dart, which renders the org side of the
// same `conversations` collection.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/notification_service.dart';
import '../../utils/profanity_filter.dart';
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
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late final String _conversationDocId;
  String _studentName = 'You';
  bool _sending = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _conversationDocId = _conversationId(widget.orgId, uid);
    _initConversation(uid);
  }

  Future<void> _initConversation(String uid) async {
    try {
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(uid)
          .get();
      final studentData = studentDoc.data();
      _studentName =
          studentData?['fullName'] ??
          FirebaseAuth.instance.currentUser?.displayName ??
          FirebaseAuth.instance.currentUser?.email ??
          'You';

      final ref = FirebaseFirestore.instance
          .collection('conversations')
          .doc(_conversationDocId);
      final existing = await ref.get();
      if (!existing.exists) {
        await ref.set({
          'orgId': widget.orgId,
          'orgName': widget.orgName,
          'studentId': uid,
          'studentName': _studentName,
          'lastMessage': '',
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastSenderRole': 'student',
          'unreadForOrg': false,
          'unreadForStudent': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await ref.update({'unreadForStudent': false});
      }
    } catch (_) {
      // Non-fatal — thread still renders, just won't have a doc until the
      // first message is sent.
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendMessage({String? imageBase64}) async {
    final rawText = _textCtrl.text.trim();
    if (rawText.isEmpty && imageBase64 == null) return;
    final text = ProfanityFilter.filter(rawText);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    setState(() => _sending = true);
    _textCtrl.clear();

    final ref = FirebaseFirestore.instance
        .collection('conversations')
        .doc(_conversationDocId);
    try {
      await ref.set({
        'orgId': widget.orgId,
        'orgName': widget.orgName,
        'studentId': uid,
        'studentName': _studentName,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await ref.collection('messages').add({
        'senderId': uid,
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
      );
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
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
            Text(
              widget.orgName,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
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
          : Column(
              children: [
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
                            child: Text(
                              'Message ${widget.orgName} directly — this is a private conversation.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
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
                          final data = docs[i].data() as Map<String, dynamic>;
                          final isMe = data['senderRole'] == 'student';
                          final text = (data['text'] ?? '').toString();
                          final image = data['imageBase64'] as String?;
                          final ts = (data['timestamp'] as Timestamp?)
                              ?.toDate();
                          return _MessageBubble(
                            isMe: isMe,
                            text: text,
                            imageBase64: image,
                            time: ts != null
                                ? DateFormat('h:mm a').format(ts)
                                : '',
                          );
                        },
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
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
                          onPressed: _sending ? null : () => _sendMessage(),
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
