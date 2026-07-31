// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../theme/org_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Field type definitions
// ─────────────────────────────────────────────────────────────────────────────
enum _FType {
  shortText,
  paragraph,
  multipleChoice,
  checkboxes,
  dropdown,
  email,
  number,
  date,
  fileUpload,
}

extension _FTypeX on _FType {
  String get key {
    const m = {
      _FType.shortText: 'short_text',
      _FType.paragraph: 'paragraph',
      _FType.multipleChoice: 'multiple_choice',
      _FType.checkboxes: 'checkboxes',
      _FType.dropdown: 'dropdown',
      _FType.email: 'email',
      _FType.number: 'number',
      _FType.date: 'date',
      _FType.fileUpload: 'file_upload',
    };
    return m[this]!;
  }

  String get label {
    const m = {
      _FType.shortText: 'Short Answer',
      _FType.paragraph: 'Paragraph',
      _FType.multipleChoice: 'Multiple Choice',
      _FType.checkboxes: 'Checkboxes',
      _FType.dropdown: 'Dropdown',
      _FType.email: 'Email',
      _FType.number: 'Number',
      _FType.date: 'Date',
      _FType.fileUpload: 'Photo/Video Upload',
    };
    return m[this]!;
  }

  IconData get icon {
    const m = {
      _FType.shortText: Icons.short_text_rounded,
      _FType.paragraph: Icons.notes_rounded,
      _FType.multipleChoice: Icons.radio_button_checked_rounded,
      _FType.checkboxes: Icons.check_box_rounded,
      _FType.dropdown: Icons.arrow_drop_down_circle_rounded,
      _FType.email: Icons.email_outlined,
      _FType.number: Icons.pin_rounded,
      _FType.date: Icons.calendar_today_rounded,
      _FType.fileUpload: Icons.perm_media_rounded,
    };
    return m[this]!;
  }

  Color get color {
    const m = {
      _FType.shortText: Color(0xFF2563EB),
      _FType.paragraph: Color(0xFF7C3AED),
      _FType.multipleChoice: Color(0xFF059669),
      _FType.checkboxes: Color(0xFF0D9488),
      _FType.dropdown: Color(0xFFB45309),
      _FType.email: Color(0xFFDC2626),
      _FType.number: Color(0xFF6B7280),
      _FType.date: Color(0xFF0369A1),
      _FType.fileUpload: Color(0xFFDB2777),
    };
    return m[this]!;
  }

  bool get hasOptions =>
      this == _FType.multipleChoice ||
      this == _FType.checkboxes ||
      this == _FType.dropdown;

