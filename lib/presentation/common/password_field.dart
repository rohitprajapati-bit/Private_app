import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/usecases/password_policy.dart';

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.onSubmitted,
    this.autofocus = false,
    this.textInputAction = TextInputAction.next,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputAction textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      obscureText: _obscure,
      enableSuggestions: false,
      autocorrect: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show' : 'Hide',
          icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final strength = passwordStrength(password);
    final (value, color, label) = switch (strength) {
      PasswordStrength.weak => (0.33, AppColors.danger, 'Weak'),
      PasswordStrength.fair => (0.66, Colors.amber, 'Fair'),
      PasswordStrength.strong => (1.0, AppColors.success, 'Strong'),
    };
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: password.isEmpty ? 0 : value,
              color: color,
              backgroundColor: AppColors.surfaceHigh,
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(password.isEmpty ? '' : label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }
}
