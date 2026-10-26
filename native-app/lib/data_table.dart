import 'dart:convert';

import 'package:flutter/material.dart';

import 'domain.dart';

class InspectableTable extends StatelessWidget {
  final String title;
  final List<Json> data;
  const InspectableTable({super.key, required this.title, required this.data});
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const ListTile(title: Text('Записей пока нет'));
    final keys = data.first.keys.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.length > 100)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Первые 100 строк · полный набор доступен в локальной выгрузке',
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: keys.map((key) => DataColumn(label: Text(key))).toList(),
            rows: data
                .take(100)
                .map(
                  (row) => DataRow(
                    onSelectChanged: (_) => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(title),
                        content: SingleChildScrollView(
                          child: SelectableText(
                            const JsonEncoder.withIndent('  ').convert(row),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Закрыть'),
                          ),
                        ],
                      ),
                    ),
                    cells: keys
                        .map(
                          (key) => DataCell(
                            SizedBox(
                              width: 140,
                              child: Text(
                                (row[key] ?? 'Не записано').toString(),
                                softWrap: true,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}
