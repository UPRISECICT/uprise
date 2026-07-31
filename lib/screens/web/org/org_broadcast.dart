// lib/screens/web/org/org_broadcast.dart
// Private messaging inbox — one thread per student, replacing the old
// org-wide broadcast channel. Messages are filtered for profanity before
// being stored. Mirrors lib/screens/student/student_broadcast_screen.dart,
// which renders the student side of the same `conversations` collection.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/notification_service.dart';
import '../../../utils/profanity_filter.dart';

class _C {
  static const Color primaryDark = Color(0xFFEA580C);
  static const Color white = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8F9FB);
  static const Color pageBg = Color(0xFFFBFCFE);
  static const Color border = Color(0xFFE8ECF0);
  static const Color charcoal = Color(0xFF1A202C);
  static const Color darkGray = Color(0xFF64748B);
  static const Color textFaint = Color(0xFF9AA5B4);
}

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

  const _ConversationsList({
    required this.orgId,
    required this.searchQuery,
    required this.searchController,
    required this.selectedId,
    required this.onSelect,
    required this.onNewMessage,
  });

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
              var docs = snap.data!.docs;
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
                      searchQuery.isEmpty
                          ? 'No conversations yet.\nTap the compose icon to message a student.'
                          : 'No students match your search.',
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

  String get _studentName =>
      (widget.conversation['studentName'] ?? 'Student').toString();
  String get _studentId => (widget.conversation['studentId'] ?? '').toString();

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
    setState(() => _sending = true);
    _textCtrl.clear();

    final user = FirebaseAuth.instance.currentUser;
    final ref = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId);
    try {
      await ref.collection('messages').add({
        'senderId': user?.uid ?? '',
        'senderRole': 'org',
        'senderName': widget.orgName,
        'text': text,
        'imageBase64': imageBase64,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await ref.update({
        'lastMessage': text.isEmpty ? 'Sent an image' : text,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderRole': 'org',
        'unreadForStudent': true,
      });
      if (_studentId.isNotEmpty) {
        await NotificationService.sendToUser(
          userId: _studentId,
          title: widget.orgName,
          body: text.isEmpty ? 'Sent you an image' : text,
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
              Text(
                _studentName,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _C.charcoal,
                ),
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
                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final isOrg = data['senderRole'] == 'org';
                    final text = (data['text'] ?? '').toString();
                    final image = data['imageBase64'] as String?;
                    final ts = (data['timestamp'] as Timestamp?)?.toDate();
                    return _MessageBubble(
                      isMe: isOrg,
                      text: text,
                      imageBase64: image,
                      time: ts != null ? DateFormat('h:mm a').format(ts) : '',
                    );
                  },
                );
              },
            ),
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
  final String time;

  const _MessageBubble({
    required this.isMe,
    required this.text,
    required this.imageBase64,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isMe ? _C.primaryDark : Colors.white;
    final fg = isMe ? Colors.white : _C.charcoal;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 460),
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
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13.5,
                        color: fg,
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
    );
  }
}
