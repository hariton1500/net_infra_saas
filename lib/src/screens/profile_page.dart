import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../core/app_i18n.dart';
import '../core/app_logger.dart';
import '../core/employee_positions.dart';
import '../widgets/language_selector.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late String _selectedPosition;

  @override
  void initState() {
    super.initState();
    final profile = widget.controller.profile;
    _fullNameController = TextEditingController(text: profile?.fullName ?? '');
    _selectedPosition = employeePositions.contains(profile?.position)
        ? profile!.position
        : employeePositionEngineer;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final profile = controller.profile;
    final email = profile?.email ?? controller.currentUser?.email ?? '-';
    final role = controller.membership?.role ?? '-';

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Профиль сотрудника')),
        actions: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: LanguageSelector()),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Личные данные'),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(
                            'Здесь можно обновить имя и должность. Email и роль доступны только для просмотра.',
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          initialValue: email,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: tr('Рабочий email'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          initialValue: _roleLabel(role),
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: tr('Роль в компании'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _fullNameController,
                          decoration: InputDecoration(
                            labelText: tr('Имя сотрудника'),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return tr('Введите имя сотрудника.');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedPosition,
                          decoration: InputDecoration(
                            labelText: tr('Должность'),
                          ),
                          items: employeePositions
                              .map(
                                (position) => DropdownMenuItem<String>(
                                  value: position,
                                  child: Text(tr(position)),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: controller.isBusy
                              ? null
                              : (value) {
                                  if (value == null) {
                                    return;
                                  }

                                  setState(() {
                                    _selectedPosition = value;
                                  });
                                },
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: controller.isBusy ? null : _saveProfile,
                          child: controller.isBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(tr('Сохранить профиль')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      await widget.controller.updateProfile(
        fullName: _fullNameController.text,
        position: _selectedPosition,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('Профиль обновлён.'))));
    } catch (_) {
      if (!mounted) {
        return;
      }

      final message =
          widget.controller.errorMessage ?? tr('Не удалось обновить профиль.');
      logUserFacingError(message, source: 'profile_page.save');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _roleLabel(String value) {
    switch (value) {
      case 'owner':
        return tr('Владелец');
      case 'admin':
        return tr('Администратор');
      case 'member':
        return tr('Сотрудник');
      default:
        return value;
    }
  }
}
