const assistantEnglish = <String, String>{
  'title': 'Farm assistant',
  'intro':
      'Ask about your weather, soil, crops or satellite data. I’ll explain what the available information means.',
  'question': 'What would you like to know?',
  'send': 'Send',
  'loading': 'Preparing an explanation…',
  'error':
      'The assistant is unavailable. Your evidence has not been replaced. Try again.',
  'retry': 'Retry',
  'expanded': 'Explain in more detail',
  'sources': 'Evidence and sources',
  'detailsNote':
      'These are the records used for this answer. Check the dates and source coverage before using them for a field decision.',
  'warnings':
      'Some evidence is missing or needs review. Open details before using these results.',
  'retrieved_fact': 'Supplied fact',
  'deterministic_calculation': 'Supplied Rust result',
  'general_knowledge': 'General explanation',
  'unavailable_evidence': 'Unknown or needs review',
  'noSources': 'No source citations supplied.',
  'unknown': 'Unknown',
  'noFarm':
      'You’re exploring an area. Add your farm when you want to keep field records.',
  'farm':
      'Using your selected farm. Nearby weather stations and regional maps may differ from conditions in your field.',
};
const assistantEnglishQuestions = <String>[
  'What is happening in my area?',
  'How much rainfall did this area receive?',
  'What does the ET0 value mean?',
  'What would I need to estimate irrigation requirement?',
  'Why is this rotation in conflict?',
  'Why is soil information unavailable?',
  'What crops could I investigate?',
  'What are the limitations of this recommendation?',
  'What does this satellite observation mean?',
  'What information should I provide next?',
];
