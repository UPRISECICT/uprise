// Lightweight client-side profanity filter for private messaging (org <-> student).
// Censors matched words in-place with asterisks rather than blocking the send
// outright, so a flagged message still goes through but with the offending
// word masked.
class ProfanityFilter {
  static const List<String> _bannedWords = [
    // English
    'fuck', 'fucker', 'fucking', 'shit', 'bullshit', 'bitch', 'asshole',
    'bastard', 'dick', 'pussy', 'cunt', 'slut', 'whore', 'nigger', 'nigga',
    'faggot', 'retard',
    // Filipino / Taglish
    'putangina', 'putanginamo', 'puta', 'gago', 'gaga', 'tangina', 'tanginamo',
    'ulol', 'tarantado', 'tarantada', 'leche', 'lintik', 'kupal', 'pokpok',
    'burat', 'tite', 'puke', 'bobo', 'bobo', 'inutil', 'hayop', 'hayup',
    'peste', 'buwisit', 'punyeta',
  ];

  static final RegExp _wordPattern = RegExp(
    _bannedWords.map((w) => '\\b${RegExp.escape(w)}\\b').join('|'),
    caseSensitive: false,
  );

  static String filter(String text) {
    return text.replaceAllMapped(_wordPattern, (m) => '*' * m.group(0)!.length);
  }

  static bool containsProfanity(String text) => _wordPattern.hasMatch(text);
}
