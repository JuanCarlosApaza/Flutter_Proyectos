import 'package:flutter/material.dart';

/// Paleta central del dashboard.
/// Verde profundo para sidebar / cards oscuras, fondo hueso suave para el
/// contenido y un único acento verde usado de forma consistente.
class AppColors {
  AppColors._();

  // Familia verde de marca
  static const Color brandGreen = Color(0xFF2FBE7A);
  static const Color brandGreenDark = Color(0xFF0E3B2E);
  static const Color sidebarBg = Color(0xFF0B2E24);
  static const Color darkCardBg = Color(0xFF0E3B2E);
  static const Color darkCardBg2 = Color(0xFF123F32);

  // Fondo neutro / contenido
  static const Color pageBg = Color(0xFFEDEEEA);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFE7E8E3);

  // Texto
  static const Color textPrimary = Color(0xFF16241F);
  static const Color textSecondary = Color(0xFF7C8983);
  static const Color textOnDark = Color(0xFFFFFFFF);
  static const Color textOnDarkMuted = Color(0xFFAFC2BA);

  // Acentos de estado
  static const Color negativeRed = Color(0xFFE8604C);
  static const Color positiveGreen = Color(0xFF2FBE7A);
  static const Color trackGrey = Color(0xFFEDEEEA);
  static const Color darkTrack = Color(0xFF13221D);

  // Acentos de mapa (heat)
  static const Color mapHighest = Color(0xFFE8604C);
  static const Color mapHigh = Color(0xFFEE8A6E);
  static const Color mapMed = Color(0xFFF4B49D);
  static const Color mapLow = Color(0xFFF8D7C9);

  // Acentos de estado (extendidos)
  static const Color infoBlue = Color(0xFF4A90D9);
  static const Color warningOrange = Color(0xFFF5A623);
}
