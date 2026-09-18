import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'mask_editor_screen.dart';
import 'patient_details_screen.dart';

Future<void> shareAssessmentPdf({
  required PatientRecord patient,
  required Uint8List originalBytes,
  required Uint8List? aiBytes,
  required Uint8List combinedBytes,
  required double? aiMaskCoverage,
  required double burnPercentage,
  required Set<String> selectedRegions,
  required double totalFluidMl,
  required double aiSensitivity,
  required bool enhanceQuality,
  required bool blurFace,
  required double aiOpacity,
  required String tbsaMethod,
}) async {
  final document = pw.Document();
  final original = pw.MemoryImage(originalBytes);
  final combined = pw.MemoryImage(combinedBytes);

  document.addPage(
    pw.Page(
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Burn Assessment Report',
            style: pw.Theme.of(context).header2,
          ),
          pw.SizedBox(height: 16),
          pw.Text('Patient: ${patient.name}'),
          pw.Text('Age: ${patient.age} years | Weight: ${patient.weightKg} kg'),
          pw.Text('Gender: ${patient.gender}'),
          if (patient.patientId != null)
            pw.Text('Patient ID: ${patient.patientId}'),
          if (patient.injuryCause != null)
            pw.Text('Cause: ${patient.injuryCause}'),
          if (patient.injuryDateTime != null)
            pw.Text('Injury time: ${patient.injuryDateTime}'),
          if (patient.notes != null) pw.Text('Notes: ${patient.notes}'),
          pw.SizedBox(height: 12),
          pw.Text('Final TBSA: ${burnPercentage.toStringAsFixed(2)}%'),
          pw.Text('TBSA method: $tbsaMethod'),
          if (aiMaskCoverage != null)
            pw.Text('AI detected area: ${aiMaskCoverage.toStringAsFixed(2)}%'),
          pw.Text(
            'Selected regions: ${selectedRegions.isEmpty ? 'None' : selectedRegions.join(', ')}',
          ),
          pw.Text(
            'Estimated 24-hour fluid: ${totalFluidMl.toStringAsFixed(0)} mL',
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'AI settings: sensitivity ${aiSensitivity.toStringAsFixed(1)}, '
            'enhancement ${enhanceQuality ? 'on' : 'off'}, '
            'face blur ${blurFace ? 'on' : 'off'}, '
            'overlay opacity ${(aiOpacity * 100).round()}%',
          ),
          pw.SizedBox(height: 16),
          pw.Text('Original image', style: pw.Theme.of(context).header3),
          pw.SizedBox(height: 8),
          pw.Center(child: pw.Image(original, height: 320)),
        ],
      ),
    ),
  );

  document.addPage(
    pw.Page(
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('AI and human review', style: pw.Theme.of(context).header2),
          pw.SizedBox(height: 16),
          if (aiBytes != null) ...[
            pw.Text('AI-detected region', style: pw.Theme.of(context).header3),
            pw.SizedBox(height: 8),
            pw.Center(child: pw.Image(pw.MemoryImage(aiBytes), height: 300)),
            pw.SizedBox(height: 18),
          ],
          pw.Text(
            'AI + manual correction',
            style: pw.Theme.of(context).header3,
          ),
          pw.SizedBox(height: 8),
          pw.Center(child: pw.Image(combined, height: 360)),
          pw.SizedBox(height: 16),
          pw.Text(
            'Legend: red = AI detected, blue = manually added, '
            'amber = privacy covered, erased areas are removed.',
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'This report supports clinical assessment and does not replace local burn protocols.',
          ),
        ],
      ),
    ),
  );

  await Printing.sharePdf(
    bytes: await document.save(),
    filename: 'burn_assessment_${patient.name.replaceAll(' ', '_')}.pdf',
  );
}

class ResultScreen extends StatelessWidget {
  final File imageFile;
  final PatientRecord patient;
  final ui.Image? aiMaskImage;
  final List<MaskStroke> strokes;
  final double? aiMaskCoverage;
  final double burnPercentage;

  const ResultScreen({
    required this.imageFile,
    required this.patient,
    required this.aiMaskImage,
    required this.strokes,
    required this.aiMaskCoverage,
    required this.burnPercentage,
    super.key,
  });

  Future<void> _downloadPdf(BuildContext context) async {
    final imageBytes = await imageFile.readAsBytes();
    final document = pw.Document();
    final image = pw.MemoryImage(imageBytes);

    document.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Burn Assessment Report',
              style: pw.Theme.of(context).header2,
            ),
            pw.SizedBox(height: 16),
            pw.Text('Patient: ${patient.name}'),
            pw.Text(
              'Age: ${patient.age} years | Weight: ${patient.weightKg} kg',
            ),
            pw.Text('Gender: ${patient.gender}'),
            pw.SizedBox(height: 12),
            pw.Text('Final TBSA: ${burnPercentage.toStringAsFixed(2)}%'),
            if (aiMaskCoverage != null)
              pw.Text(
                'AI detected area: ${aiMaskCoverage!.toStringAsFixed(2)}%',
              ),
            pw.SizedBox(height: 20),
            pw.Center(child: pw.Image(image, height: 360)),
            pw.SizedBox(height: 12),
            pw.Text(
              'This report supports clinical assessment and does not replace local burn protocols.',
            ),
          ],
        ),
      ),
    );

    await Printing.sharePdf(
      bytes: await document.save(),
      filename: 'burn_assessment_${patient.name.replaceAll(' ', '_')}.pdf',
    );
  }

  Widget _imagePanel({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: child,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assessment result'),
        actions: [
          IconButton(
            tooltip: 'Download or share PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _downloadPdf(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${patient.age} years | ${patient.weightKg} kg | ${patient.gender}',
                  ),
                  const Divider(height: 24),
                  Text(
                    'Final TBSA ${burnPercentage.toStringAsFixed(2)}%',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (aiMaskCoverage != null)
                    Text(
                      'AI-only estimate: ${aiMaskCoverage!.toStringAsFixed(2)}%',
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _imagePanel(
            title: 'Original image',
            child: Image.file(imageFile, fit: BoxFit.contain),
          ),
          const SizedBox(height: 20),
          _imagePanel(
            title: 'AI-detected region',
            child: aiMaskImage == null
                ? const Center(child: Text('AI result unavailable'))
                : RawImage(image: aiMaskImage, fit: BoxFit.contain),
          ),
          const SizedBox(height: 20),
          _imagePanel(
            title: 'AI + manual regions',
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(imageFile, fit: BoxFit.fill),
                CustomPaint(
                  painter: MaskPainter(
                    aiMaskImage: aiMaskImage,
                    strokes: strokes,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _downloadPdf(context),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Download result as PDF'),
          ),
        ],
      ),
    );
  }
}
