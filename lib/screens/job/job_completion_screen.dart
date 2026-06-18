import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../core/services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../theme/app_theme.dart';

class JobCompletionScreen extends ConsumerStatefulWidget {
  final String jobId;

  const JobCompletionScreen({super.key, required this.jobId});

  @override
  ConsumerState<JobCompletionScreen> createState() =>
      _JobCompletionScreenState();
}

class _JobCompletionScreenState extends ConsumerState<JobCompletionScreen> {
  final List<Uint8List> _images = [];
  final _notesController = TextEditingController();
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Submit Completion')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoCard(),
            const SizedBox(height: 24),
            const Text('Completion Photos *',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                )),
            const SizedBox(height: 4),
            Text(
              'Upload at least 1 photo of the completed work.',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 12),
            _imageGrid(),
            const SizedBox(height: 24),
            const Text('Notes (optional)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                )),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Describe what was done…',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(
                      color: context.colors.error, fontFamily: 'Inter')),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _uploading ? null : _submit,
              child: _uploading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit for Review'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: 18, color: context.colors.primary),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Once submitted, the customer has 7 days to confirm completion or raise a dispute. Funds release automatically after the 7-day window.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.primary,
                  fontFamily: 'Inter',
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _imageGrid() => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _images.length + 1,
        itemBuilder: (ctx, i) {
          if (i == _images.length) {
            return GestureDetector(
              onTap: _pickImage,
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: context.colors.border, style: BorderStyle.solid),
                ),
                child: Center(
                  child: Icon(Icons.add_photo_alternate_outlined,
                      color: context.colors.textTertiary, size: 28),
                ),
              ),
            );
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_images[i], fit: BoxFit.cover),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => setState(() => _images.removeAt(i)),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: context.colors.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      );

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final raw = await picked.readAsBytes();
    Uint8List bytes = raw;
    if (raw.lengthInBytes > 500 * 1024) {
      final compressed =
          await FlutterImageCompress.compressWithList(raw, quality: 70);
      bytes = Uint8List.fromList(compressed);
    }
    setState(() => _images.add(bytes));
  }

  Future<void> _submit() async {
    if (_images.isEmpty) {
      setState(() => _error = 'Please add at least one completion photo.');
      return;
    }
    final userId = ref.read(authStateChangesProvider).value?.uid ?? '';
    if (userId.isEmpty) {
      setState(() => _error = 'Not signed in.');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final storage = StorageService();
      final urls = <String>[];
      for (int i = 0; i < _images.length; i++) {
        final url = await storage.uploadJobImageBytes(
          jobId: widget.jobId,
          userId: userId,
          index: i,
          bytes: _images[i],
        );
        urls.add(url);
      }

      await ref.read(escrowNotifierProvider.notifier).submitCompletion(
            widget.jobId,
            imageUrls: urls,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      if (mounted) context.go('/job/${widget.jobId}');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
}
