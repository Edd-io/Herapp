class Msg {
  Msg(this.user, this.text);
  final bool user;
  String text;
}

typedef Model = ({String provider, String name, String desc, String id});

// ponytail: hardcoded list, replace with the one exposed by Hermes
const models = <Model>[
  (provider: 'Anthropic', name: 'Claude Opus 5.5', desc: 'Most capable, deep reasoning', id: 'anthropic/claude-opus-5-5'),
  (provider: 'Anthropic', name: 'Claude Sonnet 5.5', desc: 'Balance of speed and quality', id: 'anthropic/claude-sonnet-5-5'),
  (provider: 'Anthropic', name: 'Claude Haiku 5.5', desc: 'Fast and lightweight', id: 'anthropic/claude-haiku-5-5'),
  (provider: 'OpenAI', name: 'GPT-5', desc: 'OpenAI flagship model', id: 'openai/gpt-5'),
  (provider: 'Google', name: 'Gemini 2.5 Pro', desc: 'Very long context, multimodal', id: 'google/gemini-2.5-pro'),
  (provider: 'Nous Research', name: 'Hermes 4 405B', desc: 'Open-weight, agent-oriented', id: 'nousresearch/hermes-4-405b'),
  (provider: 'Local', name: 'Ollama', desc: 'Runs on your machine', id: 'ollama/default'),
];

Model modelOf(String id) => models.firstWhere((m) => m.id == id, orElse: () => models.first);

/// Hermes hook-up point: takes the history, returns the reply chunk by chunk.
// ponytail: fake reply, replace with the network call to Hermes (SSE / websocket)
Stream<String> hermes(List<Msg> history, String model) async* {
  await Future.delayed(const Duration(milliseconds: 700));
  final reply =
      'Got it (${modelOf(model).name}): "${history.last.text}". I\'m not connected yet, '
      'but once Hermes is hooked up, its replies will stream in here '
      'with the same progressive fade as this demo.';
  for (final word in reply.split(' ')) {
    await Future.delayed(const Duration(milliseconds: 45));
    yield '$word ';
  }
}
