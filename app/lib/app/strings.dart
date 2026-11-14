/// All English UI text in one place so P3 can review wording.
/// Voice: short, plain words a farmer uses. No jargon. Sentence case.
abstract final class S {
  static const appName = 'Field Shift';

  // Welcome
  static const welcomeTitle = 'Plan your next crops with NASA data';
  static const how1 = 'Show us your field';
  static const how2 = 'Answer 3 quick questions';
  static const how3 = 'See which crops fit';
  static const welcomeDisclaimer = 'A guide to talk over with others. Not a guarantee.';
  static const getStarted = 'Start';

  // Location
  static const locationTitle = 'Your field';
  static const locationHint = 'Tap the map on your field';
  static const useMyLocation = "I'm at my field";
  static const findingYou = 'Finding you…';
  static const gpsOff = 'Turn on location to use this. You can also tap the map.';
  static const gpsDenied = 'Location not allowed. Tap the map instead.';
  static const gpsFailed = "Couldn't find your location. Tap the map instead.";
  static const useSampleField = 'Use a sample field';
  static const fieldMarked = 'Field marked';
  static const outsideMyanmar = 'This is outside Myanmar. Results may not fit.';
  static const continueLabel = 'Continue';
  static const back = 'Back';
  static const done = 'Done';
  static const recenter = 'Back to my field';

  // Questions (only what the engine uses)
  static String stepOf(int i, int n) => '$i of $n';
  static String stepSemantic(int i, int n) => 'Question $i of $n';
  static const dontKnow = "I don't know";
  static const qCurrentCrop = 'What do you grow now?';
  static const qIrrigation = 'Can you water your field?';
  static const qDrainage = 'After heavy rain, does water stay on the field?';
  static const next = 'Next';
  static const seeResults = 'See my results';

  // Tabs
  static const tabHome = 'Home';
  static const tabCrops = 'Crops';
  static const tabWeather = 'Weather';
  static const tabNotes = 'Notes';

  // Loading / errors
  static const preparing = 'Checking your field…';
  static const step1 = 'Reading NASA weather records';
  static const step2 = 'Checking crop facts';
  static const step3 = 'Comparing crop plans';
  static const errorTitle = "Couldn't check your field";
  static const retry = 'Try again';
  static const useDemo = 'Show demo instead';
  static const showLast = 'Show last result';
  static const notFound = "This plan isn't available any more.";

  // Home
  static const myField = 'My field';
  static const demoData = 'Demo data — not your real field';
  static const satellitePhoto = 'NASA satellite photo';
  static const openMap = 'Open map';
  static const cropPlans = 'Crop plans for your field';
  static const warnings = 'Watch out';
  static const yourAnswers = 'Your answers';
  static const location = 'Location';
  static const growNow = 'Growing now';
  static const water = 'Water';
  static const drainage = 'After rain';
  static const share = 'Share with an advisor';
  static const aboutResults = 'How we checked';
  static const startOver = 'Start over with a new field';
  static const startOverConfirm = 'Your answers will be cleared. Notes are kept.';
  static const cancel = 'Cancel';

  // Crops (one plan at a time)
  static const now = 'Now';
  static String plan(int n) => 'Plan $n';
  static const whatYouGrowNow = 'What you grow now';
  static String planLong(int n) => 'Other plan $n';
  static const when = 'When';
  static const good = 'Good things';
  static const watchOut = 'Watch out';
  static const dontKnowYet = "We don't know yet";
  static const whereFrom = 'Where this comes from';
  static const noneYet = 'Nothing confirmed yet.';
  static const noWarnings = 'Nothing flagged.';
  static const fitNote = 'Based on the crop facts we have. Not a guarantee.';
  static const windowUnknown = 'Months not known';

  // Status words (plain, still honest)
  static const supported = 'Fits';
  static const conflicts = 'Does not fit';
  static const constrained = 'Some problems';
  static const unknown = 'Not sure yet';
  static const riskHigh = 'High';
  static const riskMedium = 'Medium';
  static const riskLow = 'Low';
  static const riskNoData = 'Not sure';

  // About sheet
  static const notices = 'Important';
  static const dataGaps = 'Missing information';
  static const assumptions = 'What we assumed';

  // Weather
  static const mostRain = 'Most rain';
  static const leastRain = 'Least rain';
  static const hottest = 'Hottest';
  static const seasonRain = 'Total rain';
  static const avgTemp = 'Average heat';
  static const rainEachMonth = 'Rain each month';
  static const heatEachMonth = 'Heat each month';
  static const rain = 'Rain';
  static const heat = 'Heat';
  static const noData = 'No data';
  static const tapBar = 'Tap a month to see it.';
  static const gapNote = 'Grey means no data, not zero.';
  static String notMeasured(String kind) => 'These numbers are $kind, not measured.';

  // Map
  static const photo = 'Photo';
  static const plantHealth = 'Plant health';
  static const street = 'Street';
  static const aboutImage = 'About this image';
  static const lessGreen = 'Little green';
  static const moreGreen = 'Very green';
  static const imageryNote =
      'For looking only. Satellite images are not used in any calculation.';
  static const regionalNote = 'An estimate for your area, not your exact field.';

  // Notes (field diary)
  static const notesEmptyTitle = 'Your field diary';
  static const notesEmptyBody =
      'Write down what you see: pests, water, how crops grow. Notes stay on this phone.';
  static const addNote = 'Add note';
  static const newNote = 'New note';
  static const noteHint = 'What did you see?';
  static const save = 'Save';
  static const deleted = 'Note deleted';
  static const undo = 'Undo';
  static const kindPests = 'Pests';
  static const kindWater = 'Water';
  static const kindGrowth = 'Growth';
  static const kindWeather = 'Weather';
  static const kindOther = 'Other';

  // Sources
  static const sources = 'Sources';
  static const sourcesIntro =
      'Every result comes from one of these sources. Satellite numbers describe your area, not your exact field.';
  static const evidenceTypes = 'Kinds of source';
  static const sourcesUsed = 'Sources used';
  static const evidence = 'Source';
}
