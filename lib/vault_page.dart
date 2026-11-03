import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'cron_page.dart';
import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';

/// Hermes' vault: the accounts it may sign in with for you. Passwords go to the server's encrypted
/// store and never come back; this page only sees labels, sites and identifiers.
class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  List<VaultItem>? items;
  Object? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final g = await gateway();
      if (g == null) throw StateError('no server');
      final r = await g.call('vault.list');
      if (!mounted) return;
      setState(() {
        items = parseVault(r);
        error = null;
      });
    } catch (e) {
      debugPrint('Vault: $e');
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> add() async {
    final added = await Navigator.of(context).push<bool>(CupertinoPageRoute(builder: (_) => const VaultAddPage()));
    if (added == true) load();
  }

  Future<bool> confirmDelete(VaultItem i) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showChoices<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(i.label, maxLines: 2, overflow: TextOverflow.ellipsis),
        message: Text(l.vaultDeleteMessage),
        actions: [
          CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: Text(l.vaultDelete)),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
      ),
    );
    if (ok != true) return false;
    try {
      final g = await gateway();
      if (g == null) throw StateError('no server');
      await g.call('vault.remove', {'id': i.id});
      return true;
    } catch (e) {
      debugPrint('Vault remove: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.deleteFailed(e is HttpException ? e.message : '$e'))));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    final list = items;
    return PageFrame(
      title: l.vault,
      action: error == null
          ? IconButton(
              tooltip: l.vaultAdd,
              onPressed: add,
              icon: Icon(CupertinoIcons.add, color: c.onSurface),
            )
          : null,
      child: list == null && error == null
          ? const Center(child: CupertinoActivityIndicator())
          : RefreshIndicator.adaptive(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 48),
                children: [
                  if (error != null || list!.isEmpty) ...[
                    const SizedBox(height: 40),
                    Icon(CupertinoIcons.lock_shield, size: 56, color: c.outline),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                      child: Text(
                        error != null ? serverErrorText(l, error is StateError ? null : error) : l.vaultEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: c.outline),
                      ),
                    ),
                    if (error == null)
                      Center(
                        child: TextButton(onPressed: add, child: Text(l.vaultAdd)),
                      ),
                  ] else
                    CupertinoListSection.insetGrouped(
                      backgroundColor: c.surface,
                      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                      separatorColor: c.outline.withValues(alpha: .2),
                      children: [
                        for (final i in list)
                          Dismissible(
                            key: ValueKey(i.id),
                            // a password manager's items are managed in that manager
                            direction: i.backend == 'local' ? DismissDirection.endToStart : DismissDirection.none,
                            confirmDismiss: (_) => confirmDelete(i),
                            onDismissed: (_) => setState(() => list.remove(i)),
                            background: Container(
                              color: const Color(0xFF9E1B1B),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(CupertinoIcons.trash, color: Colors.white),
                            ),
                            child: CupertinoListTile(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                              leading: SiteIcon(
                                i.origin,
                                fallback: Icon(switch (i.kind) {
                                  'payment' => CupertinoIcons.creditcard,
                                  'address' => CupertinoIcons.house,
                                  _ => CupertinoIcons.person_crop_circle,
                                }, color: c.onSurfaceVariant),
                              ),
                              title: Text(i.label, style: TextStyle(fontSize: 16, color: c.onSurface)),
                              subtitle: Text(
                                [
                                  if (i.identifier.isNotEmpty) i.identifier,
                                  if (i.origin.isNotEmpty) Uri.tryParse(i.origin)?.host ?? i.origin,
                                  if (i.backend != 'local') i.backend,
                                ].join(' · '),
                                style: small,
                              ),
                              additionalInfo: i.otp ? Text(l.vaultTwoFactor, style: small) : null,
                            ),
                          ),
                      ],
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(36, 8, 36, 0),
                    child: Text(l.vaultFooter, style: small),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Adds an account (a login) to the vault; pops true once stored.
class VaultAddPage extends StatefulWidget {
  const VaultAddPage({super.key});

  @override
  State<VaultAddPage> createState() => _VaultAddPageState();
}

class _VaultAddPageState extends State<VaultAddPage> {
  final label = TextEditingController(), site = TextEditingController(), identifier = TextEditingController();
  final password = TextEditingController(), otp = TextEditingController();
  var idType = 'email';
  var hidden = true;
  var saving = false;

  @override
  void initState() {
    super.initState();
    for (final f in [label, site, identifier, password]) {
      f.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final f in [label, site, identifier, password, otp]) {
      f.dispose();
    }
    super.dispose();
  }

  bool get complete => [label, site, identifier, password].every((f) => f.text.trim().isNotEmpty);

  Future<void> save() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => saving = true);
    try {
      final g = await gateway();
      if (g == null) throw StateError('no server');
      await g.call('vault.add', {
        'kind': 'login',
        'label': label.text.trim(),
        'origin': vaultOrigin(site.text),
        'secret': {
          'identifier_type': idType,
          'identifier': identifier.text.trim(),
          'password': password.text,
          if (otp.text.trim().isNotEmpty) 'otp_secret': otp.text.trim(),
        },
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Vault add: ${e is HttpException ? e.message : e.runtimeType}'); // the server scrubs secrets from its errors
      messenger.showSnackBar(SnackBar(content: Text(l.cronActionFailed(e is HttpException ? e.message : serverErrorText(l, null)))));
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    Widget field(
      String name,
      TextEditingController controller, {
      String? hint,
      bool secret = false,
      TextInputType? keyboard,
      Iterable<String>? autofill,
      Widget? trailing,
    }) => Padding(
      padding: EdgeInsets.fromLTRB(16, 10, trailing == null ? 16 : 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: small),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  obscureText: secret && hidden,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: keyboard,
                  autofillHints: autofill,
                  style: TextStyle(fontSize: 16, color: c.onSurface),
                  decoration: InputDecoration.collapsed(
                    hintText: hint,
                    hintStyle: TextStyle(fontSize: 16, color: c.outline.withValues(alpha: .6)),
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
    final eye = IconButton(
      tooltip: hidden ? AppLocalizations.of(context).a11yShow : AppLocalizations.of(context).a11yHide,
      onPressed: () => setState(() => hidden = !hidden),
      icon: Icon(hidden ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 20, color: c.outline),
    );
    Widget section(List<Widget> children, {String? footer}) => CupertinoListSection.insetGrouped(
      backgroundColor: c.surface,
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      separatorColor: c.outline.withValues(alpha: .2),
      footer: footer == null ? null : Text(footer, style: small),
      children: children,
    );
    return PageFrame(
      title: l.vaultAdd,
      action: saving
          ? const Padding(padding: EdgeInsets.all(14), child: CupertinoActivityIndicator())
          : TextButton(
              onPressed: complete ? save : null,
              child: Text(l.cronSave, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          section([
            field(l.vaultLabel, label, hint: l.vaultLabelHint),
            field(
              l.vaultSite,
              site,
              hint: 'github.com',
              keyboard: TextInputType.url,
              autofill: const [AutofillHints.url],
              trailing: Padding(
                padding: const EdgeInsets.only(left: 8, right: 12),
                child: SiteIcon(vaultOrigin(site.text), fallback: Icon(CupertinoIcons.globe, color: c.outline)),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: idType,
              onValueChanged: (v) => setState(() => idType = v ?? idType),
              children: {'email': Text(l.vaultEmail), 'phone': Text(l.vaultPhone), 'username': Text(l.vaultUsername)},
            ),
          ),
          // only the login in the group: the 2FA key is obscured too, and two obscured fields in one
          // group read to iOS as a new account's password + confirmation, so it offers to create one
          AutofillGroup(
            // the form only stores the password for Hermes: leaving it isn't a login for iOS to offer to save
            onDisposeAction: AutofillContextAction.cancel,
            child: section([
              field(
                switch (idType) {
                  'phone' => l.vaultPhone,
                  'username' => l.vaultUsername,
                  _ => l.vaultEmail,
                },
                identifier,
                keyboard: switch (idType) {
                  'phone' => TextInputType.phone,
                  'email' => TextInputType.emailAddress,
                  _ => TextInputType.text,
                },
                // username even for an email or phone: it's what pairs the login with the password for AutoFill
                autofill: const [AutofillHints.username],
              ),
              field(l.vaultPassword, password, secret: true, autofill: const [AutofillHints.password], trailing: eye),
            ]),
          ),
          section([field(l.vaultOtp, otp, hint: l.vaultOtpHint, secret: true)], footer: l.vaultOtpFooter),
        ],
      ),
    );
  }
}

/// The site's own icon, fetched from the site itself (nothing is asked of a third-party icon
/// service): its apple-touch-icon, else its favicon.ico, else [fallback].
class SiteIcon extends StatelessWidget {
  const SiteIcon(this.origin, {super.key, required this.fallback});

  final String origin;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(origin)?.host ?? '';
    if (!host.contains('.')) return fallback;
    Widget image(String file, Widget orElse) =>
        Image.network('https://$host/$file', width: 28, height: 28, fit: BoxFit.contain, errorBuilder: (_, _, _) => orElse);
    return SizedBox.square(
      dimension: 28,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: image('apple-touch-icon.png', image('favicon.ico', Center(child: fallback))),
      ),
    );
  }
}
