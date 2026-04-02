import 'package:flutter/material.dart';
import '../app_colors.dart';

class ShieldLogo extends StatelessWidget {
  final double size;

  const ShieldLogo({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.2,
      child: CustomPaint(
        painter: _ShieldPainter(),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: size * 0.1),
            child: Text(
              'SC',
              style: TextStyle(
                fontSize: size * 0.32,
                fontWeight: FontWeight.bold,
                color: AppColors.shieldOuter,
                fontFamily: 'serif',
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Outer shield glow
    final glowPaint = Paint()
      ..color = AppColors.shieldOuter.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawPath(_shieldPath(w, h, 0), glowPaint);

    // Outer fill
    final outerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.shieldOuter,
          AppColors.shieldOuter.withValues(alpha: 0.7),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(_shieldPath(w, h, 0), outerPaint);

    // Inner dark fill
    final innerPaint = Paint()..color = AppColors.shieldInner;
    canvas.drawPath(_shieldPath(w * 0.88, h * 0.88, 0), innerPaint..color = AppColors.shieldInner);

    // Translate for inner path
    canvas.save();
    canvas.translate(w * 0.06, h * 0.05);
    canvas.drawPath(_shieldPath(w * 0.88, h * 0.88, 0), innerPaint);
    canvas.restore();

    // Border stroke
    final borderPaint = Paint()
      ..color = AppColors.shieldOuter
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(_shieldPath(w, h, 0), borderPaint);
  }

  Path _shieldPath(double w, double h, double inset) {
    final path = Path();
    final cx = w / 2;

    path.moveTo(cx, inset);
    // Top curve
    path.quadraticBezierTo(w * 0.85, inset + h * 0.02, w - inset, h * 0.15);
    // Right side
    path.lineTo(w - inset, h * 0.45);
    // Bottom right curve
    path.quadraticBezierTo(w - inset, h * 0.7, cx, h - inset);
    // Bottom left curve
    path.quadraticBezierTo(inset, h * 0.7, inset, h * 0.45);
    // Left side
    path.lineTo(inset, h * 0.15);
    // Top left curve
    path.quadraticBezierTo(w * 0.15, inset + h * 0.02, cx, inset);

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
