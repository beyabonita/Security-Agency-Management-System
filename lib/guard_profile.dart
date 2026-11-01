import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_application_1/models/contract_period.dart';
import 'package:flutter_application_1/services/profile_photo_codec.dart';
import 'package:flutter_application_1/services/user_profile_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';

/// Shared circular avatar widget for the Guard mobile app.
/// Renders [photoUrl] when present and valid; falls back to deterministic
/// colored initials when missing or if image loading fails.
class GuardAvatarCircle extends StatelessWidget {
  const GuardAvatarCircle({
    super.key,
    required this.photoUrl,
    required this.initials,
    required this.seed,
    this.size = 52,
    this.ringColor,
    this.ringWidth = 2.0,
  });

  final String? photoUrl;
  final String initials;
  final String seed;
  final double size;
  final Color? ringColor;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = photoUrl?.trim() ?? '';
    final bgColor = Color(UserProfileService.avatarColorValueFor(seed));
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );

    Widget content = fallback;
    if (trimmedUrl.isNotEmpty) {
      content = ClipOval(
        child: Image.network(
          trimmedUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      );
    }

    if (ringColor == null) return content;

    return Container(
      width: size + ringWidth * 2,
      height: size + ringWidth * 2,
      padding: EdgeInsets.all(ringWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor!, width: ringWidth),
      ),
      child: content,
    );
  }
}

class GuardProfileScreen extends StatefulWidget {
  const GuardProfileScreen({super.key});

  @override
  State<GuardProfileScreen> createState() => _GuardProfileScreenState();
}

