// lib/widgets/common/terms_and_conditions.dart
//
// Shared Terms & Conditions content and UI for UPRISE — used at every
// first-time account setup across the system (student, guest/external
// applicant, organization officer, administrator). Keeping the text and
// the "agree" checkbox in one place means every role reads and accepts
// the same document instead of four drifting copies.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const String kAppLegalEntity =
    'Bulacan State University — College of Information and Communications Technology (CICT)';

class _TermsSection {
  final String title;
  final String body;
  const _TermsSection(this.title, this.body);
}

const List<_TermsSection> _kTermsSections = [
  _TermsSection(
    '1. Acceptance of These Terms',
    'UPRISE is a student-organization management platform operated for the '
        '$kAppLegalEntity. By creating an account, logging in, or otherwise '
        'using UPRISE — whether as a student, guest/external applicant, '
        'organization officer, or administrator — you agree to be bound by '
        'these Terms and Conditions and by the UPRISE Privacy Notice below. '
        'If you do not agree, do not proceed with account setup.',
  ),
  _TermsSection(
    '2. Account Roles and Eligibility',
    'UPRISE issues four account types: Student (CICT-enrolled students, '
        'accounts are created and managed by the Admin), Organization '
        'Officer (created by the Admin on behalf of a recognized CICT '
        'student organization), Administrator (CICT system administrators), '
        'and Guest (external individuals whose access is granted only after '
        'Admin review and approval of a submitted application). You are '
        'responsible for using only the account role assigned to you and '
        'for the accuracy of the personal information provided during '
        'account setup or application.',
  ),
  _TermsSection(
    '3. Account Security',
    'Temporary passwords issued at account creation must be changed on '
        'first login before the account can be used. You are responsible '
        'for keeping your login credentials confidential and for all '
        'activity that occurs under your account. Notify your organization '
        'officer or the CICT Admin immediately if you suspect unauthorized '
        'access to your account.',
  ),
  _TermsSection(
    '4. Acceptable Use',
    'You agree to use UPRISE only for legitimate CICT organizational and '
        'academic purposes: registering for events, viewing announcements, '
        'communicating through the platform\'s official channels, and — for '
        'organization officers — managing events, reports, and members of '
        'their own recognized organization. You agree not to impersonate '
        'another person, share your account with others, upload harmful or '
        'offensive content, or attempt to access data, features, or '
        'accounts that are not assigned to your role.',
  ),
  _TermsSection(
    '5. Event Attendance and Verification Codes',
    'Where an event uses QR check-in or a live rotating attendance code, '
        'that code is displayed only to students who are physically present '
        'at the event. Codes are personal to the session in which they are '
        'shown and must not be photographed, screenshotted, or shared with '
        'anyone who is not present. Submitting an attendance code on behalf '
        'of another student, or using a code obtained through any means '
        'other than physical attendance, is a violation of these Terms and '
        'may result in the attendance record being voided and the account '
        'being reported to the organization or the CICT Admin.',
  ),
  _TermsSection(
    '6. Certificates',
    'Certificates of participation are issued at the discretion of the '
        'hosting organization after an attendee\'s presence has been '
        'verified and, where required, after post-event feedback has been '
        'submitted. Each certificate carries a unique verification code '
        'that can be checked through the public certificate verification '
        'page. Certificates are non-transferable and remain the property '
        'of the issuing organization; falsifying or altering a certificate '
        'is prohibited.',
  ),
  _TermsSection(
    '7. Content You Submit',
    'Organization officers who submit event proposals, financial reports, '
        'accomplishment reports, or other documents through UPRISE are '
        'responsible for the accuracy and completeness of that content. '
        'The Admin may review, approve, reject, or request revisions to '
        'submitted content as part of the university\'s organizational '
        'oversight process. Do not upload documents or images that you do '
        'not have the right to share.',
  ),
  _TermsSection(
    '8. Communications',
    'By using UPRISE you consent to receive in-app notifications, '
        'announcements, and organizational broadcast messages relevant to '
        'your account role. Organization-to-student broadcast messages are '
        'one-way informational announcements; students may view but cannot '
        'reply to them within that channel. UPRISE communications are for '
        'official CICT organizational purposes only.',
  ),
  _TermsSection(
    '9. Guest and External Applicant Access',
    'Guest access is not automatic. Submitting a registration request does '
        'not guarantee approval — the CICT Admin reviews each application '
        'and may approve, deny, or request additional information at their '
        'discretion. Approved guest accounts are limited to the features '
        'made available to the Guest role (event browsing, announcements, '
        'digital ID, and feedback) and may be suspended if used outside '
        'that scope.',
  ),
  _TermsSection(
    '10. Data Privacy',
    'UPRISE collects and processes personal data — such as your name, '
        'student number or affiliation, course, year level, contact '
        'details, attendance and registration records, submitted feedback, '
        'and any images or documents you upload for organizational reports '
        '— strictly to operate student-organization functions: event '
        'registration and attendance tracking, certificate issuance, '
        'organizational reporting, and account administration. Data is '
        'processed in accordance with the Data Privacy Act of 2012 (RA '
        '10173) and its implementing rules. Data is retained for as long '
        'as your account remains active or as required for academic and '
        'organizational recordkeeping, and is not sold or shared with '
        'third parties outside legitimate university and organizational '
        'use. You may request access to, correction of, or deletion of '
        'your personal data by contacting your CICT student organization '
        'coordinator or the system Admin, subject to records that must be '
        'retained for institutional or legal purposes.',
  ),
  _TermsSection(
    '11. Intellectual Property',
    'The UPRISE name, interface, and underlying software belong to its '
        'developers and the $kAppLegalEntity. Content submitted by '
        'organizations (event materials, reports, certificates, and '
        'announcements) remains the property of the submitting organization '
        'or its members, who grant UPRISE a limited license to display and '
        'process that content solely for the platform\'s operation.',
  ),
  _TermsSection(
    '12. Suspension and Termination',
    'Accounts found to violate these Terms — including code-sharing, '
        'impersonation, falsified attendance or certificates, or misuse of '
        'organizational data — may be suspended or terminated by the '
        'Admin without prior notice. Organizations may also request the '
        'removal of a member\'s access to their organization\'s tools.',
  ),
  _TermsSection(
    '13. Changes to These Terms',
    'These Terms may be updated from time to time to reflect changes to '
        'UPRISE\'s features or applicable policy. Continued use of the '
        'platform after an update constitutes acceptance of the revised '
        'Terms. Material changes will be reflected by an updated "last '
        'revised" reference maintained by the system Admin.',
  ),
  _TermsSection(
    '14. Governing Law',
    'These Terms are governed by the laws of the Republic of the '
        'Philippines. Any dispute arising from the use of UPRISE shall '
        'first be brought to the attention of the $kAppLegalEntity for '
        'internal resolution.',
  ),
  _TermsSection(
    '15. Contact',
    'Questions about these Terms or about your data may be directed to '
        'your organization officer or the CICT system Administrator '
        'through the official channels of the $kAppLegalEntity.',
  ),
];

