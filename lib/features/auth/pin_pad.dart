import 'package:flutter/material.dart';

/// Numeric keypad with dots, used for unlock and PIN creation.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onCompleted,
    this.length = 4,
    this.onBiometric,
    this.color = Colors.white,
  });

  final int length;
  final Future<void> Function(String pin) onCompleted;
  final VoidCallback? onBiometric;
  final Color color;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  bool _busy = false;

  Future<void> _tap(String d) async {
    if (_busy || _pin.length >= widget.length) return;
    setState(() => _pin += d);
    if (_pin.length == widget.length) {
      _busy = true;
      final entered = _pin;
      await widget.onCompleted(entered);
      if (mounted) {
        setState(() {
          _pin = '';
          _busy = false;
        });
      }
    }
  }

  void _back() {
    if (_pin.isEmpty || _busy) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Widget _key(String label) => _KeyButton(
        onPressed: () => _tap(label),
        semantics: label,
        child: Text(label,
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w600, color: widget.color)),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '${_pin.length} of ${widget.length} digits entered',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.length, (i) {
              final filled = i < _pin.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 9),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? widget.color : Colors.transparent,
                  border: Border.all(
                      color: widget.color.withValues(alpha: 0.6), width: 2),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 40),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map(_key).toList(),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            widget.onBiometric == null
                ? const SizedBox(width: 80, height: 72)
                : _KeyButton(
                    onPressed: widget.onBiometric!,
                    semantics: 'Unlock with biometrics',
                    child: Icon(Icons.fingerprint,
                        size: 32, color: widget.color.withValues(alpha: 0.85)),
                  ),
            _key('0'),
            _KeyButton(
              onPressed: _back,
              semantics: 'Delete digit',
              child: Icon(Icons.backspace_outlined, color: widget.color),
            ),
          ],
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton(
      {required this.onPressed, required this.child, required this.semantics});
  final VoidCallback onPressed;
  final Widget child;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: SizedBox(
        width: 80,
        height: 72,
        child: InkResponse(
          onTap: onPressed,
          radius: 36,
          child: Center(child: child),
        ),
      ),
    );
  }
}
