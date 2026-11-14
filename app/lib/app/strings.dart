/// All English UI text in one place so P3 can review wording.
/// Voice: very short, plain words a farmer uses. No jargon. Sentence case.
abstract final class S {
  static const appName = 'Field Shift';

  // Welcome
  static const welcomeTitle = 'Which crop fits your farm next?';
  static const how1 = 'Pin your farm';
  static const how2 = 'Answer 3 questions';
  static const how3 = 'See which crops fit';
  static const welcomeDisclaimer =
      'A guide to talk over with others. Not a guarantee.';
  static const getStarted = 'Start';

  // Location (setup: one pin only)
  static const locationTitle = 'Where is your farm?';
  static const locationHint = 'Tap your farm on the map';
  static const useMyLocation = "I'm at my farm";
  static const findingYou = 'Finding you…';
  static const gpsOff = 'Turn on location, or tap the map.';
  static const gpsDenied = 'Location not allowed. Tap the map instead.';
  static const gpsFailed = "Couldn't find you. Tap the map instead.";
  static const useSampleField = 'Use a sample farm';
  static const fieldMarked = 'Farm pinned';
  static const pinLater = 'Later you can mark the whole farm on the Field tab.';
  static const outsideMyanmar = 'This is outside Myanmar. Results may not fit.';
  static const continueLabel = 'Continue';
  static const back = 'Back';
  static const done = 'Done';
  static const recenter = 'Back to my farm';

  // Questions (only what the engine uses)
  static String stepOf(int i, int n) => '$i of $n';
  static String stepSemantic(int i, int n) => 'Question $i of $n';
  static const dontKnow = 'Not sure';
  static const qCurrentCrop = 'What do you grow now?';
  static const qIrrigation = 'How do you water your farm?';
  static const qDrainage = 'After heavy rain, the water…';
  static const waterRain = 'Only rain';
  static const waterSome = 'Sometimes';
  static const waterAll = 'All year';
  static const drainFast = 'Dries fast';
  static const drainDays = 'Stays 1–2 days';
  static const drainLong = 'Stays many days';
  static const next = 'Next';
  static const seeResults = 'See my crops';

  // Tabs
  static const tabCrops = 'Crops';
  static const tabWeather = 'Weather';
  static const tabField = 'Field';
  static const tabNotes = 'Notes';

  // Loading / errors
  static const preparing = 'Checking your farm…';
  static const step1 = 'Reading NASA weather records';
  static const step2 = 'Checking crop facts';
  static const step3 = 'Comparing crops';
  static const errorTitle = "Couldn't check your farm";
  static const retry = 'Try again';
  static const useDemo = 'Show demo instead';
  static const showLast = 'Showing your last result';
  static const notFound = "This crop plan isn't available any more.";
  static const demoData = 'Practice data — not your real farm yet';

  // Crops tab
  static const nextSeason = 'Next season';
  static const bestFirst = 'Best fit first';
  static const tapForWhy = 'Tap a card to see why';
  static const whatYouGrowNow = 'What you grow now';
  static const then = 'then';
  static const whyGood = 'Why it fits';
  static const watchOut = 'Watch out';
  static const dontKnowYet = "We don't know yet";
  static const when = 'When';
  static const moreDetails = 'More details';
  static const whereFrom = 'Where this comes from';
  static const noneYet = 'Nothing confirmed yet.';
  static const fitNote = 'Based on the crop facts we have. Not a guarantee.';
  static const windowUnknown = 'Months not known';
  static String planLong(int n) => 'Other plan $n';

  // Fit words (traffic light, always with an icon too)
  static const supported = 'Good fit';
  static const constrained = 'Careful';
  static const conflicts = 'Poor fit';
  static const unknown = 'Not sure';
  static const riskHigh = 'High';
  static const riskMedium = 'Medium';
  static const riskLow = 'Low';
  static const riskNoData = 'Not sure';

  // Weather tab
  static const mostRain = 'Most rain';
  static const leastRain = 'Least rain';
  static const hottest = 'Hottest';
  static const tapMonth = 'Tap a month for numbers';
  static const rain = 'Rain';
  static const heat = 'Heat';
  static const noData = 'No data';
  static const noDataMonth = 'No data for this month';
  static String notMeasured(String kind) =>
      'These numbers are $kind, not measured.';

