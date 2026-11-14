/// All English UI text in one place so P3 can review wording.
/// Voice: plain, calm, sentence case, verb-first buttons, no "please".
abstract final class S {
  static const appName = 'Field Shift';

  // Welcome
  static const welcomeTitle = 'Plan your next season with NASA data';
  static const how1Title = 'Mark your field';
  static const how1Body = 'Tap the map or use a sample field.';
  static const how2Title = 'Answer 6 questions';
  static const how2Body = 'One tap each. "I don\'t know" is always fine.';
  static const how3Title = 'Compare 3 options';
  static const how3Body =
      'Your current crops and two others, with evidence and limits.';
  static const welcomeDisclaimer =
      'A guide to discuss with others — not a guarantee.';
  static const getStarted = 'Get started';

  // Location
  static const locationTitle = 'Where is your field?';
  static const locationHint = 'Tap the map to mark your field.';
  static const fieldMarked = 'Field marked';
  static const useSampleField = 'Use sample field';
  static const outsideMyanmar = 'Outside Myanmar — results may not fit.';
  static const continueLabel = 'Continue';
  static const back = 'Back';
  static const done = 'Done';
  static const recenter = 'Back to my field';

  // Questionnaire
  static String stepOf(int i, int n) => '$i of $n';
  static String stepSemantic(int i, int n) => 'Question $i of $n';
  static const dontKnow = "I don't know";
  static const notSure = 'Not sure?';
  static const qCurrentCrop = 'What do you grow now?';
  static const qRecentRotation = 'What did you grow before that?';
  static const qPlantingMonth = 'When do you usually plant?';
  static const qIrrigation = 'Can you water your field?';
  static const qDrainage = 'After heavy rain, does water stay on the field?';
  static const qPriorities = 'What matters most to you?';
  static const chooseAny = 'Choose any that apply.';
  static const crops = 'Crops';
  static const months = 'Month';
  static const next = 'Next';
  static const reviewAnswers = 'Review answers';

  // Review
  static const reviewTitle = 'Review';
  static const reviewFooter = 'Your answers stay on this phone.';
  static const analyze = 'See my options';
  static const notAnswered = "Don't know";

  // Analyzing
  static const analyzingTitle = 'Preparing your options';
  static const step1 = 'Reading climate records';
  static const step2 = 'Checking crop facts';
  static const step3 = 'Comparing rotations';

  // Errors
  static const errorTitle = "Couldn't prepare your options";
  static const retry = 'Try again';
  static const useDemo = 'Use demo field';
  static const showLast = 'Show last result';
  static const notFound = "This option isn't available any more.";

  // Results — tabs
  static const tabOverview = 'Overview';
  static const tabMap = 'Map';
  static const tabClimate = 'Climate';
  static const tabCompare = 'Compare';

  // Overview
  static const yourOptions = 'Your options';
  static const rotations = 'Rotations';
  static const compareSideBySide = 'Compare side by side';
  static const warnings = 'Warnings';
  static const aboutResults = 'About these results';
  static const aboutResultsSub = 'Notes, missing data and assumptions';
  static const demoData = 'Demo data — not your real field';
  static String missingCount(int n) =>
      n == 1 ? '1 detail missing' : '$n details missing';
  static String savedData(String when) => 'Saved result from $when';
  static const seasonRain = 'Season rain';
  static const avgTemp = 'Avg temperature';

  // Scenario
  static const yourPractice = 'Your current practice';
  static const current = 'Current';
  static String option(int n) => 'Option $n';
  static const benefits = 'Possible benefits';
  static const risks = 'Risks';
  static const limitations = 'Limits';
  static const evidence = 'Evidence';
  static const timeline = 'Season plan';
  static const windowUnknown = 'Planting window unknown';
  static const noBenefits = 'No benefits confirmed yet.';
  static const noRisks = 'No risks flagged.';

  // Status labels (engine wording kept honest)
  static const supported = 'Matches crop facts';
  static const conflicts = 'Conflicts with crop facts';
  static const constrained = 'Partly limited';
  static const unknown = 'Not enough information';
  static const riskHigh = 'High';
  static const riskMedium = 'Medium';
  static const riskLow = 'Low';
  static const riskNoData = 'Not enough data';

  // About sheet
  static const notices = 'Important to know';
  static const dataGaps = 'Missing data';
  static const assumptions = 'What we assumed';

  // Map
  static const satellite = 'Satellite';
  static const street = 'Street';
  static const aboutImage = 'About this image';
  static const imageryNote =
      'Satellite photo for context only. It is not used in any calculation.';
  static const regionalNote =
      'Regional estimate — not a measurement of your exact field.';

  // Climate
  static const rainfall = 'Rain';
  static const temperature = 'Temperature';
  static const noData = 'No data';
  static const gapNote = 'Gaps mean missing data, not zero.';
  static const tapBar = 'Tap a month to see its value.';

  // Sources
  static const sources = 'Sources';
  static const sourcesIntro =
      'Every result comes from one of these sources. Satellite grids and models describe your region, not your exact plot.';
  static const evidenceTypes = 'Evidence types';
  static const sourcesUsed = 'Sources used';
}