/// Full-screen, scrollable Terms & Conditions document. [accent] lets each
/// role's flow (admin/org = blue-gray, student/guest = orange) present this
/// in its own theme color without duplicating the text.
class TermsAndConditionsScreen extends StatelessWidget {
  final Color accent;
  const TermsAndConditionsScreen({
    super.key,
    this.accent = const Color(0xFFEA580C),
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF1E293B),
        title: Text(
          'Terms and Conditions',
          style: GoogleFonts.beVietnamPro(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1E293B),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: accent.withAlpha(18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withAlpha(60)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.gavel_rounded, size: 20, color: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'UPRISE — Terms and Conditions & Data Privacy Notice\n'
                      '$kAppLegalEntity',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF334155),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            for (final section in _kTermsSections) ...[
              Text(
                section.title,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                section.body,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: const Color(0xFF475569),
                  height: 1.65,
                ),
              ),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

/// "I have read and agree..." checkbox row used at every first-time
/// account-setup flow. Tapping the linked text opens the full document;
/// [onChanged] drives whatever gate (enable/disable submit) the caller needs.
class TermsAgreementCheckbox extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accent;
  final Color textColor;

  const TermsAgreementCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.accent = const Color(0xFFEA580C),
    this.textColor = const Color(0xFF475569),
  });

  @override
  State<TermsAgreementCheckbox> createState() => _TermsAgreementCheckboxState();
}

class _TermsAgreementCheckboxState extends State<TermsAgreementCheckbox> {
  late final TapGestureRecognizer _tapRecognizer;

  @override
  void initState() {
    super.initState();
    _tapRecognizer = TapGestureRecognizer()..onTap = _openTerms;
  }

  @override
  void dispose() {
    _tapRecognizer.dispose();
    super.dispose();
  }

  void _openTerms() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TermsAndConditionsScreen(accent: widget.accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => widget.onChanged(!widget.value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: widget.value,
                  onChanged: (v) => widget.onChanged(v ?? false),
                  activeColor: widget.accent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12.5,
                    color: widget.textColor,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'I have read and agree to the '),
                    TextSpan(
                      text: 'Terms and Conditions',
                      style: TextStyle(
                        color: widget.accent,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: _tapRecognizer,
                    ),
                    const TextSpan(
                      text: ', including how my data is collected and used.',
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
}
