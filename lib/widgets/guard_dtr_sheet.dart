import 'package:flutter/material.dart';
import '../models/guard_dtr.dart';

class GuardDtrSheet extends StatelessWidget {
  const GuardDtrSheet({
    super.key,
    required this.report,
    required this.tableScroll,
  });
  final GuardDtr report;
  final ScrollController tableScroll;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    color: Colors.white,
    child: DefaultTextStyle(
      style: const TextStyle(color: Color(0xff18202c), fontSize: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Image.asset(
              'assets/branding/sentinel_link_mark.png',
              width: 54,
              height: 64,
            ),
          ),
          const Text(
            GuardDtr.agency,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          for (final line in [
            GuardDtr.address1,
            GuardDtr.address2,
            GuardDtr.contact,
          ])
            Text(
              line,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10),
            ),
          const SizedBox(height: 14),
          const Text(
            GuardDtr.title,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          for (final line in [
            'Guard Name: ${report.guardName}',
            'Detachment: ${report.detachment}',
            'Period Covered: ${report.period.label}',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(line),
            ),
          const SizedBox(height: 6),
          Scrollbar(
            controller: tableScroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: tableScroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: 860,
                child: Table(
                  border: TableBorder.all(
                    color: const Color(0xff676d76),
                    width: .5,
                  ),
                  columnWidths: const {
                    0: FlexColumnWidth(12),
                    1: FlexColumnWidth(58),
                    2: FlexColumnWidth(28),
                    3: FlexColumnWidth(28),
                    4: FlexColumnWidth(28),
                    5: FlexColumnWidth(28),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xffebebed)),
                      children: [
                        for (final label in GuardDtr.columns)
                          Padding(
                            padding: const EdgeInsets.all(7),
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    for (final row in report.rows)
                      TableRow(
                        children: [
                          for (var i = 0; i < row.length; i++)
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                row[i].isEmpty ? ' ' : row[i],
                                textAlign: i == 1
                                    ? TextAlign.left
                                    : TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          for (final note in report.notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(note, style: const TextStyle(fontSize: 11)),
            ),
          const SizedBox(height: 12),
          const Text(
            'I hereby certify that the above record is true and correct.',
          ),
          const SizedBox(height: 12),
          Text('NO. OF DAYS: ${report.completedDays}'),
          Text(
            'TOTAL OVERTIME HOURS: ${GuardDtr.hours(report.overtimeMinutes)}',
          ),
          Text('TOTAL WORKED HOURS: ${GuardDtr.hours(report.totalMinutes)}'),
          const SizedBox(height: 32),
          const Row(
            children: [
              Expanded(
                child: Text(
                  '________________\nApproved By',
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  '________________\nGuard Signature',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(GuardDtr.footnote, style: TextStyle(fontSize: 10)),
        ],
      ),
    ),
  );
}
