import 'dart:convert';
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;

import 'patient_details_screen.dart';
import 'result_screen.dart' show shareAssessmentPdf;

const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

class MaskEditScreen extends StatefulWidget {
  final XFile imageFile;
  final PatientRecord patient;

  const MaskEditScreen({
    required this.imageFile,
    required this.patient,
    super.key,
  });

  @override
  MaskEditScreenState createState() => MaskEditScreenState();
}

class MaskEditScreenState extends State<MaskEditScreen> {
  final List<MaskStroke> strokes = [];
  late final Future<Size> imageSize;
  late final Future<Uint8List> originalImageBytes;
  bool isEraser = false;
  bool isPrivacyBrush = false;
  final Set<String> selectedRegions = <String>{};
  ui.Image? aiMaskImage;
  Uint8List? protectedImageBytes;
  double? aiMaskCoverage;
  bool isDetecting = false;
  String? detectionError;
  double sensitivity = 0.5;
  bool enhanceQuality = false;
  bool blurFace = true;
  double aiOpacity = 0.45;
  double brushSize = 20;
  final GlobalKey _comparisonKey = GlobalKey();
  final ageController = TextEditingController();
  final weightController = TextEditingController();
  int? ageYears;
  double? weightKg;

  @override
  void dispose() {
    aiMaskImage?.dispose();
    ageController.dispose();
    weightController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    ageYears = widget.patient.age > 0 ? widget.patient.age : null;
    weightKg = widget.patient.weightKg > 0 ? widget.patient.weightKg : null;
    originalImageBytes = widget.imageFile.readAsBytes();
    imageSize = _loadImageSize();
    _detectBurnRegion();
  }

