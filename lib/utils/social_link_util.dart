// lib/utils/social_link_util.dart
// Orgs type social fields as bare handles per the edit form's own hints
// ('facebook.com/yourorg', '@yourorg', 'yourorg@gmail.com') rather than full
// URLs — launching that raw text directly (as both org_profile.dart's social
// card and student_organization_details_screen.dart's _SocialChip used to)
// produces a schemeless URI that url_launcher can't open. This normalizes
// any of those input shapes into an absolute, launchable URL.
String normalizeSocialUrl(String platform, String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';

  if (platform == 'gmail') {
    return value.startsWith('mailto:') ? value : 'mailto:$value';
  }

  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }

  // Strip a leading '@' or '/' — handle-style input ("@yourorg") or an
  // accidental leading slash.
  final handle = value.replaceFirst(RegExp(r'^[@/]+'), '');
  final lower = handle.toLowerCase();

  switch (platform) {
    case 'facebook':
      if (lower.startsWith('facebook.com') ||
          lower.startsWith('www.facebook.com') ||
          lower.startsWith('fb.com')) {
        return 'https://$handle';
      }
      return 'https://facebook.com/$handle';
    case 'instagram':
      if (lower.startsWith('instagram.com') ||
          lower.startsWith('www.instagram.com')) {
        return 'https://$handle';
      }
      return 'https://instagram.com/$handle';
    case 'twitter':
      if (lower.startsWith('twitter.com') ||
          lower.startsWith('x.com') ||
          lower.startsWith('www.twitter.com') ||
          lower.startsWith('www.x.com')) {
        return 'https://$handle';
      }
      return 'https://x.com/$handle';
    case 'tiktok':
      if (lower.startsWith('tiktok.com') ||
          lower.startsWith('www.tiktok.com')) {
        return 'https://$handle';
      }
      return 'https://tiktok.com/@$handle';
    default:
      return value;
  }
}
