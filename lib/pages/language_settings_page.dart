import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../providers/app_locale_controller.dart';
import '../widgets/app_feedback.dart';
import '../widgets/inset_settings.dart';
import '../widgets/quiet_paper.dart';

class LanguageSettingsPage extends StatefulWidget {
  const LanguageSettingsPage({super.key});

  @override
  State<LanguageSettingsPage> createState() => _LanguageSettingsPageState();
}

class _LanguageSettingsPageState extends State<LanguageSettingsPage> {
  AppLanguage? _saving;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppLocaleController>();
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.chooseLanguage)),
      body: PaperShell(
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
              children: [
                Text(
                  l10n.languageDescription,
                  style: TextStyle(color: context.appColors.muted, height: 1.5),
                ),
                const SizedBox(height: 20),
                InsetSettingsSection(
                  children: [
                    for (final language in AppLanguage.values)
                      InsetSettingsRow(
                        rowKey: Key('app-language-${language.name}'),
                        title: _appLanguageTitle(l10n, language),
                        subtitle: _appLanguageDescription(l10n, language),
                        selected: controller.language == language,
                        busy: _saving == language,
                        enabled: _saving == null,
                        showDisclosure: false,
                        onTap: () => _select(controller, language),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _select(
    AppLocaleController controller,
    AppLanguage language,
  ) async {
    if (_saving != null || controller.language == language) return;
    setState(() => _saving = language);
    try {
      await controller.setLanguage(language);
    } catch (_) {
      if (mounted) AppFeedback.error(context, context.l10n.languageSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }
}

String _appLanguageTitle(AppLocalizations l10n, AppLanguage language) =>
    switch (language) {
      AppLanguage.system => l10n.languageSystem,
      AppLanguage.simplifiedChinese => l10n.languageSimplifiedChinese,
      AppLanguage.english => l10n.languageEnglish,
    };

String _appLanguageDescription(AppLocalizations l10n, AppLanguage language) =>
    switch (language) {
      AppLanguage.system => l10n.languageSystemDescription,
      AppLanguage.simplifiedChinese =>
        l10n.languageSimplifiedChineseDescription,
      AppLanguage.english => l10n.languageEnglishDescription,
    };
