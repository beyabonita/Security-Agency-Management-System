import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/guard_dtr.dart';

class GuardDtrPdf {
  static Future<Uint8List> generate(GuardDtr report) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final logo = pw.MemoryImage(
      (await rootBundle.load(
        'assets/branding/sentinel_link_mark.png',
      )).buffer.asUint8List(),
    );
    final doc = pw.Document(
      title: '${GuardDtr.title} - ${report.guardName}',
      author: GuardDtr.agency,
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        build: (_) => [
          pw.Row(
            children: [
              pw.Image(logo, width: 45, height: 48),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text(
                      GuardDtr.agency,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    for (final line in [
                      GuardDtr.address1,
                      GuardDtr.address2,
                      GuardDtr.contact,
                    ])
                      pw.Text(
                        line,
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Center(
            child: pw.Text(
              GuardDtr.title,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            ),
          ),
          pw.SizedBox(height: 14),
          for (final line in [
            'Guard Name: ${report.guardName}',
            'Detachment: ${report.detachment}',
            'Period Covered: ${report.period.label}',
          ])
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
            ),
          pw.SizedBox(height: 5),
          pw.TableHelper.fromTextArray(
            headers: GuardDtr.columns,
            data: report.rows,
            columnWidths: {
              0: const pw.FlexColumnWidth(12),
              1: const pw.FlexColumnWidth(58),
              for (var i = 2; i < 6; i++) i: const pw.FlexColumnWidth(28),
            },
            border: pw.TableBorder.all(color: PdfColors.grey600, width: .5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(5),
            cellHeight: 19,
            cellAlignment: pw.Alignment.center,
            cellAlignments: {1: pw.Alignment.centerLeft},
          ),
          pw.SizedBox(height: 8),
          for (final note in report.notes)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(note, style: const pw.TextStyle(fontSize: 8)),
            ),
          pw.Text(
            'I hereby certify that the above record is true and correct.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'NO. OF DAYS: ${report.completedDays}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'TOTAL OVERTIME: ${GuardDtr.hours(report.overtimeMinutes)}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'TOTAL WORKED: ${GuardDtr.hours(report.totalMinutes)}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              for (final label in ['Approved By', 'Guard Signature'])
                pw.Column(
                  children: [
                    pw.Container(
                      width: 150,
                      height: .5,
                      color: PdfColors.grey700,
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text(GuardDtr.footnote, style: const pw.TextStyle(fontSize: 7)),
        ],
      ),
    );
    return doc.save();
  }

  static Future<bool> save(GuardDtr report) async {
    final bytes = await generate(report);
    final result = await FilePicker.saveFile(
      fileName: report.fileName,
      bytes: bytes,
      mimeType: 'application/pdf',
      dialogTitle: 'Save your DTR',
    );
    return result != null;
  }
}
