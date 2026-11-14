import 'en.dart';
import 'es.dart';

class AssistantStrings {
  const AssistantStrings(this.language);
  final String language;
  String call(String key) =>
      (language == 'es' ? assistantSpanish : assistantEnglish)[key] ?? key;
  List<String> get questions =>
      language == 'es' ? assistantSpanishQuestions : assistantEnglishQuestions;
}
