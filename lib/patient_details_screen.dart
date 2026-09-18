import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import 'camera_screen.dart';

class PatientRecord {
  final String name;
  final int age;
  final double weightKg;
  final String gender;
  final String? notes;
  final String? patientId;
  final String? injuryCause;
  final DateTime? injuryDateTime;

  const PatientRecord({
    required this.name,
    required this.age,
    required this.weightKg,
    required this.gender,
    this.notes,
    this.patientId,
    this.injuryCause,
    this.injuryDateTime,
  });

  const PatientRecord.empty()
    : name = 'Patient not specified',
      age = 0,
      weightKg = 0,
      gender = 'Not specified',
      notes = null,
      patientId = null,
      injuryCause = null,
      injuryDateTime = null;
}

class PatientDetailsScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const PatientDetailsScreen({required this.cameras, super.key});

  @override
  State<PatientDetailsScreen> createState() => _PatientDetailsScreenState();
}

class _PatientDetailsScreenState extends State<PatientDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();
  final _patientIdController = TextEditingController();
  final _causeController = TextEditingController();
  String _gender = 'Not specified';
  DateTime? _injuryDateTime;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _notesController.dispose();
    _patientIdController.dispose();
    _causeController.dispose();
    super.dispose();
  }

  void _continue() {
    final age = int.tryParse(_ageController.text.trim()) ?? 0;
    final weight =
        double.tryParse(_weightController.text.trim().replaceAll(',', '.')) ??
        0;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          cameras: widget.cameras,
          patient: PatientRecord(
            name: _nameController.text.trim().isEmpty
                ? 'Patient not specified'
                : _nameController.text.trim(),
            age: age,
            weightKg: weight,
            gender: _gender,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            patientId: _patientIdController.text.trim().isEmpty
                ? null
                : _patientIdController.text.trim(),
            injuryCause: _causeController.text.trim().isEmpty
                ? null
                : _causeController.text.trim(),
            injuryDateTime: _injuryDateTime,
          ),
        ),
      ),
    );
  }

  void _skip() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          cameras: widget.cameras,
          patient: const PatientRecord.empty(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patient details')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Assessment profile',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'These details support TBSA and fluid calculations. Confirm them before capturing the wound image.',
              style: TextStyle(color: Colors.blueGrey.shade600),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Patient name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _patientIdController,
              decoration: const InputDecoration(
                labelText: 'Patient ID (optional)',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Age',
                      suffixText: 'years',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _weightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Weight',
                      suffixText: 'kg',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(
                labelText: 'Gender',
                prefixIcon: Icon(Icons.wc_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'Not specified',
                  child: Text('Not specified'),
                ),
                DropdownMenuItem(value: 'Female', child: Text('Female')),
                DropdownMenuItem(value: 'Male', child: Text('Male')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (value) =>
                  setState(() => _gender = value ?? 'Not specified'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _causeController,
              decoration: const InputDecoration(
                labelText: 'Injury cause (optional)',
                hintText: 'For example, scald, flame, chemical',
                prefixIcon: Icon(Icons.local_fire_department_outlined),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('Injury date and time'),
              subtitle: Text(
                _injuryDateTime == null
                    ? 'Not specified'
                    : MaterialLocalizations.of(context)
                          .formatFullDate(_injuryDateTime!),
              ),
              trailing: IconButton(
                tooltip: 'Choose injury date and time',
                icon: const Icon(Icons.edit_calendar_outlined),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    initialDate: _injuryDateTime ?? DateTime.now(),
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(
                      _injuryDateTime ?? DateTime.now(),
                    ),
                  );
                  if (time == null || !mounted) return;
                  setState(() {
                    _injuryDateTime = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Other notes (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _continue,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue to image capture'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _skip,
              child: const Text('Skip patient details for now'),
            ),
          ],
        ),
      ),
    );
  }
}