  static _FType fromKey(String k) {
    return _FType.values.firstWhere(
      (t) => t.key == k,
      orElse: () => _FType.shortText,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry point modal
// ─────────────────────────────────────────────────────────────────────────────
class OrgFormBuilderModal extends StatefulWidget {
  final String proposalId;
  final String proposalTitle;
  final String orgId;
  final bool isLocked;

  const OrgFormBuilderModal({
    super.key,
    required this.proposalId,
    required this.proposalTitle,
    required this.orgId,
    required this.isLocked,
  });

  @override
  State<OrgFormBuilderModal> createState() => _OrgFormBuilderModalState();
}

class _OrgFormBuilderModalState extends State<OrgFormBuilderModal> {
  bool _loading = true;
  bool _saving = false;
  bool _isPublished = false;
  int? _expandedIdx;

  final _titleCtrl = TextEditingController(text: 'Registration Form');
  final _descCtrl = TextEditingController();
  List<Map<String, dynamic>> _fields = [];

  static const _kCol = UpriseColors.primaryDark;
  static final _kColLight = UpriseColors.primaryDark.withAlpha(18);

  // Auto-save: fires periodically once the form has loaded, silently
  // persisting the current draft (unvalidated — losing in-progress work
  // because a question isn't filled in yet would defeat the point) so a
  // closed tab/browser crash doesn't lose the org's edits.
  Timer? _autoSaveTimer;
  DateTime? _lastAutoSavedAt;
  bool _autoSaveFailed = false;
  static const _autoSaveInterval = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _load();
    _autoSaveTimer = Timer.periodic(_autoSaveInterval, (_) => _autoSave());
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildPayload() => {
    'proposalId': widget.proposalId,
    'orgId': widget.orgId,
    'eventTitle': widget.proposalTitle,
    'title': _titleCtrl.text.trim().isEmpty
        ? 'Registration Form'
        : _titleCtrl.text.trim(),
    'description': _descCtrl.text.trim(),
    'isPublished': _isPublished,
    'fields': _fields,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
  };

  Future<void> _autoSave() async {
    // Don't fight an in-flight manual save, and don't auto-save before the
    // form has even finished loading (that would overwrite the real draft
    // with the still-default empty one).
    if (_loading || _saving || !mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('registration_forms')
          .doc(widget.proposalId)
          .set(_buildPayload(), SetOptions(merge: true));
      if (mounted) {
        setState(() {
          _lastAutoSavedAt = DateTime.now();
          _autoSaveFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _autoSaveFailed = true);
    }
  }

  // ── Firestore ────────────────────────────────────────────────────────────
  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('registration_forms')
          .doc(widget.proposalId)
          .get();
      if (doc.exists) {
        final d = doc.data()!;
        _titleCtrl.text = d['title'] ?? 'Registration Form';
        _descCtrl.text = d['description'] ?? '';
        _isPublished = d['isPublished'] == true;
        final raw = d['fields'];
        if (raw is List) {
          _fields = raw
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  bool _validateFields() {
    for (var i = 0; i < _fields.length; i++) {
      final f = _fields[i];
      final label = (f['label'] as String? ?? '').trim();
      if (label.isEmpty) {
        setState(() => _expandedIdx = i);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Question ${i + 1} needs a label before saving.'),
            backgroundColor: UpriseColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
        return false;
      }
      final type = _FTypeX.fromKey(f['type'] ?? 'short_text');
      if (type.hasOptions) {
        final options = (f['options'] as List?)?.cast<String>() ?? [];
        if (options.length < 2 || options.any((o) => o.trim().isEmpty)) {
          setState(() => _expandedIdx = i);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Question ${i + 1} ("$label") has a blank option — fill in every option before saving.',
              ),
              backgroundColor: UpriseColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _save() async {
    if (!_validateFields()) return;
    setState(() => _saving = true);
    try {
      final ref = FirebaseFirestore.instance
          .collection('registration_forms')
          .doc(widget.proposalId);
      final payload = _buildPayload();
      final existing = await ref.get();
      if (!existing.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }
      await ref.set(payload, SetOptions(merge: true));
      if (mounted) {
        setState(() => _lastAutoSavedAt = DateTime.now());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isPublished
                  ? 'Form saved and published.'
                  : 'Form saved as draft.',
            ),
            backgroundColor: _kCol,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: UpriseColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  // ── Field operations ──────────────────────────────────────────────────────
  void _addField(_FType type) {
    final id = 'f_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _fields.add({
        'id': id,
        'type': type.key,
        'label': '',
        'description': '',
        'required': false,
        'options': type.hasOptions ? ['', ''] : <String>[],
      });
      _expandedIdx = _fields.length - 1;
    });
  }

  void _deleteField(int i) {
    setState(() {
      _fields.removeAt(i);
      if (_expandedIdx == i) {
        _expandedIdx = null;
      } else if (_expandedIdx != null && _expandedIdx! > i) {
        _expandedIdx = _expandedIdx! - 1;
      }
    });
  }

  void _moveUp(int i) {
    if (i == 0) {
      return;
    }
    setState(() {
      final tmp = _fields[i];
      _fields[i] = _fields[i - 1];
      _fields[i - 1] = tmp;
      if (_expandedIdx == i) {
        _expandedIdx = i - 1;
      } else if (_expandedIdx == i - 1) {
        _expandedIdx = i;
      }
    });
  }

  void _moveDown(int i) {
    if (i == _fields.length - 1) {
      return;
    }
    setState(() {
      final tmp = _fields[i];
      _fields[i] = _fields[i + 1];
      _fields[i + 1] = tmp;
      if (_expandedIdx == i) {
        _expandedIdx = i + 1;
      } else if (_expandedIdx == i + 1) {
        _expandedIdx = i;
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 760,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    children: [
                      _buildFormMeta(),
                      const SizedBox(height: 20),
                      if (widget.isLocked) _buildLockedBanner(),
                      if (_fields.isEmpty && !widget.isLocked)
                        _buildEmptyState()
                      else
                        ...List.generate(
                          _fields.length,
                          (i) => _FieldCard(
                            key: ValueKey(_fields[i]['id']),
                            field: _fields[i],
                            index: i,
                            total: _fields.length,
                            isExpanded: _expandedIdx == i,
                            isLocked: widget.isLocked,
                            onTap: () => setState(
                              () => _expandedIdx = _expandedIdx == i ? null : i,
                            ),
                            onDelete: () => _deleteField(i),
                            onMoveUp: () => _moveUp(i),
                            onMoveDown: () => _moveDown(i),
                            onChanged: (updated) =>
                                setState(() => _fields[i] = updated),
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              _buildFooter(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: const BoxDecoration(
        color: _kCol,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(38),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.dynamic_form_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registration Form Builder',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.proposalTitle,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: Colors.white.withAlpha(200),
                  ),
                ),
                if (_lastAutoSavedAt != null || _autoSaveFailed) ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _autoSaveFailed
                            ? Icons.cloud_off_rounded
                            : Icons.cloud_done_rounded,
                        size: 12,
                        color: Colors.white.withAlpha(200),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _autoSaveFailed
                            ? 'Auto-save failed — changes not yet backed up'
                            : 'Auto-saved ${DateFormat('h:mm a').format(_lastAutoSavedAt!)}',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 10.5,
                          color: Colors.white.withAlpha(200),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!widget.isLocked) ...[
            _PublishToggle(
              value: _isPublished,
              onChanged: (v) => setState(() => _isPublished = v),
            ),
            const SizedBox(width: 12),
          ],
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildFormMeta() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: _kCol, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleCtrl,
            readOnly: widget.isLocked,
            style: GoogleFonts.beVietnamPro(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A202C),
            ),
            decoration: InputDecoration(
              hintText: 'Form Title',
              hintStyle: GoogleFonts.beVietnamPro(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFD1D5DB),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const Divider(height: 16),
          TextField(
            controller: _descCtrl,
            readOnly: widget.isLocked,
            maxLines: null,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
            decoration: InputDecoration(
              hintText: 'Form description (optional)',
              hintStyle: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFFD1D5DB),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFB923C).withAlpha(100)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, size: 16, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This event has already passed. The form is now locked and cannot be edited.',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: const Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE2E6EA),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _kColLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.add_box_rounded, size: 32, color: _kCol),
          ),
          const SizedBox(height: 14),
          Text(
            'No questions yet',
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Click "Add Question" below to start building your form.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
        color: Color(0xFFF8F9FB),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      child: Row(
        children: [
          if (!widget.isLocked) _AddQuestionButton(onSelected: _addField),
          const Spacer(),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFE2E6EA)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              widget.isLocked ? 'Close' : 'Cancel',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF374151),
              ),
            ),
          ),
          if (!widget.isLocked) ...[
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded, size: 16),
              label: Text(
                'Save Form',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kCol,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Publish toggle
// ─────────────────────────────────────────────────────────────────────────────
class _PublishToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _PublishToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: value
              ? Colors.white.withAlpha(38)
              : Colors.white.withAlpha(18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withAlpha(80)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: value
                    ? const Color(0xFF4ADE80)
                    : Colors.white.withAlpha(120),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              value ? 'Published' : 'Draft',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Question button with type picker
// ─────────────────────────────────────────────────────────────────────────────
class _AddQuestionButton extends StatelessWidget {
  final ValueChanged<_FType> onSelected;
  const _AddQuestionButton({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_FType>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
      offset: const Offset(0, -280),
      onSelected: onSelected,
      itemBuilder: (_) => _FType.values
          .map(
            (t) => PopupMenuItem(
              value: t,
              height: 42,
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: t.color.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(t.icon, size: 15, color: t.color),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    t.label,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: const Color(0xFF374151),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: UpriseColors.primaryDark,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: UpriseColors.primaryDark.withAlpha(60),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              'Add Question',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Field card
// ─────────────────────────────────────────────────────────────────────────────
class _FieldCard extends StatefulWidget {
  final Map<String, dynamic> field;
  final int index;
  final int total;
  final bool isExpanded;
  final bool isLocked;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const _FieldCard({
    super.key,
    required this.field,
    required this.index,
    required this.total,
    required this.isExpanded,
    required this.isLocked,
    required this.onTap,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onChanged,
  });

  @override
  State<_FieldCard> createState() => _FieldCardState();
}

class _FieldCardState extends State<_FieldCard> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _descCtrl;
  late List<TextEditingController> _optionCtrls;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.field['label'] ?? '');
    _descCtrl = TextEditingController(text: widget.field['description'] ?? '');
    final opts = (widget.field['options'] as List?)?.cast<String>() ?? [];
    _optionCtrls = opts.map((o) => TextEditingController(text: o)).toList();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final updated = Map<String, dynamic>.from(widget.field);
    updated['label'] = _labelCtrl.text;
    updated['description'] = _descCtrl.text;
    updated['options'] = _optionCtrls.map((c) => c.text).toList();
    widget.onChanged(updated);
  }

  void _addOption() {
    setState(() => _optionCtrls.add(TextEditingController()));
    _emit();
  }

  void _removeOption(int i) {
    if (_optionCtrls.length <= 1) return;
    setState(() {
      _optionCtrls[i].dispose();
      _optionCtrls.removeAt(i);
    });
    _emit();
  }

  _FType get _currentType =>
      _FTypeX.fromKey(widget.field['type'] ?? 'short_text');

  @override
  Widget build(BuildContext context) {
    final type = _currentType;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isExpanded
              ? UpriseColors.primaryDark
              : const Color(0xFFE8ECF0),
          width: widget.isExpanded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Collapsed header ──
          InkWell(
            onTap: widget.isLocked ? null : widget.onTap,
            borderRadius: widget.isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  // Field number
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: type.color.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '${widget.index + 1}',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: type.color,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(type.icon, size: 16, color: type.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.field['label']?.toString().isNotEmpty == true
                          ? widget.field['label']
                          : 'Untitled Question',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A202C),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Type pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: type.color.withAlpha(15),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      type.label,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: type.color,
                      ),
                    ),
                  ),
                  if (widget.field['required'] == true) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'Required',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                  if (!widget.isLocked) ...[
                    const SizedBox(width: 8),
                    _miniBtn(
                      Icons.keyboard_arrow_up_rounded,
                      widget.index > 0 ? widget.onMoveUp : null,
                    ),
                    _miniBtn(
                      Icons.keyboard_arrow_down_rounded,
                      widget.index < widget.total - 1
                          ? widget.onMoveDown
                          : null,
                    ),
                    _miniBtn(
                      Icons.delete_outline_rounded,
                      widget.onDelete,
                      color: const Color(0xFFDC2626),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Expanded editor ──
          if (widget.isExpanded) ...[
            const Divider(height: 1, color: Color(0xFFE8ECF0)),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type selector + Required toggle
                  Row(
                    children: [
                      Expanded(child: _buildTypeDropdown(type)),
                      const SizedBox(width: 12),
                      _RequiredToggle(
                        value: widget.field['required'] == true,
                        onChanged: (v) {
                          final u = Map<String, dynamic>.from(widget.field);
                          u['required'] = v;
                          widget.onChanged(u);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Label
                  _editorField(
                    controller: _labelCtrl,
                    label: 'Question Label *',
                    hint: 'e.g. Full Name, Department, etc.',
                    onChanged: (_) => _emit(),
                  ),
                  const SizedBox(height: 10),
                  // Description (optional)
                  _editorField(
                    controller: _descCtrl,
                    label: 'Helper text (optional)',
                    hint: 'Add a short description or note for this question',
                    onChanged: (_) => _emit(),
                  ),
                  // Options (for MCQ/checkboxes/dropdown)
                  if (type.hasOptions) ...[
                    const SizedBox(height: 16),
                    _buildOptionsEditor(type),
                  ],
                  // Preview hint
                  const SizedBox(height: 14),
                  _buildFieldPreview(type),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniBtn(
    IconData icon,
    VoidCallback? onTap, {
    Color color = const Color(0xFF9AA5B4),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 16,
          color: onTap == null ? const Color(0xFFE2E6EA) : color,
        ),
      ),
    );
  }

  Widget _buildTypeDropdown(_FType current) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E6EA)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_FType>(
          value: current,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: Color(0xFF9AA5B4),
          ),
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: const Color(0xFF374151),
          ),
          onChanged: (t) {
            if (t == null) return;
            final u = Map<String, dynamic>.from(widget.field);
            u['type'] = t.key;
            if (t.hasOptions && (u['options'] as List?)?.isEmpty == true) {
              u['options'] = ['', ''];
              setState(() {
                for (final c in _optionCtrls) {
                  c.dispose();
                }
                _optionCtrls = [
                  '',
                  '',
                ].map((o) => TextEditingController(text: o)).toList();
              });
            } else if (!t.hasOptions) {
              u['options'] = <String>[];
            }
            widget.onChanged(u);
          },
          items: _FType.values
              .map(
                (t) => DropdownMenuItem(
                  value: t,
                  child: Row(
                    children: [
                      Icon(t.icon, size: 14, color: t.color),
                      const SizedBox(width: 8),
                      Text(t.label),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _editorField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: GoogleFonts.beVietnamPro(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.beVietnamPro(
          fontSize: 12,
          color: const Color(0xFF64748B),
        ),
        hintStyle: GoogleFonts.beVietnamPro(
          fontSize: 12,
          color: const Color(0xFFD1D5DB),
        ),
        filled: true,
        fillColor: const Color(0xFFF8F9FB),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: UpriseColors.primaryDark,
            width: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildOptionsEditor(_FType type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(type.icon, size: 13, color: type.color),
            const SizedBox(width: 6),
            Text(
              'Options',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF374151),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(
          _optionCtrls.length,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  type == _FType.multipleChoice
                      ? Icons.radio_button_unchecked_rounded
                      : type == _FType.checkboxes
                      ? Icons.check_box_outline_blank_rounded
                      : Icons.drag_indicator_rounded,
                  size: 16,
                  color: const Color(0xFF9AA5B4),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _optionCtrls[i],
                    onChanged: (_) => _emit(),
                    style: GoogleFonts.beVietnamPro(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Option ${i + 1}',
                      hintStyle: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: const Color(0xFFD1D5DB),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8F9FB),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: const BorderSide(
                          color: UpriseColors.primaryDark,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _optionCtrls.length > 1
                      ? () => _removeOption(i)
                      : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: _optionCtrls.length > 1
                          ? const Color(0xFF9AA5B4)
                          : const Color(0xFFE2E6EA),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        TextButton.icon(
          onPressed: _addOption,
          icon: const Icon(Icons.add_rounded, size: 15),
          label: Text(
            'Add Option',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: UpriseColors.primaryDark,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildFieldPreview(_FType type) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.preview_rounded,
                size: 12,
                color: Color(0xFF9AA5B4),
              ),
              const SizedBox(width: 5),
              Text(
                'Preview',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF9AA5B4),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: widget.field['label']?.toString().isNotEmpty == true
                      ? widget.field['label']
                      : 'Untitled Question',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A202C),
                  ),
                ),
                if (widget.field['required'] == true)
                  TextSpan(
                    text: ' *',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: const Color(0xFFDC2626),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          if ((widget.field['description'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              widget.field['description'],
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _previewInput(type),
        ],
      ),
    );
  }

  Widget _previewInput(_FType type) {
    switch (type) {
      case _FType.shortText:
      case _FType.email:
      case _FType.number:
        return _previewTextBox(
          type == _FType.email
              ? 'someone@email.com'
              : type == _FType.number
              ? '0'
              : 'Short answer',
        );
      case _FType.paragraph:
        return _previewTextBox('Long answer text…', minLines: 3);
      case _FType.date:
        return _previewTextBox(
          DateFormat('MMM dd, yyyy').format(DateTime.now()),
          icon: Icons.calendar_today_rounded,
        );
      case _FType.multipleChoice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: (_optionCtrls.map((c) => c.text).toList())
              .map(
                (o) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.radio_button_unchecked_rounded,
                        size: 16,
                        color: Color(0xFF9AA5B4),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        o,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: const Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      case _FType.checkboxes:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: (_optionCtrls.map((c) => c.text).toList())
              .map(
                (o) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_box_outline_blank_rounded,
                        size: 16,
                        color: Color(0xFF9AA5B4),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        o,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: const Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      case _FType.dropdown:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFFE2E6EA)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _optionCtrls.isNotEmpty
                      ? _optionCtrls.first.text
                      : 'Select an option',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: const Color(0xFF9AA5B4),
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: Color(0xFF9AA5B4),
              ),
            ],
          ),
        );
      case _FType.fileUpload:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FB),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: const Color(0xFFE2E6EA),
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.add_photo_alternate_outlined,
                size: 16,
                color: Color(0xFF9AA5B4),
              ),
              const SizedBox(width: 8),
              Text(
                'Upload a photo or video',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: const Color(0xFF9AA5B4),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _previewTextBox(String hint, {int minLines = 1, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE2E6EA)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: const Color(0xFF9AA5B4)),
            const SizedBox(width: 6),
          ],
          Text(
            hint,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: const Color(0xFF9AA5B4),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Required toggle
// ─────────────────────────────────────────────────────────────────────────────
class _RequiredToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _RequiredToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: value ? const Color(0xFFFEF2F2) : const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? const Color(0xFFFCA5A5) : const Color(0xFFE2E6EA),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 15,
              color: value ? const Color(0xFFDC2626) : const Color(0xFF9AA5B4),
            ),
            const SizedBox(width: 6),
            Text(
              'Required',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: value
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF9AA5B4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
