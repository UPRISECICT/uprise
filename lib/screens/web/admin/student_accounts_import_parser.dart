class StudentImportParser {
  static List<Map<String, String>> parseRows(
    List<List<dynamic>> rows, {
    bool hasHeaderRow = true,
  }) {
    if (rows.isEmpty) return const [];

    final List<List<String>> normalizedRows = [];
    for (final rawRow in rows) {
      normalizedRows.add(
        rawRow.map((cell) => cell?.toString().trim() ?? '').toList(),
      );
    }

    final dataRows = hasHeaderRow
        ? normalizedRows.skip(1).toList()
        : normalizedRows;
    final headers = hasHeaderRow ? normalizedRows.first : null;

    final students = <Map<String, String>>[];
    for (final row in dataRows) {
      if (row.every((cell) => cell.isEmpty)) continue;

      final record = _parseRecord(row, headers: headers);
      if (record['studentId']!.isNotEmpty || record['email']!.isNotEmpty) {
        students.add(record);
      }
    }

    students.removeWhere((s) => s['studentId']!.isEmpty || s['email']!.isEmpty);
    return students;
  }

  static Map<String, String> _parseRecord(
  List<String> row, {
  List<String>? headers,
}) {
  // If the row is empty, return empty record
  if (row.isEmpty || row.every((cell) => cell.trim().isEmpty)) {
    return {
      'studentId': '',
      'fullName': '',
      'course': '',
      'schoolYear': '',
      'section': '',
      'email': '',
      'yearLevel': '',
    };
  }

  // Pad the row if it's shorter than expected
  final paddedRow = List<String>.from(row);
  while (paddedRow.length < 6) {
    paddedRow.add('');
  }

  final fallback = <String, String>{
    'studentId': paddedRow[0],
    'fullName': paddedRow[1],
    'course': paddedRow[2],
    'schoolYear': paddedRow[3],
    'section': paddedRow[4],
    'email': paddedRow[5],
    'yearLevel': paddedRow[3],
  };

  if (headers == null) {
    return fallback;
  }

  final normalizedHeaders = headers
      .map((header) => normalizeHeader(header))
      .toList(growable: false);

  final indexByHeader = <String, int>{};
  for (var i = 0; i < normalizedHeaders.length; i++) {
    if (normalizedHeaders[i].isEmpty) continue;
    indexByHeader.putIfAbsent(normalizedHeaders[i], () => i);
  }

  String getValue(String key) {
    final index = indexByHeader[key];
    if (index == null || index >= paddedRow.length) return '';
    return paddedRow[index];
  }

  final studentId = getValue('student id');
  final fullName = getValue('full name');
  final course = getValue('course');
  final schoolYear = getValue('school year') != ''
      ? getValue('school year')
      : (getValue('year level') != ''
          ? getValue('year level')
          : getValue('year'));
  final section = getValue('section');
  final email = getValue('email');

  return {
    'studentId': studentId,
    'fullName': fullName,
    'course': course,
    'schoolYear': schoolYear,
    'section': section,
    'email': email,
    'yearLevel': schoolYear,
  };
}

  static String normalizeHeader(String header) {
    final normalized = header
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();

    const synonyms = {
      'student no': 'student id',
      'student number': 'student id',
      'studentid': 'student id',
      'id number': 'student id',
      'id': 'student id',
      'name': 'full name',
      'fullname': 'full name',
      'email address': 'email',
      'email addr': 'email',
      'e mail': 'email',
      'school year': 'school year',
      'year level': 'year level',
      'yearlevel': 'year level',
      'sem': 'semester',
      'section name': 'section',
      'programme': 'program',
      'major': 'program',
      'course code': 'course',
    };

    return synonyms[normalized] ?? normalized;
  }

  static Map<String, String> inferHeaderMapping(List<String> headers) {
    final normalizedHeaders = headers
        .map(normalizeHeader)
        .toList(growable: false);
    final expectedFields = {
      'student id': 'Student ID',
      'full name': 'Full Name',
      'course': 'Course',
      'school year': 'School Year',
      'year level': 'Year Level',
      'section': 'Section',
      'email': 'Email',
    };

    final mapping = <String, String>{};
    for (final entry in expectedFields.entries) {
      final index = normalizedHeaders.indexWhere((h) => h == entry.key);
      if (index != -1) {
        mapping[entry.value] = headers[index];
      } else {
        mapping[entry.value] = '';
      }
    }
    return mapping;
  }
}
