import 'package:flutter/material.dart';

ThemeData interactionTheme(ThemeData theme) => theme.copyWith(
  materialTapTargetSize: MaterialTapTargetSize.padded,
  visualDensity: VisualDensity.standard,
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
  ),
  focusColor: theme.colorScheme.primary.withValues(alpha: .25),
  dataTableTheme: const DataTableThemeData(
    dataRowMinHeight: 56,
    dataRowMaxHeight: double.infinity,
  ),
);
