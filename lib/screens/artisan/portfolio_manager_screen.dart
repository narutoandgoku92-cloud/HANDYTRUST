import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/portfolio_service.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';
import '../../widgets/portfolio_viewer.dart';

class PortfolioManagerScreen extends ConsumerStatefulWidget {
  const PortfolioManagerScreen({super.key});

  @override
  ConsumerState<PortfolioManagerScreen> createState() =>
      _PortfolioManagerScreenState();
}

class _PortfolioManagerScreenState
    extends ConsumerState<PortfolioManagerScreen> {
  final _picker = ImagePicker();
  bool _busy = false;

  Future<Uint8List> _compress(Uint8List bytes) async {
    if (bytes.lengthInBytes <= 800 * 1024) return bytes;
    return FlutterImageCompress.compressWithList(
      bytes,
      quality: 75,
      format: CompressFormat.jpeg,
    );
  }

  Future<void> _addPhoto(String artisanId) async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _compress(await picked.readAsBytes());
      await ref
          .read(portfolioServiceProvider)
          .addImage(artisanId: artisanId, bytes: bytes);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(String artisanId, String url) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(portfolioServiceProvider)
          .removeImage(artisanId: artisanId, url: url);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reorder(
    String artisanId,
    List<String> urls,
    int oldIndex,
    int newIndex,
  ) async {
    final updated = List<String>.from(urls);
    if (newIndex > oldIndex) newIndex -= 1;
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    try {
      await ref
          .read(portfolioServiceProvider)
          .reorder(artisanId: artisanId, orderedUrls: updated);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).asData?.value;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final artisanAsync = ref.watch(artisanProfileProvider(user.uid));
    final viewCountAsync = ref.watch(portfolioViewCountProvider(user.uid));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Manage Portfolio')),
      body: artisanAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (artisan) {
          if (artisan == null) return const SizedBox();
          final urls = artisan.portfolioImageUrls;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    Icon(Icons.visibility_outlined,
                        size: 18, color: context.colors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      '${viewCountAsync.asData?.value ?? 0} profile views',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${urls.length}/${PortfolioService.maxImages}',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textTertiary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: urls.isEmpty
                    ? Center(
                        child: Text(
                          'No portfolio photos yet',
                          style: TextStyle(
                            color: context.colors.textTertiary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        itemCount: urls.length,
                        onReorder: (oldIndex, newIndex) =>
                            _reorder(artisan.uid, urls, oldIndex, newIndex),
                        itemBuilder: (ctx, i) => Container(
                          key: ValueKey(urls[i]),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: context.colors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.colors.borderLight),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => showPortfolioViewer(
                                  context,
                                  imageUrls: urls,
                                  initialIndex: i,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    urls[i],
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Photo ${i + 1}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.colors.textPrimary,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: context.colors.error),
                                onPressed: _busy
                                    ? null
                                    : () => _removePhoto(artisan.uid, urls[i]),
                              ),
                              Icon(Icons.drag_handle,
                                  color: context.colors.textTertiary),
                            ],
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy || urls.length >= PortfolioService.maxImages
                        ? null
                        : () => _addPhoto(artisan.uid),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined,
                            size: 18),
                    label: Text(urls.length >= PortfolioService.maxImages
                        ? 'Limit reached'
                        : 'Add Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      foregroundColor: context.colors.textInverse,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
