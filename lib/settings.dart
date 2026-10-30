import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

final settings = Settings();

/// Réglages persistés, lus en synchrone après [load].
class Settings extends ChangeNotifier {
  late SharedPreferences _p;

  Future<void> load() async => _p = await SharedPreferences.getInstance();

  ThemeMode get theme => ThemeMode.values[_p.getInt('theme') ?? 0];
  set theme(ThemeMode v) => _save(_p.setInt('theme', v.index));

  bool get haptics => _p.getBool('haptics') ?? true;
  set haptics(bool v) => _save(_p.setBool('haptics', v));

  /// Dernier modèle choisi, proposé par défaut aux nouvelles conversations.
  String get model => _p.getString('model') ?? '';
  set model(String v) => _save(_p.setString('model', v));

  /// Adresse du serveur Hermes, lue par hermes.dart une fois branché.
  String get url => _p.getString('url') ?? '';
  set url(String v) => _save(_p.setString('url', v.trim()));

  void _save(Future<bool> _) => notifyListeners();

  void haptic() {
    if (haptics) HapticFeedback.lightImpact();
  }
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final url = TextEditingController(text: settings.url);

  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final label = TextStyle(fontSize: 17, color: c.onSurface);
    Widget section(String title, List<Widget> children, {String? footer}) => CupertinoListSection.insetGrouped(
      backgroundColor: c.surface,
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      separatorColor: c.outline.withValues(alpha: .2),
      header: Text(title.toUpperCase(), style: TextStyle(fontSize: 13, color: c.outline)),
      footer: footer == null ? null : Text(footer, style: TextStyle(fontSize: 13, color: c.outline)),
      children: children,
    );

    return Material(
      color: c.surface,
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => ListView(
            children: [
              SizedBox(
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'Paramètres',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                    ),
                    Positioned(
                      right: 4,
                      child: CupertinoButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'OK',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              section('Apparence', [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  child: CupertinoSlidingSegmentedControl<ThemeMode>(
                    groupValue: settings.theme,
                    thumbColor: c.surface,
                    backgroundColor: c.surfaceContainerLow,
                    onValueChanged: (v) => settings.theme = v!,
                    children: {
                      for (final (m, l) in [(ThemeMode.system, 'Système'), (ThemeMode.light, 'Clair'), (ThemeMode.dark, 'Sombre')])
                        m: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(l, style: TextStyle(fontSize: 15, color: c.onSurface)),
                        ),
                    },
                  ),
                ),
              ]),
              section('Général', [
                CupertinoListTile(
                  title: Text('Retours haptiques', style: label),
                  trailing: CupertinoSwitch(value: settings.haptics, onChanged: (v) => settings.haptics = v),
                ),
              ]),
              section('Serveur Hermes', [
                CupertinoListTile(
                  title: CupertinoTextField.borderless(
                    controller: url,
                    placeholder: 'https://hermes.exemple.fr',
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    padding: EdgeInsets.zero,
                    style: label,
                    onChanged: (v) => settings.url = v,
                  ),
                ),
              ], footer: 'Adresse à laquelle l’app enverra les messages.'),
            ],
          ),
        ),
      ),
    );
  }
}
