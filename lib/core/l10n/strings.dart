import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Minimal English/French strings. Move to ARB files + `flutter gen-l10n`
/// once the copy is reviewed by the Nchemty team.
class S {
  S(this.lang);
  final String lang;

  static const supported = [Locale('en'), Locale('fr')];

  static const _t = <String, Map<String, String>>{
    'welcomeBack': {'en': 'Welcome back', 'fr': 'Bon retour'},
    'enterPin': {'en': 'Enter your PIN', 'fr': 'Saisissez votre code'},
    'createPin': {'en': 'Create a 4-digit PIN', 'fr': 'Créez un code à 4 chiffres'},
    'confirmPin': {'en': 'Confirm your PIN', 'fr': 'Confirmez votre code'},
    'pinMismatch': {'en': 'PINs do not match', 'fr': 'Les codes ne correspondent pas'},
    'wrongPin': {'en': 'Wrong PIN', 'fr': 'Code incorrect'},
    'usePassword': {'en': 'Sign in with username and password', 'fr': 'Se connecter avec identifiant et mot de passe'},
    'username': {'en': 'Username or phone', 'fr': 'Identifiant ou téléphone'},
    'password': {'en': 'Password', 'fr': 'Mot de passe'},
    'signIn': {'en': 'Sign in', 'fr': 'Se connecter'},
    'available': {'en': 'Available balance', 'fr': 'Solde disponible'},
    'accounts': {'en': 'Your accounts', 'fr': 'Vos comptes'},
    'recent': {'en': 'Recent activity', 'fr': 'Activité récente'},
    'seeAll': {'en': 'See all', 'fr': 'Tout voir'},
    'send': {'en': 'Send', 'fr': 'Envoyer'},
    'topUp': {'en': 'Top up', 'fr': 'Recharger'},
    'cashOut': {'en': 'Cash out', 'fr': 'Retrait'},
    'loans': {'en': 'Loans', 'fr': 'Prêts'},
    'history': {'en': 'History', 'fr': 'Historique'},
    'sendMoney': {'en': 'Send money', 'fr': 'Envoyer de l\'argent'},
    'recipient': {'en': 'Phone, account number or username', 'fr': 'Téléphone, numéro de compte ou identifiant'},
    'amount': {'en': 'Amount (XAF)', 'fr': 'Montant (XAF)'},
    'note': {'en': 'Note (optional)', 'fr': 'Motif (facultatif)'},
    'continue': {'en': 'Continue', 'fr': 'Continuer'},
    'confirm': {'en': 'Confirm', 'fr': 'Confirmer'},
    'fee': {'en': 'Fee', 'fr': 'Frais'},
    'total': {'en': 'Total debited', 'fr': 'Total débité'},
    'txPin': {'en': 'Transaction PIN', 'fr': 'Code de transaction'},
    'done': {'en': 'Done', 'fr': 'Terminé'},
    'success': {'en': 'Payment sent', 'fr': 'Paiement effectué'},
    'approvePrompt': {'en': 'Approve the MTN prompt on your phone', 'fr': 'Validez la demande MTN sur votre téléphone'},
    'loansSavings': {'en': 'Loans and savings', 'fr': 'Prêts et épargne'},
    'verifyId': {'en': 'Verify your identity', 'fr': 'Vérifiez votre identité'},
    'logout': {'en': 'Sign out', 'fr': 'Se déconnecter'},
    'retry': {'en': 'Try again', 'fr': 'Réessayer'},
  };

  String t(String key) => _t[key]?[lang] ?? _t[key]?['en'] ?? key;

  /// Use in build methods (rebuilds on language change).
  static S of(WidgetRef ref) => S(ref.watch(localeProvider).languageCode);

  /// Use in callbacks / async handlers, where `ref.watch` must not be called.
  static S read(WidgetRef ref) => S(ref.read(localeProvider).languageCode);
}

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale('en');
  void set(Locale l) => state = l;
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
