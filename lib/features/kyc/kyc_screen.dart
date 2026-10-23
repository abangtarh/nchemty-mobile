import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../data/middleware/hub_api.dart';

/// Front end for the existing 7-stage KYC pipeline. The app only captures
/// images; liveness, authenticity, OCR, face match and the compliance
/// result all run server-side.
class KycScreen extends ConsumerStatefulWidget {
  const KycScreen({super.key});
  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

enum _Step { selfie, document, review }

class _KycScreenState extends ConsumerState<KycScreen> {
  final _picker = ImagePicker();
  String? _sessionId;
  _Step _step = _Step.selfie;
  String _docType = 'CNI';
  bool _busy = false;
  String? _message;

  Future<void> _capture() async {
    final isSelfie = _step == _Step.selfie;
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: isSelfie ? CameraDevice.front : CameraDevice.rear,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (shot == null) return;
    final file = File(shot.path);
    if (!mounted) {
      // Never keep identity images on the phone.
      if (await file.exists()) await file.delete();
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final hub = ref.read(hubApiProvider);
    try {
      _sessionId ??= await hub.startKyc();
      final result = await hub.uploadKycImage(
        sessionId: _sessionId!,
        stage: isSelfie ? 'selfie' : 'document_front',
        documentType: isSelfie ? null : _docType,
        image: file,
      );
      if (mounted) {
        setState(() {
          _message = result['message']?.toString();
          _step = isSelfie ? _Step.document : _Step.review;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      // Never keep identity images on the phone.
      if (await file.exists()) await file.delete();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkStatus() async {
    final id = _sessionId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final status = await ref.read(hubApiProvider).kycStatus(id);
      if (mounted) {
        setState(() => _message =
            'Status: ${status['status'] ?? 'in review'}. ${status['message'] ?? ''}');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(ref);
    final (title, body) = switch (_step) {
      _Step.selfie => ('Take a selfie', 'Face the camera in good light. Remove glasses and hats.'),
      _Step.document => ('Photograph your ID', 'Front of your document, all four corners visible, no glare.'),
      _Step.review => ('Thanks, we are checking', 'Most checks finish in a few minutes. You can leave this screen.'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(s.t('verifyId'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            LinearProgressIndicator(
              value: (_step.index + 1) / _Step.values.length,
              color: AppColors.green,
              backgroundColor: AppColors.line,
            ),
            const SizedBox(height: 24),
            Text(title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(color: AppColors.muted, height: 1.5)),
            if (_step == _Step.document) ...[
              const SizedBox(height: 20),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'CNI', label: Text('CNI')),
                  ButtonSegment(value: 'PASSPORT', label: Text('Passport')),
                  ButtonSegment(value: 'DRIVING_LICENCE', label: Text('Licence')),
                ],
                selected: {_docType},
                onSelectionChanged: (v) => setState(() => _docType = v.first),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!),
            ],
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : (_step == _Step.review ? _checkStatus : _capture),
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : Icon(_step == _Step.review
                      ? Icons.refresh
                      : Icons.photo_camera_outlined),
              label: Text(_step == _Step.review ? 'Check status' : 'Take photo'),
            ),
          ],
        ),
      ),
    );
  }
}
