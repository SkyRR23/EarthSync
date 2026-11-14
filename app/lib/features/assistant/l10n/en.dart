const assistantEnglish = <String, String>{
  'title': 'Farm assistant',
  'intro': 'Ask about agricultural evidence. Answers use only the context provided.',
  'question': 'Ask a question', 'send': 'Send', 'loading': 'Preparing an explanation…',
  'error': 'The assistant is unavailable. Your evidence has not been replaced. Try again.',
  'retry': 'Retry', 'expanded': 'Expanded explanation', 'sources': 'Evidence and sources',
  'detailsNote': 'Supplied records — text and links are not independently verified.',
  'warnings': 'Some evidence is missing or needs review. Open details before using these results.',
  'retrieved_fact': 'Supplied fact', 'deterministic_calculation': 'Supplied Rust result',
  'general_knowledge': 'General explanation', 'unavailable_evidence': 'Unknown or needs review',
  'noSources': 'No source citations supplied.', 'unknown': 'Unknown',
  'noFarm': 'No confirmed farm. General or regional information only.',
  'farm': 'Farm confirmed. Source coverage still applies.',
};
const assistantEnglishQuestions = <String>[
  'What is happening in my area?', 'What does the rainfall graph mean?',
  'Why is soil information unavailable?', 'What crops could I investigate?',
  'What are the limitations of this recommendation?',
  'What does this satellite observation mean?', 'What information should I provide next?',
];
