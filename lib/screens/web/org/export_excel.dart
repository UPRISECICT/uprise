// lib/screens/web/org/export_excel.dart
//
// Shared styled-workbook generator for every org "Export" dropdown's
// spreadsheet option — mirrors admin's export_excel.dart exactly (title
// bar, filled/bold header row, zebra-striped data columns) but themed with
// the org portal's own brand color instead of admin's.
import 'package:excel/excel.dart' hide Border, TextSpan;

class OrgExportExcel {
  static const _brandOrange = 'FFC2410C';
  static const _titleText = 'FF1E293B';
  static const _bodyText = 'FF374151';
  static const _zebraFill = 'FFF8F9FB';

  /// Builds a single-sheet styled workbook and returns its raw bytes,
  /// ready for `OrgExportUtil.saveBytes(..., mimeType: orgXlsxMimeType)`.
  static List<int> generateStyledTable({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    final excel = Excel.createExcel();
    final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
    final safeName = _safeSheetName(title);
    if (safeName != defaultName) {
      excel.rename(defaultName, safeName);
    }
    // Grabbed *after* renaming — rename() clones the sheet under the new
    // name and deletes the old one, so a reference captured beforehand
    // would point at a now-deleted sheet.
    final sheet = excel[safeName];

    // ── Title bar, merged across every column ──
    final titleCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    );
    titleCell.value = TextCellValue(title);
    titleCell.cellStyle = CellStyle(
      bold: true,
      fontSize: 14,
      fontColorHex: ExcelColor.fromHexString(_titleText),
    );
    if (headers.length > 1) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        CellIndex.indexByColumnRow(
          columnIndex: headers.length - 1,
          rowIndex: 0,
        ),
      );
    }

    // ── Header row ──
    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString(_brandOrange),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1),
      );
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }

    // ── Data rows, zebra-striped ──
    final evenStyle = CellStyle(
      fontColorHex: ExcelColor.fromHexString(_bodyText),
      backgroundColorHex: ExcelColor.white,
    );
    final oddStyle = CellStyle(
      fontColorHex: ExcelColor.fromHexString(_bodyText),
      backgroundColorHex: ExcelColor.fromHexString(_zebraFill),
    );
    for (var r = 0; r < rows.length; r++) {
      final rowStyle = r.isEven ? evenStyle : oddStyle;
      final row = rows[r];
      for (var c = 0; c < headers.length; c++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 2),
        );
        cell.value = TextCellValue(c < row.length ? row[c] : '');
        cell.cellStyle = rowStyle;
      }
    }

    // ── Column widths, sized to content (bounded so one long outlier
    // cell can't blow out the whole sheet) ──
    for (var c = 0; c < headers.length; c++) {
      var maxLen = headers[c].length;
      for (final row in rows) {
        if (c < row.length && row[c].length > maxLen) maxLen = row[c].length;
      }
      sheet.setColumnWidth(c, (maxLen + 4).clamp(10, 40).toDouble());
    }

    return excel.encode() ?? <int>[];
  }

  // Excel sheet names can't exceed 31 chars or contain \ / * ? : [ ].
  static String _safeSheetName(String title) {
    var name = title.replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ').trim();
    if (name.isEmpty) name = 'Sheet1';
    if (name.length > 31) name = name.substring(0, 31);
    return name;
  }
}

const orgXlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
