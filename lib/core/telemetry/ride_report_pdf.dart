import '../trip/trip_manager.dart';
import 'pdf_builder.dart';

/// Builds the ride report PDF.
///
/// Every figure printed here comes from the trip record. Where a figure was
/// never measured, the section is omitted rather than filled with zero — a
/// report claiming "Engine brake: 0" for a trip recorded before Sprint 3 would
/// assert the rider never engine-braked, which is not knowable from the data.
List<int> buildRideReportPdf(TripRecord trip) {
  final p = PdfReport();

  p.bar(44, 742, 507, 4, PdfColor.cyan);
  p.line('RIDE REPORT', 22, bold: true, spaceAfter: 1);
  p.line(
    '${trip.startTime.toLocal().toString().split('.').first}   -   '
    '${trip.endTime.toLocal().toString().split('.').first}',
    9,
    color: PdfColor.grey,
    spaceAfter: 12,
  );

  p.line('RINGKASAN', 12, bold: true, color: PdfColor.cyan, spaceAfter: 2);
  p.rule(spaceAfter: 4);
  p.row('Jarak tempuh', '${trip.distanceKm.toStringAsFixed(2)} km');
  p.row('Durasi', '${trip.durationMin.toStringAsFixed(0)} menit');
  p.row('Kecepatan rata-rata', '${trip.avgSpeedKmh.toStringAsFixed(1)} km/h');
  p.row('Kecepatan tertinggi', '${trip.maxSpeedKmh.toStringAsFixed(0)} km/h');

  if (trip.fuelConsumedL > 0) {
    p.line('', 8, spaceAfter: 4);
    p.line('BENSIN', 12, bold: true, color: PdfColor.cyan, spaceAfter: 2);
    p.rule(spaceAfter: 4);
    p.row('Konsumsi', '${trip.fuelConsumedL.toStringAsFixed(2)} L');
    if (trip.avgKml > 0) {
      p.row('Rata-rata', '${trip.avgKml.toStringAsFixed(1)} km/L');
    }
    p.row('Biaya', 'Rp ${trip.tripCostIdr.toStringAsFixed(0)}');
  }

  p.line('', 8, spaceAfter: 4);
  p.line('REBAH', 12, bold: true, color: PdfColor.cyan, spaceAfter: 2);
  p.rule(spaceAfter: 4);
  p.row('Puncak kiri', '${trip.maxLeanLeftDeg.toStringAsFixed(1)} derajat');
  p.row('Puncak kanan', '${trip.maxLeanRightDeg.toStringAsFixed(1)} derajat');

  if (trip.engineBrakingCount > 0 || trip.serviceBrakingCount > 0) {
    p.line('', 8, spaceAfter: 4);
    p.line('PENANGANAN KECEPATAN', 12, bold: true, color: PdfColor.cyan,
        spaceAfter: 2);
    p.rule(spaceAfter: 4);

    if (trip.engineBrakingCount > 0) {
      p.row(
        'Engine brake',
        '${trip.engineBrakingCount} kali, ${trip.engineBrakeSeconds.toStringAsFixed(1)} detik',
        valueColor: PdfColor.amber,
      );
    }
    if (trip.serviceBrakingCount > 0) {
      p.row('Rem service', '${trip.serviceBrakingCount} kali',
          valueColor: PdfColor.red);
    }
    if (trip.hardBrakingCount > 0) {
      p.row('Rem mendadak', '${trip.hardBrakingCount} kali');
    }

    final total = trip.engineBrakingCount + trip.serviceBrakingCount;
    if (total > 0) {
      final pct = (trip.engineBrakingCount / total * 100).round();
      p.line('Mesin $pct%  -  rem ${100 - pct}%', 9, color: PdfColor.grey,
          spaceAfter: 2);
      p.meter(
        value: trip.engineBrakingCount.toDouble(),
        total: total.toDouble(),
        fill: PdfColor.amber,
        spaceAfter: 2,
      );
    }
  }

  if (trip.maxEctC > 0) {
    p.line('', 8, spaceAfter: 4);
    p.line('MESIN', 12, bold: true, color: PdfColor.cyan, spaceAfter: 2);
    p.rule(spaceAfter: 4);
    p.row(
      'Suhu radiator tertinggi',
      '${trip.maxEctC.toStringAsFixed(0)} C',
      valueColor: trip.maxEctC >= 102 ? PdfColor.red : PdfColor.black,
    );
  }

  p.line('', 10, spaceAfter: 6);
  p.line('PCX Cyber Telemetry', 8, color: PdfColor.grey);

  return p.build();
}