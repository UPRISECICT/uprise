// lib/screens/web/admin/export_excel.dart
//
// Shared styled-workbook generator for every admin "Export" dropdown's
// spreadsheet option — replaces plain, unstyled CSV (which can't carry any
// styling at all; a spreadsheet app's own toolbar chrome is not part of the
// file) with a real .xlsx: a title bar, a filled/bold header row, and
// zebra-striped, sized data columns. Matches the palette used by the batch
// import template in student_accounts.dart so every admin export reads as
// one consistent, designed system instead of a bare data dump.
import 'package:excel/excel.dart' hide Border, TextSpan;

class AdminExportExcel {
  static const _brandAmber = 'FFB45309';
  static const _titleText = 'FF1E293B';
  static const _bodyText = 'FF374151';
  static const _zebraFill = 'FFF8F9FB';

  /// Builds a single-sheet styled workbook and returns its raw bytes,
  /// ready for `AdminExportUtil.saveBytes(..., mimeType: xlsxMimeType)`.
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
      backgroundColorHex: ExcelColor.fromHexString(_brandAmber),
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

const xlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
