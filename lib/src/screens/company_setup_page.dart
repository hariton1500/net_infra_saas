import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../core/app_logger.dart';

class CompanySetupPage extends StatefulWidget {
  const CompanySetupPage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<CompanySetupPage> createState() => _CompanySetupPageState();
}

class _CompanySetupPageState extends State<CompanySetupPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _companyController;

  @override
  void initState() {
    super.initState();
    _companyController = TextEditingController(
      text: widget.controller.suggestedCompanyName,
    );
  }

  @override
  void dispose() {
    _companyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.controller.currentUser;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Завершите настройку компании',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Вы вошли как ${user?.email ?? 'пользователь'}, но рабочее '
                        'пространство компании ещё не создано.',
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _companyController,
                        decoration: const InputDecoration(
                          labelText: 'Название компании',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Укажите название компании.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: widget.controller.isBusy
                            ? null
                            : _handleCompleteSetup,
                        child: widget.controller.isBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Создать рабочее пространство'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: widget.controller.isBusy
                            ? null
                            : widget.controller.signOut,
                        child: const Text('Выйти'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleCompleteSetup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      final message = await widget.controller.completeCompanySetup(
        companyName: _companyController.text,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      final message =
          widget.controller.errorMessage ??
          'Не удалось завершить настройку компании.';
      logUserFacingError(message, source: 'company.setup');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
