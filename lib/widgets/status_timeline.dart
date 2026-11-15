import 'package:flutter/material.dart';
import 'package:timeline_tile/timeline_tile.dart';
import 'package:intl/intl.dart';

class StatusTimeline extends StatelessWidget {
  final List<Map<String, dynamic>> statusTimeline;

  const StatusTimeline({Key? key, required this.statusTimeline})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children:
          statusTimeline.asMap().entries.map((entry) {
            final index = entry.key;
            final status = entry.value;
            final isFirst = index == 0;
            final isLast = index == statusTimeline.length - 1;

            return TimelineTile(
              alignment: TimelineAlign.start,
              isFirst: isFirst,
              isLast: isLast,
              indicatorStyle: IndicatorStyle(
                width: 30,
                color: _getStatusColor(status['status']),
                iconStyle: IconStyle(
                  iconData: _getStatusIcon(status['status']),
                  color: Colors.white,
                ),
              ),
              beforeLineStyle: LineStyle(
                color: isFirst ? Colors.transparent : Colors.blue[300]!,
                thickness: 3,
              ),
              afterLineStyle: LineStyle(
                color: isLast ? Colors.transparent : Colors.blue[300]!,
                thickness: 3,
              ),
              endChild: _buildStatusCard(status),
            );
          }).toList(),
    );
  }

  Widget _buildStatusCard(Map<String, dynamic> status) {
    // Convertir UTC a hora local
    final utcDate =
        DateTime.tryParse(status['date'] ?? '') ?? DateTime.now().toUtc();
    final localDate = utcDate.toLocal();

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              status['status'],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  DateFormat(
                    'dd/MM/yyyy - HH:mm',
                  ).format(localDate), // Usar fecha local
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            if (status['location'] != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    status['location'],
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Recibido':
        return Colors.green;
      case 'En tránsito':
        return Colors.orange;
      case 'En aduana':
        return Colors.red;
      case 'Listo para recoger':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Recibido':
        return Icons.check_circle;
      case 'En tránsito':
        return Icons.directions_car;
      case 'En aduana':
        return Icons.security;
      case 'Listo para recoger':
        return Icons.assignment_turned_in;
      default:
        return Icons.help_outline;
    }
  }

  // Eliminamos el método _formatDate ya que ahora usamos conversión directa
}