  // Field tab
  static const myFarm = 'My farm';
  static const markFarm = 'Mark your farm';
  static const markFarmBody = 'Pin the 4 corners so we check only your farm.';
  static const editFarm = 'Change farm shape';
  static const farmSize = 'Farm size';
  static const showPlantHealth = 'Show plant health';
  static const yourAnswers = 'Your answers';
  static const location = 'Farm pin';
  static const growNow = 'Growing now';
  static const water = 'Water';
  static const drainage = 'After rain';
  static const share = 'Send to a helper';
  static const aboutResults = 'About this data';
  static const sources = 'Sources';
  static const startOver = 'Start over';
  static const startOverConfirm =
      'Your farm and answers will be cleared. Notes are kept.';
  static const cancel = 'Cancel';
  static const farmNote =
      'Crops and weather are checked at the middle of your farm. NASA weather describes the wider area around it.';

  // Mark-the-farm screen (4 corner pins)
  static String cornerOf(int i) => 'Corner $i of 4';
  static const cornerHint =
      "Walk to a corner and tap \"I'm at this corner\". Or tap the map.";
  static const atCorner = "I'm at this corner";
  static const undo = 'Undo';
  static const clear = 'Start again';
  static const saveFarm = 'Save farm';
  static const allCorners = 'All 4 corners pinned';
  static const farmSaved = 'Farm saved. Checking your farm again.';

  // About sheet
  static const notices = 'Important';
  static const dataGaps = 'Missing information';
  static const assumptions = 'What we assumed';

  // Map
  static const photo = 'Photo';
  static const plantHealth = 'Plant health';
  static const street = 'Street';
  static const aboutImage = 'About this image';
  static const lessGreen = 'Little green';
  static const moreGreen = 'Very green';
  static const imageryNote =
      'For looking only. Satellite images are not used in any calculation.';
  static const pixelNote =
      'Each NASA plant-health square is about 250 m wide, so small farms share a square with their neighbours.';

  // Notes (field diary)
  static const notesTitle = 'What did you see?';
  static const yourNotes = 'Your notes';
  static const notesEmptyBody = 'Tap what you saw. Notes stay on this phone.';
  static const addNote = 'Add note';
  static const newNote = 'New note';
  static const noteHint = 'Write a few words (you can skip this)';
  static const save = 'Save';
  static const deleted = 'Note deleted';
  static const kindPests = 'Pests';
  static const kindWater = 'Water';
  static const kindGrowth = 'Growth';
  static const kindWeather = 'Weather';
  static const kindOther = 'Other';

  // Live NASA data (team integration)
  static const provenanceHeader = 'Where the weather comes from';
  static const cropsUnknownTitle = 'Crop fit not known yet';
  static const cropsUnknownBody =
      'Your weather is real NASA data. Crop facts for your area are not added yet, so we will not guess which crop fits.';
  static const weatherMonths = 'Weather months';
  static const last12 = 'Use the last 12 months';
  static const traceBackend = 'Exact backend response and provenance';
  static const traceFarmer = 'Retained farmer answers (not all used by Rust)';

  // Google account (Firebase)
  static const signInTitle = 'Keep your farm safe';
  static const signInBody =
      'Sign in with Google. Your farm, answers, notes and results are saved to your account, so you can open them on a new phone.';
  static const signInGoogle = 'Continue with Google';
  static const notNow = 'Not now';
  static const signInFailed =
      "Couldn't sign in. Check the internet and try again.";
  static const cloudUnavailable =
      'Online saving is not set up in this version.';
  static const account = 'Google account';
  static const saveOnline = 'Save to Google account';
  static const savedOnline = 'Saved online';
  static const signOut = 'Sign out';

  // Sources
  static const sourcesIntro =
      'Every result comes from one of these sources. Satellite numbers describe your area, not your exact farm.';
  static const evidenceTypes = 'Kinds of source';
  static const sourcesUsed = 'Sources used';
  static const evidence = 'Source';
}