  Future<void> _detectBurnRegion() async {
    setState(() {
      isDetecting = true;
      detectionError = null;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_apiBaseUrl/predict'),
      );
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        await widget.imageFile.readAsBytes(),
        filename: widget.imageFile.name,
      ));
      request.fields['sensitivity'] = sensitivity.toString();
      request.fields['enhance'] = enhanceQuality.toString();
      request.fields['blur_face'] = blurFace.toString();
      final response = await request.send();
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(body);
      }
      final result = jsonDecode(body) as Map<String, dynamic>;
      final maskBytes = base64Decode(result['maskPngBase64'] as String);
      final maskCodec = await ui.instantiateImageCodec(maskBytes);
      final maskFrame = await maskCodec.getNextFrame();
      if (!mounted) return;
      setState(() {
        aiMaskImage?.dispose();
        aiMaskImage = maskFrame.image;
        protectedImageBytes = base64Decode(
          result['protectedImageBase64'] as String,
        );
        aiMaskCoverage = (result['burnPixelPercent'] as num).toDouble();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        detectionError = 'Automatic detection unavailable';
      });
      debugPrint('Burn detection failed: $error');
    } finally {
      if (mounted) {
        setState(() => isDetecting = false);
      }
    }
  }

  Future<Size> _loadImageSize() async {
    final bytes = await widget.imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    codec.dispose();
    return size;
  }

  Future<void> _showAiSettings() async {
    var nextSensitivity = sensitivity;
    var nextEnhance = enhanceQuality;
    var nextBlurFace = blurFace;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('AI detection settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enhance image quality'),
                value: nextEnhance,
                onChanged: (value) => setDialogState(() => nextEnhance = value),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('AI overlay opacity'),
              ),
              Slider(
                value: aiOpacity,
                min: 0.15,
                max: 0.9,
                divisions: 15,
                label: '${(aiOpacity * 100).round()}%',
                onChanged: (value) => setDialogState(() => aiOpacity = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Blur face automatically'),
                value: nextBlurFace,
                onChanged: (value) =>
                    setDialogState(() => nextBlurFace = value),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('AI sensitivity'),
              ),
              Slider(
                value: nextSensitivity,
                min: 0.1,
                max: 0.9,
                divisions: 8,
                label: nextSensitivity.toStringAsFixed(1),
                onChanged: (value) =>
                    setDialogState(() => nextSensitivity = value),
              ),
              const Text(
                'Higher values reduce false positives; lower values detect more possible burn pixels.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use the Privacy Brush to cover private areas. Automatic genital detection is not enabled because body geometry alone is unreliable.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  sensitivity = nextSensitivity;
                  enhanceQuality = nextEnhance;
                  blurFace = nextBlurFace;
                });
                Navigator.pop(context);
                _detectBurnRegion();
              },
              child: const Text('Run detection'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPdf() async {
    final boundary =
        _comparisonKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;

    final image = await boundary.toImage(pixelRatio: 2);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final aiBytes = aiMaskImage == null
        ? null
        : await aiMaskImage!.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (!mounted || byteData == null) return;

    await shareAssessmentPdf(
      patient: widget.patient,
      originalBytes: await widget.imageFile.readAsBytes(),
      aiBytes: aiBytes?.buffer.asUint8List(),
      combinedBytes: byteData.buffer.asUint8List(),
      aiMaskCoverage: aiMaskCoverage,
      burnPercentage: burnPercentage,
      selectedRegions: selectedRegions,
      totalFluidMl: _totalFluidMl,
      aiSensitivity: sensitivity,
      enhanceQuality: enhanceQuality,
      blurFace: blurFace,
      aiOpacity: aiOpacity,
      tbsaMethod: _usesPediatricMethod
          ? 'Simplified age-adjusted Lund-Browder (verify clinically)'
          : 'Rule of Nines',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Burn Mask'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'AI detection settings',
            onPressed: _showAiSettings,
          ),
          IconButton(
            icon: const Icon(Icons.local_hospital),
            tooltip: 'Parkland calculation',
            onPressed: _showParklandCalculator,
          ),
          IconButton(
            icon: const Icon(Icons.send),
            tooltip: 'Send Data',
            onPressed: () {
              // Yahan aap FastAPI backend ko image aur mask points bhejenge
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Mask saved! Ready to send to backend.'),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Download complete PDF report',
            onPressed: _exportPdf,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        isEraser = false;
                        isPrivacyBrush = false;
                      });
                    },
                    icon: const Icon(Icons.brush),
                    label: const Text('Add Burn Region'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: !isEraser ? Colors.red.shade50 : null,
                      foregroundColor: Colors.red.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        isEraser = true;
                        isPrivacyBrush = false;
                      });
                    },
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('Delete Burn Region'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isEraser ? Colors.blue.shade50 : null,
                      foregroundColor: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    isEraser = false;
                    isPrivacyBrush = true;
                  });
                },
                icon: const Icon(Icons.visibility_off),
                label: const Text('Privacy Brush'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: isPrivacyBrush ? Colors.amber.shade50 : null,
                  foregroundColor: Colors.amber.shade900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.brush_outlined, size: 18),
                Expanded(
                  child: Slider(
                    value: brushSize,
                    min: 8,
                    max: 44,
                    divisions: 9,
                    label: 'Brush ${brushSize.round()}',
                    onChanged: (value) => setState(() => brushSize = value),
                  ),
                ),
                IconButton(
                  tooltip: 'Undo last correction',
                  onPressed: strokes.isEmpty
                      ? null
                      : () => setState(() => strokes.removeLast()),
                  icon: const Icon(Icons.undo),
                ),
              ],
            ),
            const _MaskLegend(),
          ],
        ),
      ),
      body: FutureBuilder<Size>(
        future: imageSize,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AspectRatio(
                aspectRatio: snapshot.data!.width / snapshot.data!.height,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  boundaryMargin: const EdgeInsets.all(80),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      setState(() {
                        strokes.add(
                          MaskStroke(
                            isEraser: isEraser,
                            isPrivacy: isPrivacyBrush,
                            points: [details.localPosition],
                          ),
                        );
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        strokes.last.points.add(details.localPosition);
                      });
                    },
                    child: RepaintBoundary(
                      key: _comparisonKey,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          protectedImageBytes == null
                              ? FutureBuilder<Uint8List>(
                                  future: originalImageBytes,
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) {
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    }
                                    return Image.memory(
                                      snapshot.data!,
                                      fit: BoxFit.fill,
                                    );
                                  },
                                )
                              : Image.memory(
                                  protectedImageBytes!,
                                  fit: BoxFit.fill,
                                ),
                          CustomPaint(
                            painter: MaskPainter(
                              aiMaskImage: aiMaskImage,
                              strokes: strokes,
                              aiOpacity: aiOpacity,
                              brushSize: brushSize,
                            ),
                          ),
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _MetricBadge(
                                  text: selectedRegions.isEmpty
                                      ? 'TBSA: select body regions'
                                      : 'TBSA: ${burnPercentage.toStringAsFixed(2)}%',
                                ),
                                if (aiMaskCoverage != null)
                                  _MetricBadge(
                                    text:
                                        'AI-only detected area: ${aiMaskCoverage!.toStringAsFixed(2)}%',
                                  ),
                              ],
                            ),
                          ),
                          if (isDetecting)
                            const Positioned(
                              top: 88,
                              left: 12,
                              right: 12,
                              child: _AiStatusBanner(
                                text: 'AI is detecting burn regions...',
                                showProgress: true,
                              ),
                            ),
                          if (isDetecting)
                            const Positioned(
                              top: 12,
                              right: 12,
                              child: CircularProgressIndicator(),
                            ),
                          if (detectionError != null)
                            Positioned(
                              bottom: 12,
                              left: 12,
                              right: 12,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'AI detection unavailable. Start the Python backend and retry.',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _detectBurnRegion,
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (!isDetecting &&
                              detectionError == null &&
                              aiMaskImage != null)
                            const Positioned(
                              top: 88,
                              left: 12,
                              right: 12,
                              child: _AiStatusBanner(
                                text: 'AI regions detected',
                              ),
                            ),
                          if (weightKg != null && burnPercentage > 0)
                            Positioned(
                              top: 60,
                              left: 12,
                              child: _ParklandBadge(
                                totalFluidMl: _totalFluidMl,
                                firstEightHoursMl: _firstEightHoursMl,
                                nextSixteenHoursMl: _nextSixteenHoursMl,
                                isPediatric: _isPediatric,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  double get burnPercentage {
    if (selectedRegions.isNotEmpty) {
      return assessmentRegions
          .where((region) => selectedRegions.contains(region.name))
          .fold(0, (total, region) => total + region.percentage);
    }
    return 0;
  }

  bool get _isPediatric => ageYears != null && ageYears! < 14;

  double get _totalFluidMl => 4 * (weightKg ?? 0) * burnPercentage;

  double get _firstEightHoursMl => _totalFluidMl / 2;

  double get _nextSixteenHoursMl => _totalFluidMl / 2;

  Future<void> _showParklandCalculator() async {
    ageController.text = ageYears?.toString() ?? '';
    weightController.text = weightKg?.toString() ?? '';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final parsedAge = int.tryParse(ageController.text.trim());
            final parsedWeight = double.tryParse(
              weightController.text.trim().replaceAll(',', '.'),
            );
            final total = 4 * (parsedWeight ?? 0) * burnPercentage;

            return AlertDialog(
              title: const Text('Parkland calculation'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: ageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Age (years)',
                        suffixText: 'years',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    TextField(
                      controller: weightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Weight',
                        suffixText: 'kg',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_usesPediatricMethod ? 'Lund-Browder' : 'Rule of Nines'} regions',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final region in assessmentRegions)
                          FilterChip(
                            label: Text(
                              '${region.name} ${region.percentage.toStringAsFixed(0)}%',
                            ),
                            selected: selectedRegions.contains(region.name),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  selectedRegions.add(region.name);
                                } else {
                                  selectedRegions.remove(region.name);
                                }
                              });
                              setDialogState(() {});
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Estimated TBSA: ${burnPercentage.toStringAsFixed(2)}%',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Total 24-hour fluid: ${total.toStringAsFixed(0)} mL',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('First 8 hours: ${(total / 2).toStringAsFixed(0)} mL'),
                    Text('Next 16 hours: ${(total / 2).toStringAsFixed(0)} mL'),
                    if (parsedAge != null && parsedAge < 14) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Pediatric maintenance: '
                        '${_maintenanceRateFor(parsedWeight ?? 0).toStringAsFixed(0)} mL/hr',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      _usesPediatricMethod
                          ? 'Pediatric TBSA uses a simplified age-adjusted '
                                'Lund-Browder grouping. Confirm against the full '
                                'Lund-Browder chart and local burn protocol.'
                          : 'Rule of Nines is for adults. Follow local burn '
                                'protocols and confirm the selected regions.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: parsedAge != null && parsedWeight != null
                      ? () {
                          setState(() {
                            ageYears = parsedAge;
                            weightKg = parsedWeight;
                          });
                          Navigator.pop(context);
                        }
                      : null,
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool get _usesPediatricMethod => ageYears != null && ageYears! < 15;

  List<RuleOfNinesRegion> get assessmentRegions => _usesPediatricMethod
      ? _pediatricRegionsFor(ageYears!)
      : ruleOfNinesRegions;

  List<RuleOfNinesRegion> _pediatricRegionsFor(int age) {
    final ageBand = age <= 0
        ? 0
        : age <= 2
        ? 1
        : age <= 7
        ? 5
        : age <= 12
        ? 10
        : 15;
    const headAndNeck = {0: 21.0, 1: 19.0, 5: 15.0, 10: 13.0, 15: 11.0};
    final head = headAndNeck[ageBand]!;
    final leg = (45 - head) / 2;
    return [
      RuleOfNinesRegion(name: 'Head and neck', percentage: head),
      const RuleOfNinesRegion(name: 'Left arm', percentage: 9),
      const RuleOfNinesRegion(name: 'Right arm', percentage: 9),
      const RuleOfNinesRegion(name: 'Anterior trunk', percentage: 18),
      const RuleOfNinesRegion(name: 'Posterior trunk', percentage: 18),
      RuleOfNinesRegion(name: 'Left leg', percentage: leg),
      RuleOfNinesRegion(name: 'Right leg', percentage: leg),
      const RuleOfNinesRegion(name: 'Perineum', percentage: 1),
    ];
  }

  double _maintenanceRateFor(double weight) {
    if (weight <= 10) return weight * 4;
    if (weight <= 20) return 40 + (weight - 10) * 2;
    return 60 + (weight - 20);
  }
}

const ruleOfNinesRegions = [
  RuleOfNinesRegion(name: 'Head and neck', percentage: 9),
  RuleOfNinesRegion(name: 'Left arm', percentage: 9),
  RuleOfNinesRegion(name: 'Right arm', percentage: 9),
  RuleOfNinesRegion(name: 'Anterior trunk', percentage: 18),
  RuleOfNinesRegion(name: 'Posterior trunk', percentage: 18),
  RuleOfNinesRegion(name: 'Left leg', percentage: 18),
  RuleOfNinesRegion(name: 'Right leg', percentage: 18),
  RuleOfNinesRegion(name: 'Perineum', percentage: 1),
];

class RuleOfNinesRegion {
  final String name;
  final double percentage;

  const RuleOfNinesRegion({required this.name, required this.percentage});
}

class _ParklandBadge extends StatelessWidget {
  final double totalFluidMl;
  final double firstEightHoursMl;
  final double nextSixteenHoursMl;
  final bool isPediatric;

  const _ParklandBadge({
    required this.totalFluidMl,
    required this.firstEightHoursMl,
    required this.nextSixteenHoursMl,
    required this.isPediatric,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          'Parkland: ${totalFluidMl.toStringAsFixed(0)} mL\n'
          '8h: ${firstEightHoursMl.toStringAsFixed(0)} mL | '
          '16h: ${nextSixteenHoursMl.toStringAsFixed(0)} mL'
          '${isPediatric ? '\nPediatric: use Lund-Browder' : ''}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  final String text;

  const _MetricBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AiStatusBanner extends StatelessWidget {
  final String text;
  final bool showProgress;

  const _AiStatusBanner({required this.text, this.showProgress = false});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProgress) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
            ] else ...[
              const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaskLegend extends StatelessWidget {
  const _MaskLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: const [
        _LegendItem(color: Colors.red, label: 'AI detected'),
        _LegendItem(color: Colors.blue, label: 'Manual added'),
        _LegendItem(color: Colors.amber, label: 'Privacy covered'),
        _LegendItem(color: Colors.white, label: 'Eraser'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.blueGrey.shade300),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class MaskStroke {
  final bool isEraser;
  final bool isPrivacy;
  final List<Offset> points;

  MaskStroke({
    required this.isEraser,
    required this.isPrivacy,
    required this.points,
  });
}

class MaskPainter extends CustomPainter {
  final ui.Image? aiMaskImage;
  final List<MaskStroke> strokes;
  final double aiOpacity;
  final double brushSize;

  MaskPainter({
    required this.aiMaskImage,
    required this.strokes,
    this.aiOpacity = 0.45,
    this.brushSize = 20,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());

    if (aiMaskImage != null) {
      canvas.drawImageRect(
        aiMaskImage!,
        Rect.fromLTWH(
          0,
          0,
          aiMaskImage!.width.toDouble(),
          aiMaskImage!.height.toDouble(),
        ),
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: aiOpacity),
      );
    }

    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      final paint = Paint()
        ..color = stroke.isPrivacy
            ? Colors.amber.withValues(alpha: 0.85)
            : stroke.isEraser
            ? Colors.transparent
            : Colors.blue.withValues(alpha: 0.55)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = brushSize
        ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;

      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, paint.strokeWidth / 2, paint);
      } else {
        for (var i = 0; i < stroke.points.length - 1; i++) {
          canvas.drawLine(stroke.points[i], stroke.points[i + 1], paint);
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
