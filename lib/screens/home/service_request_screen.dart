import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../core/constants/service_categories.dart';
import '../../providers/ai_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/job_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';

class ServiceRequestScreen extends ConsumerStatefulWidget {
  final String? initialCategory;

  const ServiceRequestScreen({super.key, this.initialCategory});

  @override
  ConsumerState<ServiceRequestScreen> createState() =>
      _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends ConsumerState<ServiceRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _budgetMinController = TextEditingController();
  final _budgetMaxController = TextEditingController();
  final _picker = ImagePicker();

  final List<Uint8List> _images = [];
  String? _selectedCategory;
  double? _lat;
  double? _lng;
  bool _fetchingLocation = false;
  String _urgency = 'asap';
  DateTime? _scheduledDate;

  bool _analyzing = false;
  JobAiSuggestion? _aiSuggestion;
  bool _aiAccepted = false;

  static const int _maxImages = 5;

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null &&
        ServiceCategories.all.contains(widget.initialCategory)) {
      _selectedCategory = widget.initialCategory;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _addressController.dispose();
    _budgetMinController.dispose();
    _budgetMaxController.dispose();
    super.dispose();
  }

  Future<void> _selectImages() async {
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) {
      showErrorSnackbar(context, 'Maximum of $_maxImages images allowed.');
      return;
    }
    try {
      final picked =
          await _picker.pickMultiImage(imageQuality: 70, limit: remaining);
      if (picked.isEmpty) return;

      final bytesList = await Future.wait(
        picked.map((image) async {
          final bytes = await image.readAsBytes();
          if (bytes.lengthInBytes <= 500 * 1024) return bytes;
          return FlutterImageCompress.compressWithList(
            bytes,
            quality: 70,
            format: CompressFormat.jpeg,
          );
        }),
      );

      if (mounted) setState(() => _images.addAll(bytesList));
    } catch (e) {
      if (mounted) {
        showErrorSnackbar(context, 'Could not load the selected photos. Please try again.');
      }
    }
  }

  void _removeImage(int index) => setState(() => _images.removeAt(index));

  Future<void> _analyzeWithAi() async {
    final description = _descriptionController.text.trim();
    if (description.length < 10) {
      showErrorSnackbar(
          context, 'Write a few more words about the job first.');
      return;
    }

    setState(() {
      _analyzing = true;
      _aiSuggestion = null;
      _aiAccepted = false;
    });

    try {
      final suggestion = await ref.read(aiServiceProvider).analyzeJob(
            description: description,
            imagesBase64: _images.take(3).map(base64Encode).toList(),
          );
      if (mounted) setState(() => _aiSuggestion = suggestion);
    } catch (e) {
      // AiService.analyzeJob throws AiServiceException with an
      // already-friendly message — show it directly.
      if (mounted) {
        showErrorSnackbar(context, '$e');
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _acceptAiSuggestion() {
    final suggestion = _aiSuggestion;
    if (suggestion == null) return;
    setState(() {
      if (ServiceCategories.all.contains(suggestion.suggestedCategory)) {
        _selectedCategory = suggestion.suggestedCategory;
      }
      _descriptionController.text = suggestion.enhancedDescription;
      _aiAccepted = true;
    });
  }

  void _dismissAiSuggestion() => setState(() {
        _aiSuggestion = null;
        _aiAccepted = false;
      });

  Future<void> _fetchLocation() async {
    setState(() => _fetchingLocation = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          showErrorSnackbar(
              context, 'Location permission denied. Enter address manually.');
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [p.subLocality, p.locality, p.administrativeArea]
            .where((s) => s != null && s!.isNotEmpty)
            .toList();
        setState(() {
          _lat = position.latitude;
          _lng = position.longitude;
          _addressController.text = parts.join(', ');
        });
      }
    } catch (_) {
      if (mounted) {
        showErrorSnackbar(
            context, 'Could not get location. Enter address manually.');
      }
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  Future<void> _pickScheduledDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      helpText: 'Select the date you need this done',
    );
    if (picked != null) setState(() => _scheduledDate = picked);
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    if (_images.isEmpty) {
      showErrorSnackbar(
          context, 'Please attach at least one photo of the work needed.');
      return;
    }

    if (_urgency == 'scheduled' && _scheduledDate == null) {
      showErrorSnackbar(context, 'Please select the date you need this done.');
      return;
    }

    final profile = ref.read(currentUserProvider).asData?.value;
    if (profile == null) {
      showErrorSnackbar(context, 'Unable to submit: user profile not found.');
      return;
    }

    final budgetMin = _budgetMinController.text.trim().isEmpty
        ? null
        : double.tryParse(_budgetMinController.text.trim());
    final budgetMax = _budgetMaxController.text.trim().isEmpty
        ? null
        : double.tryParse(_budgetMaxController.text.trim());

    await ref.read(jobRequestNotifierProvider.notifier).submitRequest(
          customerId: profile.uid,
          category: _selectedCategory!,
          description: _descriptionController.text.trim(),
          images: _images,
          customerLat: _lat,
          customerLng: _lng,
          customerAddress: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          budgetMin: budgetMin,
          budgetMax: budgetMax,
          urgency: _urgency,
          scheduledDate: _scheduledDate,
          aiSuggestion: _aiAccepted ? _aiSuggestion?.toJson() : null,
        );

    final state = ref.read(jobRequestNotifierProvider);
    if (state.error != null) {
      if (!mounted) return;
      // Network/Firestore failures are usually transient — offer a one-tap
      // retry instead of leaving the customer to re-fill the whole form.
      showErrorSnackbar(
        context,
        "Couldn't post your job: ${state.error}",
        onRetry: _submitRequest,
      );
      return;
    }

    if (state.success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state.failedImageCount > 0
                ? 'Job posted! ${state.failedImageCount} photo'
                    '${state.failedImageCount == 1 ? '' : 's'} failed to upload '
                    'but your request was still submitted.'
                : 'Job posted! Choose an artisan.',
          ),
        ),
      );
      context.push(
        '/artisans/${state.createdJobId}',
        extra: {
          'category': _selectedCategory,
          'lat': _lat,
          'lng': _lng,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobState = ref.watch(jobRequestNotifierProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        title: const Text(
          'Post a Job',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _SectionLabel('What service do you need?'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: InputDecoration(
                  hintText: 'Select a category',
                  prefixIcon: const Icon(Icons.handyman_outlined),
                  filled: true,
                  fillColor: context.colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.colors.border),
                  ),
                ),
                items: ServiceCategories.all
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
                validator: (v) =>
                    v == null ? 'Please select a service category' : null,
              ),
              const SizedBox(height: 24),

              _SectionLabel('Describe the work needed'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText:
                      'Describe the problem, size of the job, and any relevant details…',
                  hintStyle: TextStyle(
                      fontSize: 13, color: context.colors.textTertiary),
                  filled: true,
                  fillColor: context.colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.colors.border),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 20) {
                    return 'Please describe the job (at least 20 characters)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _analyzing ? null : _analyzeWithAi,
                icon: _analyzing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(_analyzing ? 'Analyzing…' : 'Analyze with AI'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.colors.primary),
                  foregroundColor: context.colors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              if (_aiSuggestion != null) ...[
                const SizedBox(height: 12),
                _AiSuggestionCard(
                  suggestion: _aiSuggestion!,
                  accepted: _aiAccepted,
                  onAccept: _acceptAiSuggestion,
                  onDismiss: _dismissAiSuggestion,
                ),
              ],
              const SizedBox(height: 24),

              Row(
                children: [
                  const _SectionLabel('Photos'),
                  const SizedBox(width: 8),
                  Text(
                    '${_images.length}/$_maxImages',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textTertiary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_images.isNotEmpty) ...[
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, i) => const SizedBox(width: 10),
                    itemBuilder: (ctx, i) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            _images[i],
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImage(i),
                            child: Container(
                              decoration: BoxDecoration(
                                color: context.colors.error,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(3),
                              child: const Icon(Icons.close,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (_images.length < _maxImages)
                OutlinedButton.icon(
                  onPressed: _selectImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_images.isEmpty
                      ? 'Add Photos (required)'
                      : 'Add More Photos'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.colors.primary),
                    foregroundColor: context.colors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              const SizedBox(height: 24),

              _SectionLabel('Location'),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _addressController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Victoria Island, Lagos',
                        prefixIcon: Icon(
                          _lat != null
                              ? Icons.location_on
                              : Icons.location_on_outlined,
                          color: _lat != null ? context.colors.accent : null,
                        ),
                        filled: true,
                        fillColor: context.colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                      ),
                      onChanged: (_) {
                        if (_lat != null) {
                          setState(() {
                            _lat = null;
                            _lng = null;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    tooltip: 'Use my current location',
                    onPressed: _fetchingLocation ? null : _fetchLocation,
                    icon: _fetchingLocation
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.my_location),
                    style: IconButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              _SectionLabel('Budget (optional)'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _budgetMinController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: InputDecoration(
                        labelText: 'Min (₦)',
                        prefixIcon: const Icon(Icons.payments_outlined),
                        filled: true,
                        fillColor: context.colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        final min = double.tryParse(v);
                        if (min == null || min <= 0) {
                          return 'Enter a valid amount';
                        }
                        final max =
                            double.tryParse(_budgetMaxController.text.trim());
                        if (max != null && min > max) {
                          return 'Must be ≤ max';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _budgetMaxController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: InputDecoration(
                        labelText: 'Max (₦)',
                        filled: true,
                        fillColor: context.colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        final max = double.tryParse(v);
                        if (max == null || max <= 0) {
                          return 'Enter a valid amount';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              _SectionLabel('When do you need this done?'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _UrgencyTile(
                      label: 'As Soon As Possible',
                      icon: Icons.bolt_rounded,
                      selected: _urgency == 'asap',
                      onTap: () => setState(() {
                        _urgency = 'asap';
                        _scheduledDate = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _UrgencyTile(
                      label: 'Specific Date',
                      icon: Icons.calendar_month_outlined,
                      selected: _urgency == 'scheduled',
                      onTap: () async {
                        setState(() => _urgency = 'scheduled');
                        await _pickScheduledDate();
                      },
                    ),
                  ),
                ],
              ),
              if (_urgency == 'scheduled' && _scheduledDate != null) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _pickScheduledDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: context.colors.accentSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: context.colors.accent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event_available,
                            color: context.colors.accent, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          DateFormat('EEEE, d MMMM yyyy')
                              .format(_scheduledDate!),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.colors.accent,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.edit_outlined,
                            size: 16, color: context.colors.accent),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: jobState.isSubmitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: jobState.isSubmitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Post Job & Find Artisans',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter',
                        ),
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiSuggestionCard extends StatelessWidget {
  final JobAiSuggestion suggestion;
  final bool accepted;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const _AiSuggestionCard({
    required this.suggestion,
    required this.accepted,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.primary.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_outlined,
                    size: 16, color: context.colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'AI-generated suggestion. Review before accepting.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.colors.primary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
                Text(
                  '${(suggestion.confidence * 100).round()}% confident',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Category: ${suggestion.suggestedCategory}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontFamily: 'Inter')),
            const SizedBox(height: 6),
            Text(
              suggestion.enhancedDescription,
              style: TextStyle(
                  fontSize: 13, color: context.colors.textSecondary, fontFamily: 'Inter'),
            ),
            const SizedBox(height: 12),
            if (accepted)
              Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: context.colors.accent),
                  SizedBox(width: 6),
                  Text('Applied to your post',
                      style: TextStyle(
                          fontSize: 12,
                          color: context.colors.accent,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter')),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDismiss,
                      child: const Text('Keep my version'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onAccept,
                      child: const Text('Use this'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
          fontFamily: 'Inter',
        ),
      );
}

class _UrgencyTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _UrgencyTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color:
                selected ? context.colors.primarySurface : context.colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? context.colors.primary : context.colors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected
                    ? context.colors.primary
                    : context.colors.textSecondary,
                size: 24,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? context.colors.primary
                      : context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      );
}
