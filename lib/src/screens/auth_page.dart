import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../core/app_logger.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _signInFormKey = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();

  final _signInEmailController = TextEditingController();
  final _signInPasswordController = TextEditingController();

  final _signUpFullNameController = TextEditingController();
  final _signUpCompanyController = TextEditingController();
  final _signUpEmailController = TextEditingController();
  final _signUpPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _signInEmailController.dispose();
    _signInPasswordController.dispose();
    _signUpFullNameController.dispose();
    _signUpCompanyController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF071526), Color(0xFF0A1B31), Color(0xFF102744)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 840;
                    final authCard = Card(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF0C1D33),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: TabBar(
                                controller: _tabController,
                                indicatorSize: TabBarIndicatorSize.tab,
                                tabs: const [
                                  Tab(text: 'Вход'),
                                  Tab(text: 'Регистрация'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 460,
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  _SignInForm(
                                    formKey: _signInFormKey,
                                    emailController: _signInEmailController,
                                    passwordController:
                                        _signInPasswordController,
                                    controller: widget.controller,
                                    onSubmit: _handleSignIn,
                                  ),
                                  _SignUpForm(
                                    formKey: _signUpFormKey,
                                    fullNameController:
                                        _signUpFullNameController,
                                    companyController: _signUpCompanyController,
                                    emailController: _signUpEmailController,
                                    passwordController:
                                        _signUpPasswordController,
                                    controller: widget.controller,
                                    onSubmit: _handleSignUp,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );

                    if (isCompact) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _BrandPanel(isCompact: true),
                          const SizedBox(height: 24),
                          authCard,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(child: _BrandPanel(isCompact: false)),
                        const SizedBox(width: 24),
                        Expanded(child: authCard),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSignIn() async {
    if (!_signInFormKey.currentState!.validate()) {
      return;
    }

    try {
      await widget.controller.signIn(
        email: _signInEmailController.text,
        password: _signInPasswordController.text,
      );
    } catch (_) {
      _showErrorMessage(widget.controller.errorMessage ?? 'Не удалось войти.');
    }
  }

  Future<void> _handleSignUp() async {
    if (!_signUpFormKey.currentState!.validate()) {
      return;
    }

    try {
      final message = await widget.controller.signUp(
        fullName: _signUpFullNameController.text,
        companyName: _signUpCompanyController.text,
        email: _signUpEmailController.text,
        password: _signUpPasswordController.text,
      );
      _showMessage(message);
    } catch (_) {
      _showErrorMessage(
        widget.controller.errorMessage ?? 'Не удалось создать аккаунт.',
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showErrorMessage(String message) {
    logUserFacingError(message, source: 'auth.page');
    _showMessage(message);
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF0C1D33),
                borderRadius: BorderRadius.circular(22),
              ),
              clipBehavior: Clip.antiAlias,
              child: const _BrandBadge(),
            ),
            const SizedBox(height: 24),
            Text(
              'Управление инфраструктурой для компаний и их команд',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            const Text(
              'Входите в рабочее пространство компании, создавайте первую организацию '
              'и готовьте доступ для сотрудников на общей платформе.',
            ),
            SizedBox(height: isCompact ? 24 : 40),
            const _FeatureTile(
              title: 'Один аккаунт на компанию',
              description:
                  'Владелец создаёт рабочее пространство и затем добавляет сотрудников.',
            ),
            const SizedBox(height: 14),
            const _FeatureTile(
              title: 'Сессии Supabase',
              description:
                  'Приложение автоматически восстанавливает активную сессию пользователя.',
            ),
            const SizedBox(height: 14),
            const _FeatureTile(
              title: 'Готово для multi-tenant',
              description:
                  'Профили, компании и роли сотрудников уже разделены на уровне базы.',
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1D33),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E466A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(description),
        ],
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BrandBadgePainter());
  }
}

class _BrandBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final framePaint = Paint()
      ..color = const Color(0xFF173E61)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    final teal = const Color(0xFF1EDDC5);
    final green = const Color(0xFF35C886);
    final white = const Color(0xFFF2F7FA);
    final muted = const Color(0xFF50749A);

    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(22),
    );
    canvas.drawRRect(rect, framePaint);

    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width * 0.26;

    final top = Offset(cx, cy - radius);
    final topRight = Offset(cx + radius * 0.86, cy - radius * 0.5);
    final bottomRight = Offset(cx + radius * 0.86, cy + radius * 0.5);
    final bottom = Offset(cx, cy + radius);
    final bottomLeft = Offset(cx - radius * 0.86, cy + radius * 0.5);
    final topLeft = Offset(cx - radius * 0.86, cy - radius * 0.5);
    final center = Offset(cx, cy);

    void drawLine(Offset a, Offset b, Color color, double width) {
      linePaint
        ..color = color
        ..strokeWidth = width;
      canvas.drawLine(a, b, linePaint);
    }

    void drawNode(Offset point, double r, Color color) {
      canvas.drawCircle(point, r, Paint()..color = color);
    }

    drawLine(topLeft, top, white, 4.8);
    drawLine(top, topRight, white, 4.8);
    drawLine(topRight, bottomRight, green, 4.2);
    drawLine(bottomRight, bottom, green, 4.2);
    drawLine(bottom, bottomLeft, green, 4.2);
    drawLine(bottomLeft, topLeft, green, 4.2);

    drawLine(center, top, muted, 3.6);
    drawLine(center, bottom, muted, 3.6);
    drawLine(center, topRight, teal, 3.2);
    drawLine(center, topLeft, teal, 3.2);
    drawLine(center, bottomLeft, const Color(0xFF294E72), 3.2);
    drawLine(center, bottomRight, const Color(0xFF294E72), 3.2);

    drawNode(top, 4.2, white);
    drawNode(topRight, 4.0, const Color(0xFFA6F6E8));
    drawNode(bottomRight, 4.0, green);
    drawNode(bottom, 4.0, green);
    drawNode(bottomLeft, 4.0, green);
    drawNode(topLeft, 4.0, green);
    drawNode(center, 5.2, green);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SignInForm extends StatelessWidget {
  const _SignInForm({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.controller,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final AuthController controller;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Вход для сотрудников',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text(
            'Используйте рабочий email и пароль, чтобы открыть пространство компании.',
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Рабочий email'),
            validator: _validateEmail,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Пароль'),
            validator: _validatePassword,
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: controller.isBusy ? null : onSubmit,
            child: controller.isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Войти'),
          ),
        ],
      ),
    );
  }
}

class _SignUpForm extends StatelessWidget {
  const _SignUpForm({
    required this.formKey,
    required this.fullNameController,
    required this.companyController,
    required this.emailController,
    required this.passwordController,
    required this.controller,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController fullNameController;
  final TextEditingController companyController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final AuthController controller;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Регистрация владельца компании',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text(
            'Создайте первый аккаунт компании. После этого можно будет добавлять сотрудников.',
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: fullNameController,
            decoration: const InputDecoration(labelText: 'Ваше имя'),
            validator: _validateRequired,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: companyController,
            decoration: const InputDecoration(labelText: 'Название компании'),
            validator: _validateRequired,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Рабочий email'),
            validator: _validateEmail,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Пароль'),
            validator: _validatePassword,
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: controller.isBusy ? null : onSubmit,
            child: controller.isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Создать компанию'),
          ),
        ],
      ),
    );
  }
}

String? _validateRequired(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Поле обязательно.';
  }

  return null;
}

String? _validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Введите email.';
  }

  if (!value.contains('@')) {
    return 'Введите корректный email.';
  }

  return null;
}

String? _validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Введите пароль.';
  }

  if (value.length < 8) {
    return 'Минимум 8 символов.';
  }

  return null;
}
