const assistantSpanish = <String, String>{
  'title': 'Asistente agrícola',
  'intro': 'Pregunte sobre evidencia agrícola. Las respuestas usan solo el contexto aportado.',
  'question': 'Haga una pregunta', 'send': 'Enviar', 'loading': 'Preparando una explicación…',
  'error': 'El asistente no está disponible. No se ha sustituido su evidencia. Inténtelo de nuevo.',
  'retry': 'Reintentar', 'expanded': 'Explicación ampliada', 'sources': 'Evidencia y fuentes',
  'detailsNote': 'Registros aportados: texto y enlaces no verificados de forma independiente.',
  'warnings': 'Faltan datos o necesitan revisión. Abra los detalles antes de usar estos resultados.',
  'retrieved_fact': 'Dato aportado', 'deterministic_calculation': 'Resultado de Rust aportado',
  'general_knowledge': 'Explicación general', 'unavailable_evidence': 'Desconocido o necesita revisión',
  'noSources': 'No se aportaron citas de fuentes.', 'unknown': 'Desconocido',
  'noFarm': 'Sin finca confirmada. Solo información general o regional.',
  'farm': 'Finca confirmada. Se conserva la cobertura de cada fuente.',
};
const assistantSpanishQuestions = <String>[
  '¿Qué pasa en mi zona?', '¿Qué significa el gráfico de lluvia?',
  '¿Por qué faltan datos del suelo?', '¿Qué cultivos podría investigar?',
  '¿Cuáles son las limitaciones?', '¿Qué significa esta observación satelital?',
  '¿Qué información debo aportar?',
];
