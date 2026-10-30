class Msg {
  Msg(this.user, this.text);
  final bool user;
  String text;
}

/// Point de branchement Hermes : reçoit l'historique, renvoie la réponse morceau par morceau.
// ponytail: réponse factice, remplacer par l'appel réseau à Hermes (SSE / websocket)
Stream<String> hermes(List<Msg> history) async* {
  await Future.delayed(const Duration(milliseconds: 700));
  final reply = 'Bien reçu : « ${history.last.text} ». Je ne suis pas encore branché, '
      'mais dès que Hermes sera connecté, ses réponses apparaîtront ici en continu, '
      'avec le même fondu progressif que pendant cette démonstration.';
  for (final word in reply.split(' ')) {
    await Future.delayed(const Duration(milliseconds: 45));
    yield '$word ';
  }
}
