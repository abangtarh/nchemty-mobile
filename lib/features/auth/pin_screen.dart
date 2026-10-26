import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import 'auth_controller.dart';
import 'pin_pad.dart';

/// Unlock with the local PIN or biometrics.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  bool _bio = false;

  @override
  void initState() {
    super.initState();
    _initBiometrics();
  }

  Future<void> _initBiometrics() async {
    final auth = ref.read(authProvider.notifier);
    final can = await auth.canUseBiometrics();
    if (!mounted) return;
    setState(() => _bio = can);
    if (can) await auth.unlockWithBiometrics();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(ref);
    final state = ref.watch(authProvider);
    final auth = ref.read(authProvider.notifier);
    return Scaffold(
      backgroundColor: AppColors.green,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 48),
              CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.greenDark,
                child: Text(state.user?.initials ?? '',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 16),
              Text(s.t('welcomeBack'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(state.error ?? s.t('enterPin'),
                  style: TextStyle(
                      color: state.error != null
                          ? AppColors.goldLight
                          : Colors.white.withValues(alpha: 0.78))),
              const Spacer(),
              PinPad(
                onCompleted: (pin) async {
                  await auth.unlockWithPin(pin);
                },
                onBiometric: _bio ? () => auth.unlockWithBiometrics() : null,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: auth.logout,
                style: TextButton.styleFrom(foregroundColor: AppColors.goldLight),
                child: Text(s.t('usePassword')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// First-time PIN creation (enter twice), then offer biometrics.
class CreatePinScreen extends ConsumerStatefulWidget {
  const CreatePinScreen({super.key});

  @override
  ConsumerState<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends ConsumerState<CreatePinScreen> {
  String? _first;
  String? _error;

  Future<void> _onPin(String pin) async {
    if (_first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (pin != _first) {
      setState(() {
        _first = null;
        _error = S.read(ref).t('pinMismatch');
      });
      return;
    }
    final auth = ref.read(authProvider.notifier);
    final wantsBio = await auth.biometricsAvailable() && await _askBiometrics();
    final error = await auth.createPin(pin, biometrics: wantsBio);
    if (error != null && mounted) {
      // Cyclos refused the PIN (too simple, wrong length): choose another.
      setState(() {
        _first = null;
        _error = error;
      });
    }
  }

  Future<bool> _askBiometrics() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Use fingerprint or Face ID?'),
        content: const Text(
            'You can unlock Nchemty with biometrics instead of typing your PIN.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Turn on')),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(ref);
    return Scaffold(
      backgroundColor: AppColors.green,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 80),
              Text(s.t(_first == null ? 'createPin' : 'confirmPin'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.goldLight)),
              ],
              const Spacer(),
              PinPad(key: ValueKey(_first == null), onCompleted: _onPin),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