class _GuardProfileScreenState extends State<GuardProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mobileCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _emergencyCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  Map<String, dynamic>? _details;
  bool _loading = true;
  bool _savingInfo = false;
  bool _uploadingPhoto = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void dispose() {
    _mobileCtrl.dispose();
    _addressCtrl.dispose();
    _emergencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await UserProfileService.getOwnGuardProfileDetails();
      if (!mounted) return;
      _mobileCtrl.text = data['mobile_number']?.toString() ?? '';
      _addressCtrl.text = data['complete_address']?.toString() ?? '';
      _emergencyCtrl.text = data['emergency_contact']?.toString() ?? '';
      setState(() {
        _details = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String _cleanError(Object error) =>
      error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
      if (picked == null || !mounted) return;

      final lowerName = picked.name.toLowerCase();
      if (lowerName.isNotEmpty &&
          !lowerName.endsWith('.jpg') &&
          !lowerName.endsWith('.jpeg') &&
          !lowerName.endsWith('.png')) {
        _showSnack(
          'Only JPG and PNG images are allowed.',
          isError: true,
        );
        return;
      }

      final rawBytes = await picked.readAsBytes();
      final dims = ProfilePhotoCodec.validateSource(rawBytes);
      if (!mounted) return;

      final croppedJpeg = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CircularPhotoCropDialog(
          sourceBytes: rawBytes,
          imageWidth: dims.width,
          imageHeight: dims.height,
        ),
      );

      if (croppedJpeg == null || !mounted) return;

      setState(() => _uploadingPhoto = true);
      final newUrl = await UserProfileService.uploadOwnProfilePhoto(
        croppedJpeg,
      );
      if (!mounted) return;
      setState(() {
        _details = <String, dynamic>{...?_details, 'profile_photo_url': newUrl};
        _uploadingPhoto = false;
      });
      _showSnack(
        'Profile photo updated and synced to Operations Console.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingPhoto = false);
      _showSnack(_cleanError(error), isError: true);
    }
  }

  Future<void> _confirmRemovePhoto() async {
    final currentUrl = _details?['profile_photo_url']?.toString().trim() ?? '';
    if (currentUrl.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove profile photo?'),
        content: const Text(
          'Your profile will display your initials on a colored background across the mobile app and Operations Head Console.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.of(dialogContext).error,
            ),
            child: const Text('Remove Photo'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _uploadingPhoto = true);
    try {
      await UserProfileService.removeOwnProfilePhoto();
      if (!mounted) return;
      setState(() {
        _details = <String, dynamic>{...?_details, 'profile_photo_url': null};
        _uploadingPhoto = false;
      });
      _showSnack('Profile photo removed.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingPhoto = false);
      _showSnack(_cleanError(error), isError: true);
    }
  }

  Future<void> _savePersonalDetails() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _savingInfo = true);
    try {
      final updated = await UserProfileService.updateOwnGuardProfile(
        mobileNumber: _mobileCtrl.text,
        completeAddress: _addressCtrl.text,
        emergencyContact: _emergencyCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _details = <String, dynamic>{
          ...?_details,
          'mobile_number': updated['mobile_number'] ?? _mobileCtrl.text.trim(),
          'complete_address':
              updated['complete_address'] ?? _addressCtrl.text.trim(),
          'emergency_contact':
              updated['emergency_contact'] ?? _emergencyCtrl.text.trim(),
        };
        _mobileCtrl.text = _details?['mobile_number']?.toString() ?? '';
        _addressCtrl.text = _details?['complete_address']?.toString() ?? '';
        _emergencyCtrl.text = _details?['emergency_contact']?.toString() ?? '';
        _savingInfo = false;
      });
      _showSnack(
        'Profile saved and synced to Personnel Record & Live Guard Map.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingInfo = false);
      _showSnack(_cleanError(error), isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    final palette = AppColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? palette.error : AppColors.snackBar,
      ),
    );
  }

  String _fullLegalName(Map<String, dynamic> d) {
    final first = d['first_name']?.toString().trim() ?? '';
    final middle = d['middle_name']?.toString().trim() ?? '';
    final mi = d['middle_initial']?.toString().trim() ?? '';
    final last = d['last_name']?.toString().trim() ?? '';
    final midDisplay = middle.isNotEmpty
        ? middle
        : (mi.isNotEmpty ? '$mi.' : '');
    final joined = [first, midDisplay, last]
        .where((part) => part.isNotEmpty)
        .join(' ');
    return joined.isEmpty ? 'Security Guard' : joined;
  }

  String _formatDate(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return 'Not set';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final d = _details ?? const <String, dynamic>{};
    final fullName = _fullLegalName(d);
    final initials = UserProfileService.initialsFor(
      d,
      fallbackName: fullName,
    );
    final seed =
        d['id']?.toString() ?? d['email']?.toString() ?? fullName;
    final photoUrl = d['profile_photo_url']?.toString();
    final hasPhoto = (photoUrl?.trim().isNotEmpty ?? false);
    final category =
        (d['employment_category']?.toString().toLowerCase() ?? 'regular') ==
                'contract'
            ? 'Contract Guard'
            : 'Regular Guard';
    final contract = ContractPeriod.fromProfile(d);
    final contractDates =
        (d['contract_start_date'] != null || d['contract_end_date'] != null)
            ? '${_formatDate(d['contract_start_date'])} – ${_formatDate(d['contract_end_date'])}'
            : (category == 'Regular Guard'
                ? 'Regular / Non-expiring'
                : 'Not set');

    return Scaffold(
      body: GuardAmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: palette.surfaceMuted,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Profile',
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Photo & personal contact details',
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const GuardThemeToggle(),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(color: palette.accent),
                      )
                    : _loadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: palette.error,
                                size: 42,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _loadError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: palette.text),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _loadDetails,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        color: palette.accent,
                        onRefresh: _loadDetails,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                          children: [
                            // ── Avatar & Photo Controls ─────────────────────
                            GuardSurfaceCard(
                              child: Column(
                                children: [
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      GuardAvatarCircle(
                                        photoUrl: photoUrl,
                                        initials: initials,
                                        seed: seed,
                                        size: 96,
                                        ringColor: palette.accent,
                                        ringWidth: 3,
                                      ),
                                      if (_uploadingPhoto)
                                        Container(
                                          width: 102,
                                          height: 102,
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.45,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          alignment: Alignment.center,
                                          child:
                                              const CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.6,
                                              ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    fullName,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: palette.text,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${d['personnel_id']?.toString().trim().isNotEmpty == true ? d['personnel_id'] : 'No SEC ID'} · $category',
                                    style: TextStyle(
                                      color: palette.textMuted,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      FilledButton.tonalIcon(
                                        onPressed: _uploadingPhoto
                                            ? null
                                            : () => _pickAndUploadPhoto(
                                                ImageSource.camera,
                                              ),
                                        icon: const Icon(
                                          Icons.photo_camera_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('Camera'),
                                      ),
                                      FilledButton.tonalIcon(
                                        onPressed: _uploadingPhoto
                                            ? null
                                            : () => _pickAndUploadPhoto(
                                                ImageSource.gallery,
                                              ),
                                        icon: const Icon(
                                          Icons.photo_library_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('Gallery'),
                                      ),
                                      if (hasPhoto)
                                        OutlinedButton.icon(
                                          onPressed: _uploadingPhoto
                                              ? null
                                              : _confirmRemovePhoto,
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: palette.error,
                                            side: BorderSide(
                                              color: palette.error.withValues(
                                                alpha: 0.45,
                                              ),
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Remove'),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'JPG or PNG · Max 2 MB · Circular crop (~400×400)',
                                    style: TextStyle(
                                      color: palette.textMuted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),

                            // ── Editable Personal Information ────────────────
                            GuardSurfaceCard(
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.edit_note_rounded,
                                          color: palette.accent,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'PERSONAL CONTACT DETAILS',
                                          style: TextStyle(
                                            color: palette.accent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Changes appear automatically in Personnel Records and on the Live Guard Map.',
                                      style: TextStyle(
                                        color: palette.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _mobileCtrl,
                                      keyboardType: TextInputType.phone,
                                      decoration: const InputDecoration(
                                        labelText: 'Contact / Mobile Number',
                                        hintText: '09171234567',
                                        helperText:
                                            '11-digit Philippine mobile starting with 09',
                                        prefixIcon: Icon(
                                          Icons.smartphone_rounded,
                                        ),
                                      ),
                                      validator: (value) {
                                        final raw = (value ?? '')
                                            .replaceAll(
                                              RegExp(r'[\s\-()]'),
                                              '',
                                            )
                                            .trim();
                                        if (raw.isEmpty) {
                                          return 'Enter your 11-digit contact number.';
                                        }
                                        final normalized = raw.startsWith('+639') &&
                                                raw.length == 13
                                            ? '0${raw.substring(3)}'
                                            : raw;
                                        if (!RegExp(r'^09\d{9}$')
                                            .hasMatch(normalized)) {
                                          return 'Enter an 11-digit number starting with 09.';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      controller: _addressCtrl,
                                      maxLines: 2,
                                      maxLength: 500,
                                      decoration: const InputDecoration(
                                        labelText: 'Complete Address',
                                        hintText:
                                            'House/Lot, Street, Barangay, City/Municipality, Province',
                                        prefixIcon: Icon(Icons.home_outlined),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: _emergencyCtrl,
                                      maxLength: 300,
                                      decoration: const InputDecoration(
                                        labelText: 'Emergency Contact',
                                        hintText:
                                            'e.g. Maria Santos (Spouse) — 09181234567',
                                        helperText:
                                            'Full name, relationship, and phone number',
                                        prefixIcon: Icon(
                                          Icons.contact_phone_outlined,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: _savingInfo
                                            ? null
                                            : _savePersonalDetails,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        icon: _savingInfo
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.save_rounded),
                                        label: Text(
                                          _savingInfo
                                              ? 'Saving...'
                                              : 'Save Contact Details',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),

                            // ── Read-Only Employment & Assignment Record ─────
                            GuardSurfaceCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.lock_outline_rounded,
                                        color: palette.textMuted,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'AGENCY RECORD (READ-ONLY)',
                                          style: TextStyle(
                                            color: palette.textMuted,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Managed exclusively by the Operations Head.',
                                    style: TextStyle(
                                      color: palette.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  _ReadOnlyFieldRow(
                                    label: 'Full Name',
                                    value: fullName,
                                  ),
                                  _ReadOnlyFieldRow(
                                    label: 'SEC Personnel ID',
                                    value: d['personnel_id']
                                                ?.toString()
                                                .trim()
                                                .isNotEmpty ==
                                            true
                                        ? d['personnel_id'].toString()
                                        : 'Not assigned',
                                  ),
                                  _ReadOnlyFieldRow(
                                    label: 'Email',
                                    value: UserProfileService.displayLoginId(d),
                                  ),
                                  _ReadOnlyFieldRow(
                                    label: 'Date Hired',
                                    value: _formatDate(d['date_hired']),
                                  ),
                                  _ReadOnlyFieldRow(
                                    label: 'Duty Category',
                                    value: category,
                                  ),
                                  _ReadOnlyFieldRow(
                                    label: 'Contract Status',
                                    value: d['contract_status']
                                                ?.toString()
                                                .trim()
                                                .isNotEmpty ==
                                            true
                                        ? '${d['contract_status']} (${contract.label(DateTime.now())})'
                                        : contract.label(DateTime.now()),
                                  ),
                                  _ReadOnlyFieldRow(
                                    label: 'Contract Dates',
                                    value: contractDates,
                                  ),
                                  _ReadOnlyFieldRow(
                                    label: 'Assigned Post',
                                    value: d['assigned_post_label']
                                            ?.toString() ??
                                        'Unassigned',
                                  ),
                                  _ReadOnlyFieldRow(
                                    label: 'Assigned Inspector',
                                    value: d['inspector_name']?.toString() ??
                                        'Unassigned',
                                    showDivider: false,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyFieldRow extends StatelessWidget {
  const _ReadOnlyFieldRow({
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 132,
                child: Text(
                  label,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: palette.border.withValues(alpha: 0.65)),
      ],
    );
  }
}

class _CircularPhotoCropDialog extends StatefulWidget {
  const _CircularPhotoCropDialog({
    required this.sourceBytes,
    required this.imageWidth,
    required this.imageHeight,
  });

  final Uint8List sourceBytes;
  final int imageWidth;
  final int imageHeight;

  @override
  State<_CircularPhotoCropDialog> createState() =>
      _CircularPhotoCropDialogState();
}

class _CircularPhotoCropDialogState extends State<_CircularPhotoCropDialog> {
  static const double _viewportSize = 260;

  double _zoom = 1.0;
  double _normCenterX = 0.5;
  double _normCenterY = 0.5;
  bool _processing = false;

  void _handlePan(DragUpdateDetails details) {
    final aspect = widget.imageWidth / math.max(1, widget.imageHeight);
    final baseW = aspect >= 1 ? _viewportSize * aspect : _viewportSize;
    final baseH = aspect >= 1 ? _viewportSize : _viewportSize / aspect;
    final scaledW = baseW * _zoom;
    final scaledH = baseH * _zoom;

    setState(() {
      _normCenterX = (_normCenterX - details.delta.dx / scaledW).clamp(
        0.0,
        1.0,
      );
      _normCenterY = (_normCenterY - details.delta.dy / scaledH).clamp(
        0.0,
        1.0,
      );
    });
  }

  Future<void> _confirmCrop() async {
    setState(() => _processing = true);
    try {
      final result = ProfilePhotoCodec.cropAndResizeTo400Jpeg(
        widget.sourceBytes,
        normCenterX: _normCenterX,
        normCenterY: _normCenterY,
        zoom: _zoom,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final aspect = widget.imageWidth / math.max(1, widget.imageHeight);
    final baseW = aspect >= 1 ? _viewportSize * aspect : _viewportSize;
    final baseH = aspect >= 1 ? _viewportSize : _viewportSize / aspect;
    final scaledW = baseW * _zoom;
    final scaledH = baseH * _zoom;

    final maxOffsetX = math.max(0.0, (scaledW - _viewportSize) / 2);
    final maxOffsetY = math.max(0.0, (scaledH - _viewportSize) / 2);
    final translateX = ((0.5 - _normCenterX) * scaledW).clamp(
      -maxOffsetX,
      maxOffsetX,
    );
    final translateY = ((0.5 - _normCenterY) * scaledH).clamp(
      -maxOffsetY,
      maxOffsetY,
    );

    return AlertDialog(
      title: const Text('Crop Profile Photo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Drag to position and adjust zoom for your circular avatar.',
            style: TextStyle(color: palette.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onPanUpdate: _handlePan,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: _viewportSize,
                height: _viewportSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(color: Colors.black),
                    Transform.translate(
                      offset: Offset(translateX, translateY),
                      child: SizedBox(
                        width: scaledW,
                        height: scaledH,
                        child: Image.memory(
                          widget.sourceBytes,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        size: const Size(_viewportSize, _viewportSize),
                        painter: _CircularMaskPainter(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.zoom_out_rounded, size: 18, color: palette.textMuted),
              Expanded(
                child: Slider(
                  value: _zoom,
                  min: 1.0,
                  max: 3.0,
                  activeColor: AppColors.primary,
                  onChanged: _processing
                      ? null
                      : (val) => setState(() => _zoom = val),
                ),
              ),
              Icon(Icons.zoom_in_rounded, size: 18, color: palette.textMuted),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _processing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _processing ? null : _confirmCrop,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          icon: _processing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: Text(_processing ? 'Processing...' : 'Use Photo'),
        ),
      ],
    );
  }
}

class _CircularMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 8;

    final maskPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      maskPath,
      Paint()..color = Colors.black.withValues(alpha: 0.56),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

