class Msg {
  Msg(this.user, this.text);
  final bool user;
  String text;
}

typedef Model = ({String provider, String name, String desc, String id});

// ponytail: liste en dur, à remplacer par celle exposée par Hermes
const models = <Model>[
  (provider: 'Anthropic', name: 'Claude Opus 5.5', desc: 'Le plus puissant, raisonnement approfondi', id: 'anthropic/claude-opus-5-5'),
  (provider: 'Anthropic', name: 'Claude Sonnet 5.5', desc: 'Équilibre entre vitesse et qualité', id: 'anthropic/claude-sonnet-5-5'),
  (provider: 'Anthropic', name: 'Claude Haiku 5.5', desc: 'Rapide et léger', id: 'anthropic/claude-haiku-5-5'),
  (provider: 'OpenAI', name: 'GPT-5', desc: 'Modèle phare d’OpenAI', id: 'openai/gpt-5'),
  (provider: 'Google', name: 'Gemini 2.5 Pro', desc: 'Très long contexte, multimodal', id: 'google/gemini-2.5-pro'),
  (provider: 'Nous Research', name: 'Hermes 4 405B', desc: 'Open-weight, orienté agent', id: 'nousresearch/hermes-4-405b'),
  (provider: 'Local', name: 'Ollama', desc: 'Exécuté sur ta machine', id: 'ollama/default'),
];

Model modelOf(String id) => models.firstWhere((m) => m.id == id, orElse: () => models.first);

/// Point de branchement Hermes : reçoit l'historique, renvoie la réponse morceau par morceau.
// ponytail: réponse factice, remplacer par l'appel réseau à Hermes (SSE / websocket)
Stream<String> hermes(List<Msg> history, String model) async* {
  await Future.delayed(const Duration(milliseconds: 700));
  final reply =
      'Bien reçu (${modelOf(model).name}) : « ${history.last.text} ». Je ne suis pas encore branché, '
      'mais dès que Hermes sera connecté, ses réponses apparaîtront ici en continu, '
      'avec le même fondu progressif que pendant cette démonstration.';
  for (final word in reply.split(' ')) {
    await Future.delayed(const Duration(milliseconds: 45));
    yield '$word ';
  }
}
