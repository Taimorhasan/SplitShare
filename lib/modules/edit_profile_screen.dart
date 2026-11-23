import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../controllers/profile_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';

/// Edit name, photo and (private) phone number. Email is read-only.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  ProfileController get _profile => ProfileController.to;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;

  /// Values the form started from (kept in sync while the profile loads).
  late String _originalName;
  late String _originalPhone;

  File? _pickedImage;
  bool _removePhoto = false;
  bool _saving = false;
  final List<Worker> _workers = [];

  @override
  void initState() {
    super.initState();
    _originalName = _profile.name.value;
    _originalPhone = _profile.phone.value;
    _nameCtrl = TextEditingController(text: _originalName)
      ..addListener(_onChanged);
    _emailCtrl = TextEditingController(text: _profile.email.value);
    _phoneCtrl = TextEditingController(text: _originalPhone)
      ..addListener(_onChanged);

    // The profile (and the private phone doc) may arrive after this screen
    // opens. Fill fields the user hasn't touched yet.
    _workers
      ..add(
        ever<String>(_profile.name, (v) {
          if (_nameCtrl.text == _originalName) {
            _originalName = v;
            _nameCtrl.text = v;
          }
        }),
      )
      ..add(
        ever<String>(_profile.phone, (v) {
          if (_phoneCtrl.text == _originalPhone) {
            _originalPhone = v;
            _phoneCtrl.text = v;
          }
        }),
      )
      ..add(ever<String>(_profile.email, (v) => _emailCtrl.text = v));
  }

  @override
  void dispose() {
    for (final w in _workers) {
      w.dispose();
    }
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool get _dirty =>
      _nameCtrl.text.trim() != _originalName.trim() ||
      _phoneCtrl.text.trim() != _originalPhone.trim() ||
      _pickedImage != null ||
      _removePhoto;

  bool get _hasPhoto =>
      _pickedImage != null ||
      (!_removePhoto && _profile.avatarUrl.value.startsWith('http'));

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 800,
      );
      if (file == null || !mounted) return;
      setState(() {
        _pickedImage = File(file.path);
        _removePhoto = false;
      });
    } catch (e) {
      AppToast.error(
        source == ImageSource.camera
            ? 'Couldn\'t open the camera. Check camera permission and try again.'
            : 'Couldn\'t open your photos. Check photo permission and try again.',
        title: 'Photo unavailable',
      );
    }
  }

  void _showPhotoOptions() {
    AppNav.unfocus();
    AppDialogs.sheet<void>(
      title: 'Profile photo',
      child: Builder(
        builder: (sheetContext) {
          void choose(VoidCallback action) {
            Navigator.of(sheetContext).pop();
            action();
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppListTile(
                  icon: Icons.photo_camera_outlined,
                  title: 'Take photo',
                  showChevron: false,
                  onTap: () => choose(() => _pick(ImageSource.camera)),
                ),
                AppListTile(
                  icon: Icons.photo_library_outlined,
                  iconColor: AppColors.secondary,
                  title: 'Choose from gallery',
                  showChevron: false,
                  onTap: () => choose(() => _pick(ImageSource.gallery)),
                ),
                if (_hasPhoto)
                  AppListTile(
                    icon: Icons.delete_outline_rounded,
                    title: 'Remove photo',
                    destructive: true,
                    showChevron: false,
                    onTap: () => choose(() {
                      setState(() {
                        _pickedImage = null;
                        // Only an existing uploaded photo needs removing.
                        _removePhoto = _profile.avatarUrl.value.startsWith(
                          'http',
                        );
                      });
                    }),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    AppNav.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      String? newAvatar;
      if (_pickedImage != null) {
        newAvatar = await _profile.uploadAvatar(_pickedImage!);
      } else if (_removePhoto) {
        newAvatar = '';
      }

      await _profile.updateProfile(
        newName: _nameCtrl.text.trim(),
        newPhone: _phoneCtrl.text.trim() != _originalPhone.trim()
            ? _phoneCtrl.text.trim()
            : null,
        newAvatar: newAvatar,
      );
      if (!mounted) return;
      _originalName = _nameCtrl.text.trim();
      _originalPhone = _phoneCtrl.text.trim();
      _pickedImage = null;
      _removePhoto = false;
      // Pop before showing the toast: Get.back() would only close an open toast.
      Navigator.of(context).pop();
      AppToast.success('Your profile has been updated.', title: 'Saved');
    } catch (e) {
      AppToast.error(AppToast.friendly(e), title: 'Couldn\'t save changes');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await AppDialogs.confirm(
      title: 'Discard changes?',
      message: 'Your edits to your profile haven\'t been saved.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
      destructive: true,
    );
    if (discard && mounted) {
      setState(() {
        _nameCtrl.text = _originalName;
        _phoneCtrl.text = _originalPhone;
        _pickedImage = null;
        _removePhoto = false;
      });
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;
    return PopScope(
      canPop: !dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _saving) return;
        _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppTopBar(
          title: 'Edit profile',
          onBack: () => Navigator.of(context).maybePop(),
        ),
        body: GestureDetector(
          onTap: AppNav.unfocus,
          behavior: HitTestBehavior.translucent,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.xxxl,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FadeSlideIn(child: _buildAvatar()),
                  const SizedBox(height: AppSpacing.xxl),
                  FadeSlideIn(
                    index: 1,
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTextField(
                            controller: _nameCtrl,
                            label: 'Full name',
                            hint: 'e.g. Alex Morgan',
                            prefixIcon: Icons.person_outline_rounded,
                            validator: Validators.name,
                            maxLength: 50,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppTextField(
                            controller: _emailCtrl,
                            label: 'Email',
                            prefixIcon: Icons.mail_outline_rounded,
                            readOnly: true,
                            suffix: const Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                            helperText:
                                'Email is used to sign in and can\'t be changed here',
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          AppTextField(
                            controller: _phoneCtrl,
                            label: 'Phone',
                            hint: 'Optional',
                            prefixIcon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            validator: Validators.phone,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                            helperText: 'Only visible to you',
                            onSubmitted: (_) => _save(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FadeSlideIn(
                    index: 2,
                    child: AppButton(
                      label: 'Save changes',
                      icon: Icons.check_rounded,
                      loading: _saving,
                      onPressed: dirty ? _save : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Center(
      child: Pressable(
        onTap: _saving ? null : _showPhotoOptions,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                shape: BoxShape.circle,
                boxShadow: AppShadows.glow(AppColors.primary),
              ),
              child: AnimatedSwitcher(
                duration: AppMotion.normal,
                child: _pickedImage != null
                    ? Container(
                        key: ValueKey(_pickedImage!.path),
                        padding: const EdgeInsets.all(2.5),
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: Image.file(
                            _pickedImage!,
                            width: 104,
                            height: 104,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                    : Obx(
                        () => AppAvatar(
                          key: ValueKey('avatar-$_removePhoto'),
                          name: _profile.name.value,
                          imageUrl: _removePhoto
                              ? null
                              : _profile.avatarUrl.value,
                          radius: 52,
                          ring: true,
                        ),
                      ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 2,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 3),
                ),
                child: const Icon(
                  Icons.photo_camera_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
