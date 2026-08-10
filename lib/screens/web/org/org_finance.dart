import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../services/activity_logger.dart' as activity_log;
import 'package:fl_chart/fl_chart.dart';
import '../../../widgets/admin_export_button.dart';
import '../../../widgets/anchored_dropdown.dart';
import '../../../widgets/org_action_icon_button.dart';
import '../../../widgets/org_modal_shell.dart';
import 'export_util.dart';
import 'export_pdf.dart';
import '../../../theme/org_theme.dart';
import '../../../utils/school_year.dart';

// ============ COLOR SCHEME ============
class OrgColors {
  static const Color primaryDark = Color(0xFFC2410C);
  static const Color primaryLight = Color(0xFFEA580C);
  static const Color accent = Color(0xFF2563EB);
  static const Color white = Color(0xFFFFFFFF);
  static const Color lightGray = Color(0xFFF8F9FB);
  static const Color mediumGray = Color(0xFFE8ECF0);
  static const Color darkGray = Color(0xFF64748B);
  static const Color charcoal = Color(0xFF1A202C);
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFFB923C);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);
}

// ============ DESIGN SYSTEM ============
class _DS {
  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withOpacity(0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

// ============ TRANSACTION MODEL ============
class TransactionModel {
  final String id;
  final String eventId;
  final String eventName;
  final String category;
  final String segment;
  final double amount;
  final String type;
  final Timestamp date;
  final bool isArchived;

  TransactionModel({
    required this.id,
    required this.eventId,
    required this.eventName,
    required this.category,
    required this.segment,
    required this.amount,
    required this.type,
    required this.date,
    this.isArchived = false,
  });

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TransactionModel(
      id: doc.id,
      eventId: data['eventId'] ?? '',
      eventName: data['eventName'] ?? '',
      category: data['category'] ?? '',
      segment: data['segment'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      type: data['type'] ?? 'income',
      date: data['date'] as Timestamp,
      isArchived: data['isArchived'] ?? false,
    );
  }
}

// ============ MAIN SCREEN ============
class OrgFinanceScreen extends StatefulWidget {
  final String orgId;
  const OrgFinanceScreen({super.key, required this.orgId});

  @override
  State<OrgFinanceScreen> createState() => _OrgFinanceScreenState();
}

class _OrgFinanceScreenState extends State<OrgFinanceScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterType = 'all';
  String _filterCategory = 'All';
  // Archiving a transaction removes it from the active list "but kept on
  // record" (per the archive confirmation copy) — except there was no way
  // to actually get back to that record afterward. This toggles between the
  // active list and a dedicated archived view.
  bool _showArchived = false;
  // Which stat card (if any) is currently driving _filterType — lets the
  // cards act as quick filters into the transactions table below, matching
  // AdminDashboard's clickable-stat-card pattern.
  int? _selectedStatCard;
  int _currentPage = 1;
  static const int _pageSize = 10;
  final ScrollController _tableScrollController = ScrollController();
  String? _highlightedTransactionId;
  String _orgName = '';
  String _orgLogoUrl = '';

  final List<String> _categories = [
    'All',
    'Workshops',
    'Competitions',
    'Partnerships',
    'Socials',
    'Retail',
    'General',
  ];

  // Stats row used to hold its own separate live listener on this exact
  // same query — two Firestore subscriptions doing identical work for the
  // whole time this screen was open. Now shared.
  late final Stream<QuerySnapshot> _transactionsStream;

  List<TransactionModel> _filterTransactions(List<TransactionModel> list) {
    return list.where((t) {
      if (t.isArchived != _showArchived) return false;
      final matchSearch =
          _searchQuery.isEmpty ||
          t.eventName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          t.category.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          t.segment.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchType = _filterType == 'all' || t.type == _filterType;
      final matchCategory =
          _filterCategory == 'All' || t.category == _filterCategory;
      return matchSearch && matchType && matchCategory;
    }).toList();
  }

  // 'event' mode filters by a specific event and excludes archived
  // transactions, same as the rest of the page. 'dateRange' and 'semester'
  // modes filter by date only and deliberately include archived
  // transactions that fall within the range — these are mutually exclusive
  // report modes, not combinable filters.
  List<TransactionModel> _applyReportFilters(
    List<TransactionModel> list, {
    required String mode,
    String eventFilter = 'All Events',
    DateTime? startDate,
    DateTime? endDate,
    String? schoolYear,
    String? semester,
  }) {
    if (mode == 'dateRange') {
      final inclusiveEnd = endDate == null
          ? null
          : DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
      return list.where((t) {
        final txnDate = t.date.toDate();
        final startMatch = startDate == null || !txnDate.isBefore(startDate);
        final endMatch = inclusiveEnd == null || !txnDate.isAfter(inclusiveEnd);
        return startMatch && endMatch;
      }).toList();
    }
    if (mode == 'semester') {
      final (rangeStart, rangeEnd) = SchoolYearUtil.dateRangeFor(
        schoolYear ?? SchoolYearUtil.currentSchoolYear(),
        semester == SchoolYearUtil.wholeYear ? null : semester,
      );
      return list.where((t) {
        final txnDate = t.date.toDate();
        return !txnDate.isBefore(rangeStart) && !txnDate.isAfter(rangeEnd);
      }).toList();
    }
    return list.where((t) {
      if (t.isArchived) return false;
      return eventFilter == 'All Events' || t.eventName == eventFilter;
    }).toList();
  }

  void _openAddModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TransactionModal(orgId: widget.orgId),
    ).then((result) {
      // Reset filters and go to first page so the newly added transaction is visible
      if (result is String && result.isNotEmpty) {
        setState(() {
          _currentPage = 1;
          _searchQuery = '';
          _searchController.clear();
          _filterType = 'all';
          _filterCategory = 'All';
          _showArchived = false;
          _selectedStatCard = null;
          _highlightedTransactionId = result;
        });
        // Remove highlight after a short delay
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted && _highlightedTransactionId == result) {
            setState(() => _highlightedTransactionId = null);
          }
        });
      } else {
        setState(() {
          _currentPage = 1;
        });
      }
      // Scroll the table to top after frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_tableScrollController.hasClients) {
          _tableScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  void _openEditModal(TransactionModel transaction) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TransactionModal(
        orgId: widget.orgId,
        existingTransaction: transaction,
      ),
    ).then((result) {
      if (result is String && result.isNotEmpty) {
        setState(() {
          _highlightedTransactionId = result;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_tableScrollController.hasClients) {
            _tableScrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _highlightedTransactionId == result)
            setState(() => _highlightedTransactionId = null);
        });
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _archiveTransaction(TransactionModel transaction) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.archive_outlined,
                      color: Color(0xFF6B7280),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Archive Transaction',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: OrgColors.charcoal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Archive "${transaction.segment.isNotEmpty ? transaction.segment : transaction.eventName}"? It will be removed from the active list but kept on record.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  color: OrgColors.darkGray,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: OrgColors.mediumGray),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: OrgColors.charcoal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B7280),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    child: Text(
                      'Archive',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(transaction.id)
          .update({'isArchived': true});
      await activity_log.ActivityLogger.log(
        action: 'archive_transaction',
        module: 'finance',
        details: {
          'orgId': widget.orgId,
          'transactionId': transaction.id,
          'amount': transaction.amount,
        },
      );
      if (mounted) {
        _showSnack('Transaction archived', OrgColors.success);
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', OrgColors.error);
    }
  }

  Future<void> _unarchiveTransaction(TransactionModel transaction) async {
    try {
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(transaction.id)
          .update({'isArchived': false});
      await activity_log.ActivityLogger.log(
        action: 'unarchive_transaction',
        module: 'finance',
        details: {
          'orgId': widget.orgId,
          'transactionId': transaction.id,
          'amount': transaction.amount,
        },
      );
      if (mounted) {
        _showSnack('Transaction restored to active list', OrgColors.success);
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', OrgColors.error);
    }
  }

  void _viewTransactionDetails(TransactionModel transaction) {
    final isIncome = transaction.type == 'income';
    final accent = isIncome ? OrgColors.success : OrgColors.error;
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => OrgModalShell(
        accentColor: accent,
        icon: isIncome
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded,
        title: transaction.eventName,
        subtitle: DateFormat('MMMM d, yyyy').format(transaction.date.toDate()),
        width: 440,
        footerActions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openEditModal(transaction);
            },
            icon: const Icon(Icons.edit_outlined, size: 15),
            label: Text(
              'Edit',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: UpriseColors.primaryDark,
              side: BorderSide(color: UpriseColors.primaryDark.withAlpha(102)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // Column defaults to MainAxisSize.max, so without this it filled
            // every bit of height OrgModalShell's Flexible offered (up to
            // its 0.85-of-viewport cap) instead of shrinking to this short
            // content — leaving a large dead gap below "Event" before the
            // footer. Confirmed via a widget test: same body measured
            // 765px (== 900 * 0.85, the cap) without this, 461px with it.
            mainAxisSize: MainAxisSize.min,
            children: [
              // Amount up front and prominent — the one number an org
              // actually opens this dialog to double-check — instead of
              // buried as just another label/value row.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: accent.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withAlpha(51)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isIncome ? 'INCOME' : 'EXPENSE',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: accent,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${isIncome ? '+' : '-'}₱${NumberFormat('#,###.00').format(transaction.amount)}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              OrgDetailItem(
                label: 'Category',
                value: transaction.category,
                icon: Icons.sell_outlined,
                iconColor: UpriseColors.primaryDark,
              ),
              const SizedBox(height: 14),
              OrgDetailItem(
                label: 'Description',
                value: transaction.segment.isNotEmpty
                    ? transaction.segment
                    : 'No description added',
                icon: Icons.notes_rounded,
              ),
              const SizedBox(height: 14),
              OrgDetailItem(
                label: 'Event',
                value: transaction.eventName,
                icon: Icons.event_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.beVietnamPro()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // Standard accounting notation: expenses are wrapped in parentheses (e.g.
  // "(1,000.00)") instead of printing an unsigned figure identical to
  // income, so an exported ledger reads the way a real accounting ledger
  // does instead of relying solely on the Type column to tell them apart.
  String _accountingAmount(TransactionModel t) {
    final formatted = NumberFormat('#,##0.00').format(t.amount);
    return t.type == 'expense' ? '($formatted)' : formatted;
  }

  Future<void> _exportTransactions(
    String choice,
    List<TransactionModel> transactions,
  ) async {
    final filtered = _filterTransactions(transactions);
    if (filtered.isEmpty) {
      _showSnack('No transactions to export', OrgColors.warning);
      return;
    }
    if (choice == 'pdf') {
      // PDF generation is CPU-bound and blocks the UI thread for a moment on
      // web — show feedback now so it doesn't look like the page froze.
      _showSnack('Generating PDF…', UpriseColors.primaryDark);
    }
    final headers = [
      'Event Name',
      'Category',
      'Segment',
      'Amount',
      'Type',
      'Date',
    ];
    final rows = filtered.map((t) {
      return [
        t.eventName,
        t.category,
        t.segment,
        _accountingAmount(t),
        t.type,
        DateFormat('MM/dd/yyyy').format(t.date.toDate()),
      ];
    }).toList();
    try {
      if (choice == 'csv') {
        final csv = [headers, ...rows]
            .map(
              (row) => row.map((c) => '"${c.replaceAll('"', '""')}"').join(','),
            )
            .join('\n');
        await OrgExportUtil.saveText(
          csv,
          'transactions_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
          mimeType: 'text/csv',
        );
      } else if (choice == 'pdf') {
        final pdfBytes = await OrgExportPdf.generateTablePdf(
          title: 'Transactions',
          headers: headers,
          rows: rows,
          orgLogoUrl: _orgLogoUrl,
        );
        await OrgExportUtil.saveBytes(
          pdfBytes,
          'transactions_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
          mimeType: 'application/pdf',
        );
      }
      _showSnack('Exported ${filtered.length} transactions', OrgColors.success);
    } catch (e) {
      _showSnack('Export failed: $e', OrgColors.error);
    }
  }

  Future<void> _showGenerateReportDialog(
    BuildContext context,
    List<TransactionModel> transactions,
  ) async {
    final events = [
      'All Events',
      ...{for (var t in transactions) t.eventName}.toList()..sort(),
    ];
    String selectedEvent = 'All Events';
    DateTime? startDate;
    DateTime? endDate;
    String selectedFormat = 'pdf';
    String selectedSchoolYear = SchoolYearUtil.currentSchoolYear();
    String selectedSemester = SchoolYearUtil.wholeYear;
    // Filter by a specific event, a date range, or a school year/semester —
    // not combinable. Date-range and semester modes also pull in archived
    // transactions that fall within the range, since "export everything
    // from this period" should include records the org has since archived.
    String reportMode = 'event';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> pickDate(bool isStart) async {
              final initial = isStart
                  ? startDate ??
                        DateTime.now().subtract(const Duration(days: 30))
                  : endDate ?? DateTime.now();
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: initial,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                // Material 3's default seed skews purple/indigo unless the
                // scheme is seeded from the brand color instead.
                builder: (context, child) {
                  final baseTheme = Theme.of(context);
                  final scheme =
                      ColorScheme.fromSeed(
                        seedColor: UpriseColors.primaryDark,
                        brightness: Brightness.light,
                      ).copyWith(
                        primary: UpriseColors.primaryDark,
                        onPrimary: Colors.white,
                        surface: Colors.white,
                        surfaceTint: Colors.transparent,
                      );
                  return Theme(
                    data: baseTheme.copyWith(
                      colorScheme: scheme,
                      textButtonTheme: TextButtonThemeData(
                        style: TextButton.styleFrom(
                          foregroundColor: UpriseColors.primaryDark,
                        ),
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked == null) return;
              setDialogState(() {
                if (isStart) {
                  startDate = picked;
                  if (endDate != null && endDate!.isBefore(picked))
                    endDate = picked;
                } else {
                  endDate = picked;
                  if (startDate != null && startDate!.isAfter(picked))
                    startDate = picked;
                }
              });
            }

            final filtered = _applyReportFilters(
              transactions,
              mode: reportMode,
              eventFilter: selectedEvent,
              startDate: startDate,
              endDate: endDate,
              schoolYear: selectedSchoolYear,
              semester: selectedSemester,
            );
            final archivedIncluded =
                (reportMode == 'dateRange' || reportMode == 'semester')
                ? filtered.where((t) => t.isArchived).length
                : 0;

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: 520,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(dialogContext).size.height * 0.85,
                ),
                decoration: BoxDecoration(
                  color: OrgColors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: _DS.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                      decoration: const BoxDecoration(
                        color: UpriseColors.primaryDark,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.insert_drive_file_outlined,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Generate Financial Report',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    // Body
                    Flexible(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FieldLabel('REPORT BY'),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _FormatChip(
                                    label: 'Specific Event',
                                    icon: Icons.event_outlined,
                                    selected: reportMode == 'event',
                                    onTap: () => setDialogState(() {
                                      reportMode = 'event';
                                      startDate = null;
                                      endDate = null;
                                    }),
                                  ),
                                  const SizedBox(width: 10),
                                  _FormatChip(
                                    label: 'Date Range',
                                    icon: Icons.date_range_outlined,
                                    selected: reportMode == 'dateRange',
                                    onTap: () => setDialogState(() {
                                      reportMode = 'dateRange';
                                      selectedEvent = 'All Events';
                                    }),
                                  ),
                                  const SizedBox(width: 10),
                                  _FormatChip(
                                    label: 'School Year',
                                    icon: Icons.school_outlined,
                                    selected: reportMode == 'semester',
                                    onTap: () => setDialogState(() {
                                      reportMode = 'semester';
                                      selectedEvent = 'All Events';
                                    }),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (reportMode == 'semester') ...[
                                _FieldLabel('SCHOOL YEAR'),
                                const SizedBox(height: 6),
                                _StyledDropdown<String>(
                                  value: selectedSchoolYear,
                                  items: SchoolYearUtil.schoolYears()
                                      .map(
                                        (y) => DropdownMenuItem(
                                          value: y,
                                          child: Text(y),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) => setDialogState(
                                    () => selectedSchoolYear =
                                        v ?? SchoolYearUtil.currentSchoolYear(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _FieldLabel('SEMESTER'),
                                const SizedBox(height: 6),
                                _StyledDropdown<String>(
                                  value: selectedSemester,
                                  items:
                                      [
                                            SchoolYearUtil.wholeYear,
                                            ...SchoolYearUtil.semesters,
                                          ]
                                          .map(
                                            (s) => DropdownMenuItem(
                                              value: s,
                                              child: Text(s),
                                            ),
                                          )
                                          .toList(),
                                  onChanged: (v) => setDialogState(
                                    () => selectedSemester =
                                        v ?? SchoolYearUtil.wholeYear,
                                  ),
                                ),
                              ] else if (reportMode == 'event') ...[
                                _FieldLabel('FILTER BY EVENT'),
                                const SizedBox(height: 6),
                                _StyledDropdown<String>(
                                  value: selectedEvent,
                                  items: events
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) => setDialogState(
                                    () => selectedEvent = v ?? 'All Events',
                                  ),
                                ),
                              ] else ...[
                                _FieldLabel('FILTER BY DATE'),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => pickDate(true),
                                        style: OutlinedButton.styleFrom(
                                          backgroundColor: OrgColors.lightGray,
                                          side: const BorderSide(
                                            color: OrgColors.mediumGray,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                        ),
                                        child: Text(
                                          startDate == null
                                              ? 'Start date'
                                              : DateFormat(
                                                  'MMM d, yyyy',
                                                ).format(startDate!),
                                          style: GoogleFonts.beVietnamPro(
                                            color: OrgColors.charcoal,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => pickDate(false),
                                        style: OutlinedButton.styleFrom(
                                          backgroundColor: OrgColors.lightGray,
                                          side: const BorderSide(
                                            color: OrgColors.mediumGray,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                        ),
                                        child: Text(
                                          endDate == null
                                              ? 'End date'
                                              : DateFormat(
                                                  'MMM d, yyyy',
                                                ).format(endDate!),
                                          style: GoogleFonts.beVietnamPro(
                                            color: OrgColors.charcoal,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.inventory_2_outlined,
                                      size: 13,
                                      color: OrgColors.darkGray,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Includes archived transactions that fall within this range.',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 11,
                                          color: OrgColors.darkGray,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 16),
                              _FieldLabel('FORMAT'),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _FormatChip(
                                    label: 'PDF',
                                    icon: Icons.picture_as_pdf_outlined,
                                    selected: selectedFormat == 'pdf',
                                    onTap: () => setDialogState(
                                      () => selectedFormat = 'pdf',
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _FormatChip(
                                    label: 'CSV',
                                    icon: Icons.table_chart_outlined,
                                    selected: selectedFormat == 'csv',
                                    onTap: () => setDialogState(
                                      () => selectedFormat = 'csv',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F6FF),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFBFD7FF),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      size: 15,
                                      color: Color(0xFF2563EB),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        archivedIncluded > 0
                                            ? '${filtered.length} transaction(s) will be included ($archivedIncluded archived)'
                                            : '${filtered.length} transaction(s) will be included',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 12,
                                          color: const Color(0xFF1D4ED8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Footer
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: OrgColors.mediumGray),
                        ),
                        color: OrgColors.lightGray,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(18),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: OrgColors.mediumGray,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: OrgColors.darkGray,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: filtered.isEmpty
                                  ? null
                                  : () async {
                                      Navigator.pop(ctx);
                                      await _generateFinancialReport(
                                        selectedFormat,
                                        transactions,
                                        mode: reportMode,
                                        eventFilter: selectedEvent,
                                        startDate: startDate,
                                        endDate: endDate,
                                        schoolYear: selectedSchoolYear,
                                        semester: selectedSemester,
                                      );
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: UpriseColors.primaryDark,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                              ),
                              child: Text(
                                'Generate Report',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
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
          },
        );
      },
    );
  }

  Future<void> _generateFinancialReport(
    String choice,
    List<TransactionModel> transactions, {
    required String mode,
    String eventFilter = 'All Events',
    DateTime? startDate,
    DateTime? endDate,
    String? schoolYear,
    String? semester,
  }) async {
    final filtered = _applyReportFilters(
      transactions,
      mode: mode,
      eventFilter: eventFilter,
      startDate: startDate,
      endDate: endDate,
      schoolYear: schoolYear,
      semester: semester,
    );
    if (filtered.isEmpty) {
      _showSnack(
        'No transactions match the selected filters',
        OrgColors.warning,
      );
      return;
    }
    if (choice == 'pdf') {
      // PDF generation is CPU-bound and blocks the UI thread for a moment —
      // show feedback right away so it doesn't look like the page froze.
      _showSnack('Generating PDF…', UpriseColors.primaryDark);
    }
    final includeStatusColumn = mode == 'dateRange' || mode == 'semester';
    final headers = [
      'Date',
      'Event',
      'Category',
      'Description',
      'Type',
      'Amount',
      if (includeStatusColumn) 'Status',
    ];
    final rows = filtered
        .map(
          (t) => [
            DateFormat('MM/dd/yyyy').format(t.date.toDate()),
            t.eventName,
            t.category,
            t.segment,
            t.type,
            _accountingAmount(t),
            if (includeStatusColumn) (t.isArchived ? 'Archived' : 'Active'),
          ],
        )
        .toList();
    final fileName =
        'financial_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';
    try {
      if (choice == 'csv') {
        final csv = [headers, ...rows]
            .map(
              (row) => row.map((c) => '"${c.replaceAll('"', '""')}"').join(','),
            )
            .join('\n');
        await OrgExportUtil.saveText(
          csv,
          '$fileName.csv',
          mimeType: 'text/csv',
        );
      } else {
        final filters = <String>[];
        if (mode == 'event' && eventFilter != 'All Events')
          filters.add('Event: $eventFilter');
        if (mode == 'dateRange' && startDate != null)
          filters.add('From: ${DateFormat('MMM d, yyyy').format(startDate)}');
        if (mode == 'dateRange' && endDate != null)
          filters.add('To: ${DateFormat('MMM d, yyyy').format(endDate)}');
        if (mode == 'semester' && schoolYear != null) {
          filters.add(
            semester == null || semester == SchoolYearUtil.wholeYear
                ? 'School Year: $schoolYear (Whole Year)'
                : 'School Year: $schoolYear, $semester',
          );
        }
        if (mode == 'dateRange' || mode == 'semester') {
          final archivedCount = filtered.where((t) => t.isArchived).length;
          if (archivedCount > 0)
            filters.add('Includes $archivedCount archived');
        }
        final periodLabel = filters.isEmpty ? 'All time' : filters.join(' | ');

        final inflow = filtered.where((t) => t.type == 'income').toList();
        final outflow = filtered.where((t) => t.type == 'expense').toList();
        // 'PHP ' instead of '₱' — the PDF's default font has no glyph for the
        // peso symbol and renders it as a missing-character box.
        final currency = NumberFormat.currency(locale: 'en_PH', symbol: 'PHP ');
        List<List<String>> toRows(List<TransactionModel> list) => list
            .map(
              (t) => [
                DateFormat('MM/dd/yyyy').format(t.date.toDate()),
                t.eventName,
                t.category,
                t.segment,
                currency.format(t.amount),
              ],
            )
            .toList();
        double sumOf(List<TransactionModel> list) =>
            list.fold(0.0, (s, t) => s + t.amount);

        final pdfBytes = await OrgExportPdf.generateFinancialReportPdf(
          orgName: _orgName.isNotEmpty ? _orgName : 'Organization',
          periodLabel: periodLabel,
          inflowRows: toRows(inflow),
          outflowRows: toRows(outflow),
          totalInflow: sumOf(inflow),
          totalOutflow: sumOf(outflow),
          orgLogoUrl: _orgLogoUrl,
        );
        await OrgExportUtil.saveBytes(
          pdfBytes,
          '$fileName.pdf',
          mimeType: 'application/pdf',
        );
      }
      if (mounted)
        _showSnack(
          'Financial report generated successfully',
          OrgColors.success,
        );
    } catch (e) {
      if (mounted) _showSnack('Report generation failed: $e', OrgColors.error);
    }
  }

  @override
  void initState() {
    super.initState();
    _transactionsStream = FirebaseFirestore.instance
        .collection('transactions')
        .where('orgId', isEqualTo: widget.orgId)
        // Removed server-side orderBy to avoid requiring a composite index.
        // We will sort the transactions client-side in _transactionsFromSnapshot().
        .snapshots();
    _loadOrgProfile();
  }

  Future<void> _loadOrgProfile() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.orgId)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _orgName = doc.data()?['name'] ?? 'Organization';
          _orgLogoUrl = doc.data()?['logoUrl'] ?? '';
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tableScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<TransactionModel> _transactionsFromSnapshot(QuerySnapshot? snap) {
    if (snap == null) return <TransactionModel>[];
    final out = <TransactionModel>[];
    for (final doc in snap.docs) {
      try {
        out.add(TransactionModel.fromFirestore(doc));
      } catch (e) {
        // Skip invalid documents to avoid breaking the whole list
        debugPrint('org_finance: skipping invalid transaction ${doc.id}: $e');
      }
    }
    return out;
  }

  Widget _buildStreamErrorWidget(Object? error) {
    final msg = error?.toString() ?? 'Unknown error';
    debugPrint('org_finance: stream error: $msg');
    // Try to extract a Firebase console index URL
    final urlRegex = RegExp(
      r'https://console\.firebase\.google\.com/[^\s"<>]+',
    );
    final match = urlRegex.firstMatch(msg);
    final url = match?.group(0);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: OrgColors.error),
            const SizedBox(height: 12),
            Text(
              'Error loading transactions',
              style: GoogleFonts.beVietnamPro(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'There was a problem fetching transactions. This often means Firestore needs a composite index for the current query.',
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: OrgColors.darkGray,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(msg, style: GoogleFonts.beVietnamPro(fontSize: 12)),
            if (url != null) ...[
              const SizedBox(height: 10),
              Text(
                'Open this link in your browser to create the index:',
                style: GoogleFonts.beVietnamPro(fontSize: 12),
              ),
              const SizedBox(height: 6),
              SelectableText(
                url,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: OrgColors.info,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isTablet = screenWidth < 1200;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFE),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsRow(isMobile),
          _buildToolbar(isMobile, isTablet),
          const SizedBox(height: 16),
          Expanded(child: _buildMainContent(isMobile)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Stats Row ──────────────────────────────────────────────────────
  Widget _buildStatsRow(bool isMobile) {
    return StreamBuilder<QuerySnapshot>(
      stream: _transactionsStream,
      builder: (context, snapshot) {
        double income = 0, expense = 0;
        int activeCount = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            // Keep these cards reconciled with the table below, which only
            // shows archived OR active transactions depending on the toggle.
            if ((data['isArchived'] == true) != _showArchived) continue;
            activeCount++;
            final amount = (data['amount'] ?? 0).toDouble();
            if (data['type'] == 'income') {
              income += amount;
            } else {
              expense += amount;
            }
          }
        }
        final net = income - expense;
        void selectCard(int index, String type) {
          setState(() {
            if (_selectedStatCard == index) {
              _selectedStatCard = null;
              _filterType = 'all';
            } else {
              _selectedStatCard = index;
              _filterType = type;
            }
            // Stat cards reflect live (non-archived) totals — jumping into
            // one while the Archived view was active would otherwise leave
            // you looking at an empty/confusing intersection.
            _showArchived = false;
            _currentPage = 1;
          });
        }

        final statCards = [
          _StatCard(
            label: 'Total Income',
            value: '₱${NumberFormat('#,###').format(income)}',
            icon: Icons.trending_up_rounded,
            color: OrgColors.success,
            isSelected: _selectedStatCard == 0,
            onTap: () => selectCard(0, 'income'),
            expand: !isMobile,
          ),
          _StatCard(
            label: 'Total Expenses',
            value: '₱${NumberFormat('#,###').format(expense)}',
            icon: Icons.trending_down_rounded,
            color: OrgColors.error,
            isSelected: _selectedStatCard == 1,
            onTap: () => selectCard(1, 'expense'),
            expand: !isMobile,
          ),
          _StatCard(
            label: 'Net Balance',
            value: net >= 0
                ? '₱${NumberFormat('#,###').format(net)}'
                : '-₱${NumberFormat('#,###').format(net.abs())}',
            icon: Icons.account_balance_wallet_outlined,
            color: net >= 0 ? OrgColors.info : OrgColors.error,
            isSelected: _selectedStatCard == 2,
            onTap: () => selectCard(2, 'all'),
            expand: !isMobile,
          ),
          _StatCard(
            label: 'Transactions',
            value: '$activeCount',
            icon: Icons.receipt_long_outlined,
            color: UpriseColors.primaryDark,
            isSelected: _selectedStatCard == 3,
            onTap: () => selectCard(3, 'all'),
            expand: !isMobile,
          ),
        ];

        return Padding(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 16 : 28,
            isMobile ? 16 : 24,
            isMobile ? 16 : 28,
            0,
          ),
          child: isMobile
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(
                      statCards.length,
                      (i) => Padding(
                        padding: EdgeInsets.only(
                          right: i < statCards.length - 1 ? 8 : 0,
                        ),
                        child: SizedBox(width: 170, child: statCards[i]),
                      ),
                    ),
                  ),
                )
              : Row(
                  // _StatCard wraps itself in Expanded when expand:true (the
                  // desktop case here), and Expanded must be a *direct* Flex
                  // child — wrapping it in Padding like the mobile branch
                  // above would throw "Expanded widgets must be placed
                  // inside a Flex widget". Spacers have to be separate Row
                  // children instead.
                  children: [
                    for (var i = 0; i < statCards.length; i++) ...[
                      statCards[i],
                      if (i < statCards.length - 1) const SizedBox(width: 14),
                    ],
                  ],
                ),
        );
      },
    );
  }

  // ── Toolbar ────────────────────────────────────────────────────────
  Widget _buildSearchField() {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search by event, category, description…',
          hintStyle: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: const Color(0xFF9AA5B4),
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: Color(0xFF9AA5B4),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: UpriseColors.primaryDark,
              width: 1.5,
            ),
          ),
        ),
        onChanged: (v) => setState(() {
          _searchQuery = v;
          _currentPage = 1;
        }),
      ),
    );
  }

  // "Archived" now lives as a value in this same dropdown instead of a
  // separate standalone toggle chip next to it — one less floating control,
  // matching the Announcements page's filter dropdown.
  Widget _buildTypeFilterDropdown() {
    return _FilterDropdown(
      value: _showArchived ? 'archived' : _filterType,
      items: const ['all', 'income', 'expense', 'archived'],
      labels: const ['All Types', 'Income', 'Expense', 'Archived'],
      onChanged: (v) => setState(() {
        if (v == 'archived') {
          _showArchived = true;
          _filterType = 'all';
        } else {
          _showArchived = false;
          _filterType = v!;
        }
        _selectedStatCard = null;
        _currentPage = 1;
      }),
    );
  }

  Widget _buildCategoryFilterDropdown() {
    return _FilterDropdown(
      value: _filterCategory,
      items: _categories,
      labels: _categories,
      onChanged: (v) => setState(() {
        _filterCategory = v!;
        _currentPage = 1;
      }),
    );
  }

  Widget _buildGenerateReportButton() {
    return StreamBuilder<QuerySnapshot>(
      stream: _transactionsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.insert_drive_file_outlined, size: 15),
            label: Text(
              'Generate Report',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: UpriseColors.primaryDark,
              side: const BorderSide(color: UpriseColors.primaryDark),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
        final transactions = _transactionsFromSnapshot(snapshot.data);
        return OutlinedButton.icon(
          onPressed: () => _showGenerateReportDialog(context, transactions),
          icon: const Icon(Icons.insert_drive_file_outlined, size: 15),
          label: Text(
            'Generate Report',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: UpriseColors.primaryDark,
            side: const BorderSide(color: UpriseColors.primaryDark),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExportButton() {
    return StreamBuilder<QuerySnapshot>(
      stream: _transactionsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AdminExportButton(label: 'Export', onSelected: (_) {});
        }
        final transactions = _transactionsFromSnapshot(snapshot.data);
        return AdminExportButton(
          label: 'Export',
          onSelected: (choice) => _exportTransactions(choice, transactions),
        );
      },
    );
  }

  Widget _buildAddTransactionButton() {
    return ElevatedButton.icon(
      onPressed: _openAddModal,
      icon: const Icon(Icons.add_rounded, size: 15),
      label: Text(
        'Add Transaction',
        style: GoogleFonts.beVietnamPro(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: UpriseColors.primaryDark,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
    );
  }

  Widget _buildToolbar(bool isMobile, bool isTablet) {
    final horizontalPadding = isMobile ? 16.0 : 28.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        isMobile ? 14 : 20,
        horizontalPadding,
        0,
      ),
      child: isMobile
          ? Column(
              spacing: 10,
              children: [
                _buildSearchField(),
                Row(
                  spacing: 10,
                  children: [
                    Expanded(child: _buildTypeFilterDropdown()),
                    Expanded(child: _buildCategoryFilterDropdown()),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildGenerateReportButton(),
                    _buildExportButton(),
                    _buildAddTransactionButton(),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: _buildSearchField()),
                const SizedBox(width: 10),
                _buildTypeFilterDropdown(),
                const SizedBox(width: 10),
                _buildCategoryFilterDropdown(),
                const SizedBox(width: 10),
                _buildGenerateReportButton(),
                const SizedBox(width: 10),
                _buildExportButton(),
                const SizedBox(width: 10),
                _buildAddTransactionButton(),
              ],
            ),
    );
  }

  // ── Main Content: Table + Side Panel ──────────────────────────────
  Widget _buildMainContent(bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 28),
      child: StreamBuilder<QuerySnapshot>(
        stream: _transactionsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildStreamErrorWidget(snapshot.error);
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final transactions = _transactionsFromSnapshot(snapshot.data);
          final filtered = _filterTransactions(transactions);

          final totalPages = filtered.isEmpty
              ? 1
              : (filtered.length / _pageSize).ceil();
          final safePage = _currentPage.clamp(1, totalPages);
          final start = (safePage - 1) * _pageSize;
          final end = (start + _pageSize).clamp(0, filtered.length);
          final pageDocs = filtered.isEmpty
              ? <TransactionModel>[]
              : filtered.sublist(start, end);

          final tableContainer = Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8ECF0)),
              boxShadow: _DS.cardShadow,
            ),
            child: Column(
              children: [
                _buildTableHeader(filtered.length, transactions.length),
                Expanded(
                  child: transactions.isEmpty
                      ? _buildEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No transactions yet',
                          subtitle: 'Click "Add Transaction" to get started.',
                        )
                      : filtered.isEmpty
                      ? _buildEmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No matching transactions',
                          subtitle: 'Try adjusting your search or filters.',
                        )
                      : ListView.builder(
                          controller: _tableScrollController,
                          itemCount: pageDocs.length,
                          itemBuilder: (_, i) => _buildTransactionRow(
                            transaction: pageDocs[i],
                            isLast: i == pageDocs.length - 1,
                          ),
                        ),
                ),
                if (filtered.isNotEmpty)
                  _buildFooter(
                    filtered.length,
                    totalPages,
                    start,
                    end,
                    safePage,
                  ),
              ],
            ),
          );

          // Same fix as org_certificates.dart / org_event_proposals.dart:
          // the header/rows use Expanded columns, which need a bounded
          // width to divide up — pin the table to a fixed, readable width
          // that scrolls sideways on narrow screens instead of squeezing
          // those columns down to nothing. The summary panel drops below
          // the table (it has its own internal scroll for its cards, so
          // nesting it under an outer scroll just displays it at full
          // natural height instead of a fixed 300px sidebar).
          if (isMobile) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 900,
                      height: 480,
                      child: tableContainer,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SummaryPanel(orgId: widget.orgId),
                ],
              ),
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Left: Table ──
              Expanded(flex: 3, child: tableContainer),
              const SizedBox(width: 20),
              // ── Right: Summary Panel ──
              SizedBox(width: 300, child: _SummaryPanel(orgId: widget.orgId)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTableHeader(int filteredCount, int totalCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(
          bottom: BorderSide(color: OrgColors.primaryDark.withAlpha(60)),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: _headerCell('DATE')),
          Expanded(flex: 3, child: _headerCell('EVENT')),
          Expanded(flex: 2, child: _headerCell('CATEGORY')),
          Expanded(flex: 2, child: _headerCell('DESCRIPTION')),
          Expanded(flex: 2, child: _headerCell('AMOUNT')),
          Expanded(flex: 2, child: _headerCell('TYPE')),
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.centerRight,
              child: _headerCell('ACTIONS'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String text) => Text(
    text,
    style: GoogleFonts.beVietnamPro(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF64748B),
      letterSpacing: 0.7,
    ),
  );

  Widget _buildTransactionRow({
    required TransactionModel transaction,
    required bool isLast,
  }) {
    final isIncome = transaction.type == 'income';
    final amountFmt = NumberFormat('#,###.00').format(transaction.amount);
    final dateFmt = DateFormat('MM/dd/yyyy').format(transaction.date.toDate());

    return InkWell(
      hoverColor: const Color(0xFFF8F9FB),
      onTap: () => _viewTransactionDetails(transaction),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          children: [
            // Date
            Expanded(
              flex: 2,
              child: Text(
                dateFmt,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: OrgColors.darkGray,
                ),
              ),
            ),
            // Event
            Expanded(
              flex: 3,
              child: Text(
                transaction.eventName,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: UpriseColors.primaryDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Category
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: UpriseColors.primaryDark.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      transaction.category,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: UpriseColors.primaryDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Description
            Expanded(
              flex: 2,
              child: Text(
                transaction.segment.isNotEmpty ? transaction.segment : '—',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: OrgColors.darkGray,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Amount
            Expanded(
              flex: 2,
              child: Text(
                '₱$amountFmt',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isIncome ? OrgColors.success : OrgColors.error,
                ),
              ),
            ),
            // Type badge
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isIncome
                          ? OrgColors.success.withOpacity(0.12)
                          : OrgColors.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isIncome ? 'Income' : 'Expense',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isIncome ? OrgColors.success : OrgColors.error,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Actions
            Expanded(
              flex: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OrgActionIconButton(
                    icon: Icons.visibility_outlined,
                    tooltip: 'View Details',
                    color: const Color(0xFF3B82F6),
                    onTap: () => _viewTransactionDetails(transaction),
                  ),
                  const SizedBox(width: 6),
                  OrgActionIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit',
                    color: UpriseColors.primaryDark,
                    onTap: () => _openEditModal(transaction),
                  ),
                  const SizedBox(width: 6),
                  OrgActionIconButton(
                    icon: transaction.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    tooltip: transaction.isArchived ? 'Unarchive' : 'Archive',
                    color: const Color(0xFF6B7280),
                    onTap: () => transaction.isArchived
                        ? _unarchiveTransaction(transaction)
                        : _archiveTransaction(transaction),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 40, color: const Color(0xFF9AA5B4)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: OrgColors.darkGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(
    int total,
    int totalPages,
    int start,
    int end,
    int safePage,
  ) {
    const int maxVisible = 5;
    int firstPage = (safePage - maxVisible ~/ 2).clamp(1, totalPages);
    int lastPage = (firstPage + maxVisible - 1).clamp(1, totalPages);
    if (lastPage - firstPage + 1 < maxVisible && firstPage > 1) {
      firstPage = (lastPage - maxVisible + 1).clamp(1, totalPages);
    }
    final pages = List.generate(lastPage - firstPage + 1, (i) => firstPage + i);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
        color: OrgColors.lightGray,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${total == 0 ? 0 : start + 1}–$end of $total transactions',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: OrgColors.darkGray,
            ),
          ),
          Row(
            children: [
              _PageButton(
                icon: Icons.chevron_left_rounded,
                enabled: safePage > 1,
                onTap: () => setState(() => _currentPage = safePage - 1),
              ),
              const SizedBox(width: 4),
              ...pages.map(
                (p) => _PageNumButton(
                  page: p,
                  isActive: p == safePage,
                  onTap: () => setState(() => _currentPage = p),
                ),
              ),
              if (lastPage < totalPages) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '…',
                    style: GoogleFonts.beVietnamPro(
                      color: OrgColors.darkGray,
                      fontSize: 12,
                    ),
                  ),
                ),
                _PageNumButton(
                  page: totalPages,
                  isActive: safePage == totalPages,
                  onTap: () => setState(() => _currentPage = totalPages),
                ),
              ],
              const SizedBox(width: 4),
              _PageButton(
                icon: Icons.chevron_right_rounded,
                enabled: safePage < totalPages,
                onTap: () => setState(() => _currentPage = safePage + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============ SUMMARY PANEL ============
// Takes the parent's already-open transactions stream instead of opening a
// third independent live listener on the exact same org-scoped query (the
// stats row above it shared a fourth one until this was consolidated too).
class _SummaryPanel extends StatefulWidget {
  final String orgId;
  const _SummaryPanel({required this.orgId});

  @override
  State<_SummaryPanel> createState() => _SummaryPanelState();
}

class _SummaryPanelState extends State<_SummaryPanel> {
  // Was previously handed the parent's already-shared _transactionsStream
  // instead of owning its own — that stream object is a `late final` field
  // on _OrgFinanceScreenState, but every emission from it makes the parent's
  // StreamBuilder rebuild and reconstruct this whole widget subtree fresh,
  // including a brand-new StreamBuilder instance here trying to listen to
  // the same shared stream again. That reconstruction cycle never let this
  // panel's own subscription settle long enough to receive data — it kept
  // showing its permanent "waiting" state (empty charts) even though the
  // table beside it, fed the same underlying data, rendered fine. A
  // dedicated stream owned by this widget's own State (created once, not
  // re-created on every parent rebuild) sidesteps that entirely.
  late final Stream<QuerySnapshot> _stream = FirebaseFirestore.instance
      .collection('transactions')
      .where('orgId', isEqualTo: widget.orgId)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        Map<String, double> incomeByEvent = {};
        Map<String, double> expenseByEvent = {};
        double totalIncome = 0, totalExpense = 0;

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final eventName = data['eventName'] ?? 'Unknown';
          final amount = (data['amount'] ?? 0).toDouble();
          final type = data['type'];
          if (type == 'income') {
            incomeByEvent[eventName] = (incomeByEvent[eventName] ?? 0) + amount;
            totalIncome += amount;
          } else {
            expenseByEvent[eventName] =
                (expenseByEvent[eventName] ?? 0) + amount;
            totalExpense += amount;
          }
        }

        final allEvents = {
          ...incomeByEvent.keys,
          ...expenseByEvent.keys,
        }.toList();
        final netPerEvent = <String, double>{};
        for (final event in allEvents) {
          netPerEvent[event] =
              (incomeByEvent[event] ?? 0) - (expenseByEvent[event] ?? 0);
        }
        final sortedEvents = netPerEvent.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topEvents = sortedEvents.take(5).toList();

        return SingleChildScrollView(
          child: Column(
            children: [
              // Bar Chart
              _SummaryCard(
                title: 'Income vs Expenses',
                child: Column(
                  children: [
                    SizedBox(
                      height: 180,
                      child: topEvents.isEmpty
                          ? Center(
                              child: Text(
                                'No data yet',
                                style: GoogleFonts.beVietnamPro(
                                  color: OrgColors.darkGray,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : BarChart(
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                maxY: (() {
                                  final vals = [
                                    ...topEvents.map(
                                      (e) => incomeByEvent[e.key] ?? 0,
                                    ),
                                    ...topEvents.map(
                                      (e) => expenseByEvent[e.key] ?? 0,
                                    ),
                                  ];
                                  return vals.isNotEmpty
                                      ? vals.reduce((a, b) => a > b ? a : b) *
                                            1.2
                                      : 10.0;
                                })(),
                                barGroups: topEvents.asMap().entries.map((
                                  entry,
                                ) {
                                  final i = entry.key;
                                  final name = entry.value.key;
                                  return BarChartGroupData(
                                    x: i,
                                    barsSpace: 4,
                                    barRods: [
                                      BarChartRodData(
                                        toY: incomeByEvent[name] ?? 0,
                                        color: OrgColors.success,
                                        width: 10,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(4),
                                            ),
                                      ),
                                      BarChartRodData(
                                        toY: expenseByEvent[name] ?? 0,
                                        color: OrgColors.error,
                                        width: 10,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(4),
                                            ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                                titlesData: FlTitlesData(
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 28,
                                      getTitlesWidget: (value, meta) {
                                        final index = value.toInt();
                                        if (index >= 0 &&
                                            index < topEvents.length) {
                                          final name = topEvents[index].key;
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              name.length > 6
                                                  ? '${name.substring(0, 6)}…'
                                                  : name,
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 9,
                                                color: OrgColors.darkGray,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          );
                                        }
                                        return const Text('');
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 42,
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                          '₱${NumberFormat.compact().format(value)}',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 9,
                                            color: OrgColors.darkGray,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                ),
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  getDrawingHorizontalLine: (value) => FlLine(
                                    color: const Color(0xFFE8ECF0),
                                    strokeWidth: 0.8,
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                              ),
                            ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _LegendDot(color: OrgColors.success, label: 'Income'),
                        const SizedBox(width: 16),
                        _LegendDot(color: OrgColors.error, label: 'Expenses'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Per Event Summary
              _SummaryCard(
                title: 'Per Event Summary',
                child: Column(
                  children: topEvents.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No events yet',
                              style: GoogleFonts.beVietnamPro(
                                color: OrgColors.darkGray,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ]
                      : topEvents.map((entry) {
                          final inc = incomeByEvent[entry.key] ?? 0;
                          final exp = expenseByEvent[entry.key] ?? 0;
                          final net = inc - exp;
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Color(0xFFF1F5F9)),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.key,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: OrgColors.charcoal,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'In: ₱${NumberFormat('#,###').format(inc)}',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 11,
                                        color: OrgColors.success,
                                      ),
                                    ),
                                    Text(
                                      'Out: ₱${NumberFormat('#,###').format(exp)}',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 11,
                                        color: OrgColors.error,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Net: ${net >= 0 ? '' : '-'}₱${NumberFormat('#,###').format(net.abs())}',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: net >= 0
                                        ? OrgColors.success
                                        : OrgColors.error,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                ),
              ),
              const SizedBox(height: 12),

              // Semester Summary
              _SummaryCard(
                title: 'Semester Summary (2025–2026)',
                child: Column(
                  children: [
                    _SummaryRow(
                      label: 'Total Income',
                      value: '₱${NumberFormat('#,###').format(totalIncome)}',
                      color: OrgColors.success,
                    ),
                    const SizedBox(height: 8),
                    _SummaryRow(
                      label: 'Total Expenses',
                      value: '₱${NumberFormat('#,###').format(totalExpense)}',
                      color: OrgColors.error,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(color: const Color(0xFFE8ECF0), height: 1),
                    ),
                    _SummaryRow(
                      label: 'Net Balance',
                      value:
                          '₱${NumberFormat('#,###').format(totalIncome - totalExpense)}',
                      color: (totalIncome - totalExpense) >= 0
                          ? OrgColors.success
                          : OrgColors.error,
                      isBold: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============ TRANSACTION MODAL (ADD/EDIT) ============
class _TransactionModal extends StatefulWidget {
  final String orgId;
  final TransactionModel? existingTransaction;
  const _TransactionModal({required this.orgId, this.existingTransaction});

  @override
  State<_TransactionModal> createState() => _TransactionModalState();
}

class _TransactionModalState extends State<_TransactionModal> {
  final _formKey = GlobalKey<FormState>();
  final _segmentCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _manualEventCtrl = TextEditingController();
  String? _selectedEventId;
  String _selectedEventName = '';
  String _category = 'Workshops';
  String _type = 'expense';
  DateTime _selectedDate = DateTime.now();
  bool _loadingEvents = true;
  bool _submitting = false;
  List<Map<String, dynamic>> _events = [];

  final List<String> _categories = [
    'Workshops',
    'Competitions',
    'Partnerships',
    'Socials',
    'Retail',
    'General',
  ];

  bool get _isEdit => widget.existingTransaction != null;

  @override
  void initState() {
    super.initState();
    _loadEvents();
    if (_isEdit) {
      final t = widget.existingTransaction!;
      _segmentCtrl.text = t.segment;
      _amountCtrl.text = t.amount.toStringAsFixed(2);
      _selectedEventName = t.eventName;
      _selectedEventId = t.eventId.isNotEmpty ? t.eventId : null;
      _manualEventCtrl.text = t.eventName;
      _category = t.category;
      _type = t.type;
      _selectedDate = t.date.toDate();
    }
  }

  Future<void> _loadEvents() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('events')
        .where('orgId', isEqualTo: widget.orgId)
        .get();
    setState(() {
      _events = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['title'] ?? 'Untitled',
          'date': data['date'],
        };
      }).toList();
      // Sort client-side by date if available
      _events.sort((a, b) {
        final da = a['date'] as Timestamp?;
        final db = b['date'] as Timestamp?;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.toDate().compareTo(db.toDate());
      });
      _loadingEvents = false;
      if (_events.isNotEmpty && !_isEdit) {
        _selectedEventId = _events.first['id'];
        _selectedEventName = _events.first['name'];
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      // Material 3's default seed skews purple/indigo unless the scheme is
      // seeded from the brand color instead.
      builder: (context, child) {
        final baseTheme = Theme.of(context);
        final scheme =
            ColorScheme.fromSeed(
              seedColor: UpriseColors.primaryDark,
              brightness: Brightness.light,
            ).copyWith(
              primary: UpriseColors.primaryDark,
              onPrimary: Colors.white,
              surface: Colors.white,
              surfaceTint: Colors.transparent,
            );
        return Theme(
          data: baseTheme.copyWith(
            colorScheme: scheme,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: UpriseColors.primaryDark,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  // Orgs can't spend money they haven't recorded — an expense that would
  // push the balance negative is blocked here rather than letting the
  // finance totals go negative silently. Mirrors the same income-minus-
  // expense calculation the stats row uses (including archived
  // transactions, since archiving is just a display filter, not a "this
  // didn't happen" flag). When editing an existing expense, its own prior
  // amount is excluded so raising it slightly isn't double-penalized.
  Future<double> _availableBalance() async {
    final snap = await FirebaseFirestore.instance
        .collection('transactions')
        .where('orgId', isEqualTo: widget.orgId)
        .get();
    double income = 0, expense = 0;
    for (final doc in snap.docs) {
      if (_isEdit && doc.id == widget.existingTransaction!.id) continue;
      final data = doc.data();
      final amt = (data['amount'] ?? 0).toDouble();
      if (data['type'] == 'income') {
        income += amt;
      } else {
        expense += amt;
      }
    }
    return income - expense;
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;

    if (_type == 'expense') {
      final balance = await _availableBalance();
      if (amount > balance) {
        final money = NumberFormat('#,##0.00');
        _showError(
          balance <= 0
              ? 'This organization has no recorded funds yet. Add an income transaction for your starting funds before logging expenses.'
              : 'This expense (₱${money.format(amount)}) exceeds the available balance (₱${money.format(balance)}). Record more income first.',
        );
        return;
      }
    }

    setState(() => _submitting = true);
    final user = FirebaseAuth.instance.currentUser;
    final data = {
      'orgId': widget.orgId,
      'eventId': _selectedEventId ?? '',
      'eventName': _selectedEventName,
      'category': _category,
      'segment': _segmentCtrl.text.trim(),
      'amount': amount,
      'type': _type,
      'date': Timestamp.fromDate(_selectedDate),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      if (_isEdit) {
        await FirebaseFirestore.instance
            .collection('transactions')
            .doc(widget.existingTransaction!.id)
            .update(data);
        await activity_log.ActivityLogger.log(
          action: 'edit_transaction',
          module: 'finance',
          details: {
            'orgId': widget.orgId,
            'transactionId': widget.existingTransaction!.id,
          },
        );
        if (mounted) Navigator.pop(context, widget.existingTransaction!.id);
      } else {
        data['createdBy'] = user?.uid ?? '';
        data['createdAt'] = FieldValue.serverTimestamp();
        final ref = await FirebaseFirestore.instance
            .collection('transactions')
            .add(data);
        await activity_log.ActivityLogger.log(
          action: 'create_transaction',
          module: 'finance',
          details: {'orgId': widget.orgId, 'amount': amount, 'type': _type},
        );
        if (mounted) Navigator.pop(context, ref.id);
      }
    } catch (e) {
      if (mounted) _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.beVietnamPro()),
        backgroundColor: OrgColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  void dispose() {
    _segmentCtrl.dispose();
    _amountCtrl.dispose();
    _manualEventCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 480,
        decoration: BoxDecoration(
          color: OrgColors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
              decoration: const BoxDecoration(
                color: UpriseColors.primaryDark,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _isEdit ? 'Edit Transaction' : 'Add Transaction',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Transaction Type Toggle
                      _FieldLabel('TRANSACTION TYPE'),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: OrgColors.lightGray,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: OrgColors.mediumGray),
                        ),
                        child: Row(
                          children: [
                            _TypeToggle(
                              label: 'Expense',
                              isSelected: _type == 'expense',
                              selectedColor: OrgColors.error,
                              onTap: () => setState(() => _type = 'expense'),
                            ),
                            _TypeToggle(
                              label: 'Income',
                              isSelected: _type == 'income',
                              selectedColor: OrgColors.success,
                              onTap: () => setState(() => _type = 'income'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Date & Amount
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _FieldLabel('DATE'),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: _pickDate,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: OrgColors.lightGray,
                                      border: Border.all(
                                        color: const Color(0xFFE2E6EA),
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            DateFormat(
                                              'MM/dd/yyyy',
                                            ).format(_selectedDate),
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 13,
                                              color: OrgColors.charcoal,
                                            ),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.calendar_today_outlined,
                                          size: 15,
                                          color: OrgColors.darkGray,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _FieldLabel('AMOUNT (₱)', required: true),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _amountCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  style: GoogleFonts.beVietnamPro(fontSize: 13),
                                  decoration: _inputDecoration('0.00'),
                                  validator: (v) {
                                    final trimmed = v?.trim() ?? '';
                                    if (trimmed.isEmpty) return 'Required';
                                    final amount = double.tryParse(trimmed);
                                    if (amount == null || amount <= 0) {
                                      return 'Must be greater than 0';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Event
                      _FieldLabel('EVENT', required: true),
                      const SizedBox(height: 6),
                      if (_loadingEvents)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (_events.isEmpty)
                        TextFormField(
                          controller: _manualEventCtrl,
                          onChanged: (v) =>
                              setState(() => _selectedEventName = v),
                          style: GoogleFonts.beVietnamPro(fontSize: 13),
                          decoration: _inputDecoration('Enter event name'),
                          validator: (v) =>
                              v?.trim().isEmpty ?? true ? 'Required' : null,
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: _selectedEventId,
                          items: _events
                              .map<DropdownMenuItem<String>>(
                                (event) => DropdownMenuItem<String>(
                                  value: event['id'],
                                  child: Text(
                                    event['name'],
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedEventId = value;
                              _selectedEventName = _events.firstWhere(
                                (e) => e['id'] == value,
                              )['name'];
                            });
                          },
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: OrgColors.charcoal,
                          ),
                          decoration: _inputDecoration('Select event'),
                          validator: (v) => v == null ? 'Required' : null,
                        ),
                      const SizedBox(height: 16),

                      // Category
                      _FieldLabel('CATEGORY'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _category,
                        items: _categories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  c,
                                  style: GoogleFonts.beVietnamPro(fontSize: 13),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _category = v!),
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: OrgColors.charcoal,
                        ),
                        decoration: _inputDecoration('Select category'),
                      ),
                      const SizedBox(height: 16),

                      // Description
                      _FieldLabel('DESCRIPTION (OPTIONAL)'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _segmentCtrl,
                        maxLines: 2,
                        style: GoogleFonts.beVietnamPro(fontSize: 13),
                        decoration: _inputDecoration(
                          'Add notes about this transaction…',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
                color: OrgColors.lightGray,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: OrgColors.mediumGray),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: OrgColors.charcoal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: UpriseColors.primaryDark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 11,
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isEdit ? 'Save Changes' : 'Save Transaction',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
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

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.beVietnamPro(
      fontSize: 13,
      color: const Color(0xFF9AA5B4),
    ),
    filled: true,
    fillColor: const Color(0xFFF8F9FB),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
      borderSide: const BorderSide(color: UpriseColors.primaryDark, width: 1.5),
    ),
    isDense: true,
  );
}

// ============ SHARED SMALL WIDGETS ============

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback? onTap;
  // Desktop's Row relies on this self-wrapping in Expanded to fill the row
  // evenly (matches every other stat-card row in the org portal). The
  // mobile horizontal-scroll layout instead gives each card a fixed
  // SizedBox width, where an inner Expanded would crash — Expanded needs a
  // bounded main-axis size to divide up, and a horizontally scrolling Row
  // is intentionally unbounded on that axis.
  final bool expand;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isSelected = false,
    this.onTap,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final card = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : const Color(0xFFE8ECF0),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withAlpha(46),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : _DS.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: OrgColors.charcoal,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: OrgColors.darkGray,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return expand ? Expanded(child: card) : card;
  }
}

class _FilterDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final List<String> labels;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    String labelOf(String v) => labels[items.indexOf(v)];
    return AnchoredMenuTrigger<String>(
      items: items,
      labelOf: labelOf,
      selectedValue: value,
      onSelected: onChanged,
      trigger: Container(
        height: 40,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E6EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labelOf(value),
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF374151),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: Color(0xFF9AA5B4),
            ),
          ],
        ),
      ),
    );
  }
}

class _StyledDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _StyledDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        border: Border.all(color: const Color(0xFFE2E6EA)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: OrgColors.charcoal,
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: Color(0xFF9AA5B4),
          ),
        ),
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FormatChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? UpriseColors.primaryDark : OrgColors.lightGray,
            border: Border.all(
              color: selected
                  ? UpriseColors.primaryDark
                  : const Color(0xFFE2E6EA),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : OrgColors.darkGray,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : OrgColors.darkGray,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SummaryCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: _DS.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: OrgColors.charcoal,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isBold;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            color: OrgColors.darkGray,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 11,
            color: OrgColors.darkGray,
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  const _FieldLabel(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.beVietnamPro(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: OrgColors.darkGray,
      letterSpacing: 0.8,
    );
    if (!required) return Text(text, style: style);
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: text, style: style),
          TextSpan(
            text: ' *',
            style: style.copyWith(color: OrgColors.error),
          ),
        ],
      ),
    );
  }
}

class _TypeToggle extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _TypeToggle({
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: isSelected ? selectedColor : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : OrgColors.darkGray,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _PageButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? const Color(0xFF374151) : const Color(0xFFD1D5DB),
        ),
      ),
    );
  }
}

class _PageNumButton extends StatelessWidget {
  final int page;
  final bool isActive;
  final VoidCallback onTap;

  const _PageNumButton({
    required this.page,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? UpriseColors.primaryDark : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$page',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
              color: isActive ? Colors.white : const Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }
}
