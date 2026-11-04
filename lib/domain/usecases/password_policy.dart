import '../../core/constants/app_constants.dart';

/// Returns an error message, or null when [password] is acceptable.
String? validateNewPassword(String password, String confirmation) {
  if (password.length < AppConstants.minPasswordLength) {
    return 'Use at least ${AppConstants.minPasswordLength} characters.';
  }
  if (password.trim().isEmpty) return 'Password cannot be only spaces.';
  if (password != confirmation) return 'Passwords do not match.';
  return null;
}

enum PasswordStrength { weak, fair, strong }

PasswordStrength passwordStrength(String password) {
  var classes = 0;
  if (RegExp('[a-z]').hasMatch(password)) classes++;
  if (RegExp('[A-Z]').hasMatch(password)) classes++;
  if (RegExp('[0-9]').hasMatch(password)) classes++;
  if (RegExp('[^a-zA-Z0-9]').hasMatch(password)) classes++;
  if (password.length >= 14 && classes >= 2 || password.length >= 10 && classes >= 3) {
    return PasswordStrength.strong;
  }
  if (password.length >= AppConstants.minPasswordLength && classes >= 2) return PasswordStrength.fair;
  return PasswordStrength.weak;
}
