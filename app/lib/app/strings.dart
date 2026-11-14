/// All English UI text in one place so P3 can review wording.
abstract final class S {
  static const appName = 'EarthSync';

  // Welcome
  static const welcomeTitle = 'Plan your next crops with NASA data';
  static const welcomeBody =
      'Tell us about your field. We read NASA satellite climate records for '
      'your area and compare your current crops with two other rotation options.';
  static const howItWorks = 'How it works';
  static const how1 = 'Mark your field on the map';
  static const how2 = 'Answer 6 short questions';
  static const how3 = 'Compare your crops with 2 other options';
  static const welcomeDisclaimer =
      'This is a guide to discuss with other farmers or an extension officer. '
      'It is not a guarantee.';
  static const start = 'Start';

  // Location
  static const locationTitle = 'Where is your field?';
  static const locationHint = 'Tap the map to place your field.';
  static const useSampleField = 'Use sample field (Yangon)';
  static const next = 'Next';
  static const done = 'Done';
  static const reviewAnswers = 'Check my answers';
  static const back = 'Back';

  // Questionnaire
  static String stepOf(int i, int n) => 'Question $i of $n';
  static const dontKnow = "I don't know";
  static const qCurrentCrop = 'What do you grow now?';
  static const qRecentRotation = 'What did you grow before that?';
  static const qPlantingMonth = 'When do you usually plant?';
  static const qIrrigation = 'Can you water your field?';
  static const qDrainage = 'After heavy rain, does water stay on the field?';
  static const qPriorities = 'What matters most to you?';
  static const chooseAny = 'Choose any that apply.';

  // Review
  static const reviewTitle = 'Check your answers';
  static const analyze = 'See my options';
  static const edit = 'Change';
  static const notAnswered = "Don't know";

  // Analyzing
  static const analyzing = 'Reading NASA data for your field…';

  // Errors
  static const errorTitle = 'We could not get results';
  static const retry = 'Try again';
  static const useDemo = 'Use demo field';
  static const showLast = 'Show last saved result';

  // Results
  static const tabOverview = 'Overview';
  static const tabMap = 'Map';
  static const tabClimate = 'Climate';
  static const tabRotations = 'Rotations';
  static const atAGlance = 'Your 3 options at a glance';
  static const compareOptions = 'Compare options';
  static const recenter = 'Back to my field';
  static const showLegend = 'About this image';
  static const alerts = 'Warnings';
  static const noAlerts =
      'No hazard assessment is available. Risks remain unknown.';
  static const dataGaps = 'Missing data';
  static const assumptions = 'What we assumed';
  static const notices = 'Important to know';
  static const seasonSummary = 'Season summary';
  static const demoData = 'Demo data — not real results for your field.';
  static String savedData(String when) => 'Saved data from $when.';
  static const partialData =
      'Some data is missing. Parts marked "Unknown" could not be checked.';

  // Scenario
  static const yourPractice = 'Your current practice';
  static const option = 'Option';
  static const benefits = 'Possible benefits';
  static const risks = 'Risks';
  static const limitations = 'Limitations';
  static const evidence = 'Evidence';
  static const seeDetails = 'See details';
  static const sources = 'Sources and limits';

  // Feasibility / risk
  static const supported = 'Matches crop facts';
  static const conflicts = 'Conflicts with crop facts';
  static const constrained = 'Partly limited';
  static const unknown = 'Not enough information';
  static const riskHigh = 'High';
  static const riskMedium = 'Medium';
  static const riskLow = 'Low';
  static const riskNoData = 'Not enough data';

  // Map
  static const mapLayerUnavailable = 'Satellite image unavailable';
  static const mapNotConfigured =
      'Satellite layer not set yet. Waiting for layer ID from the data team.';
  static const imagery = 'Imagery';

  // Climate
  static const rainfall = 'Rainfall';
  static const temperature = 'Temperature';
  static const noData = 'No data';
}
