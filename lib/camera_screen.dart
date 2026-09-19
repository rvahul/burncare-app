import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'mask_editor_screen.dart';
import 'patient_details_screen.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final PatientRecord patient;

  const CameraScreen({required this.cameras, required this.patient, super.key});

  @override
  State<CameraScreen> createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.cameras.isNotEmpty) {
      _controller = CameraController(widget.cameras[0], ResolutionPreset.high);
      _initializeControllerFuture = _controller!.initialize();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || _initializeControllerFuture == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add wound image')),
        body: Center(
          child: FilledButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload image'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture Burn Wound'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library),
            tooltip: 'Choose image from device',
            onPressed: _pickImage,
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return CameraPreview(_controller!);
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.camera),
        onPressed: () async {
          if (_controller == null) return;

          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);

          try {
            await _initializeControllerFuture;
            final image = await _controller!.takePicture();

            if (!mounted) return;

            await navigator.push(
              MaterialPageRoute(
                builder: (context) => MaskEditScreen(
                  imageFile: image,
                  patient: widget.patient,
                ),
              ),
            );
          } catch (error) {
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text('Unable to capture image: $error')),
            );
          }
        },
      ),
    );
  }

  Future<void> _pickImage() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;

      await navigator.push(
        MaterialPageRoute(
          builder: (context) => MaskEditScreen(
            imageFile: image,
            patient: widget.patient,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to choose image: $error')),
      );
    }
  }
}
