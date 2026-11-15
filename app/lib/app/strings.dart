/// All English UI text in one place so P3 can review wording.
/// Voice: very short, plain words a farmer uses. No jargon. Sentence case.
abstract final class S {
  static const appName = 'EarthSync';

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
  static const tabToday = 'Today';
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
  static String savedResult(String when) => 'Saved result from $when';
  static const updating = 'Checking for new data…';
  static const noInternet = "No internet right now. Tap to try again.";
  static const notFound = "This crop plan isn't available any more.";
  static const demoData = 'Practice data — not your real farm yet';
  static const noFarmTitle = 'Pin your farm first';
  static const noFarmBody =
      'We need to know where your farm is before we can check crops and weather.';
  static const pinMyFarm = 'Pin my farm';

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
  static String cornerTooFar(String km) =>
      'That spot is $km km from your other corners, so it was not added. Walk to the farm corner and try again, or tap the map.';

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
      'Not live: NASA builds this picture from 8 days of satellite passes. Each square is about 250 m wide, so a small farm is often one colour.';
  static const plantHealthNewest = 'NASA 8-day image, newest';
  static const insideFarmOnly = 'Colour is shown inside your farm border only.';
  static const markFarmForHealth =
      'Mark your farm to see plant health inside it.';

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
  static const kindSoil = 'Soil';
  static const takePhoto = 'Take photo';
  static const choosePhoto = 'Choose photo';
  static const removePhoto = 'Remove photo';
  static const photoInCloud = 'Photo saved online';

  // Soil check: 2 photos + hand test, checked by AI on the backend
  static const soilTitle = 'Check your soil';
  static const soilCard = 'Take 2 photos and feel your soil. About 1 minute.';
  static const soil = 'Soil';
  static const soilNotChecked = 'Not checked';
  static const soilIntroTitle = 'Get your soil ready';
  static const soilIntro1 = 'Dig a handful of soil from 10 cm deep.';
  static const soilIntro2 = 'Remove stones and roots.';
  static const soilIntro3 =
      'Add water little by little until it feels like soft putty.';
  static const start = 'Start';
  static const photoGroundTitle = 'Photo 1: your soil';
  static const photoGroundHint =
      'Take a photo of the soil on the ground, in daylight, close up.';
  static const photoSqueezeTitle = 'Photo 2: squeeze it';
  static const photoSqueezeHint =
      'Squeeze the wet soil in your hand, open your hand, and take a photo.';
  static const skipPhoto = 'Skip photo';
  static const retakePhoto = 'Take again';
  static const qRibbon = 'Push it out between thumb and finger. What happens?';
  static const ribbonFallsApart = 'Falls apart';
  static const ribbonNone = 'Ball, no ribbon';
  static const ribbonShort = 'Short (under 2.5 cm)';
  static const ribbonMedium = 'Medium (2.5–5 cm)';
  static const ribbonLong = 'Long (over 5 cm)';
  static const qFeel = 'Rub a little wet soil. How does it feel?';
  static const feelGritty = 'Gritty';
  static const feelSmooth = 'Smooth like flour';
  static const feelSticky = 'Sticky';
  static const qSigns = 'What do you see in your field?';
  static const signsHint = 'Tap all that you see, then Next.';
  static const signCracks = 'Cracks when dry';
  static const signWhiteCrust = 'White crust';
  static const signGreySpots = 'Grey or blue spots';
  static const signStones = 'Many stones';
  static const signDarkTopsoil = 'Dark top soil';
  static const signWaterlogged = 'Water stays on top';
  static const signRootsOrWorms = 'Roots or worms';
  static const checkingSoil = 'Checking your soil…';
  static const soilResult = 'Your soil';
  static const soilFromAi =
      'AI estimate from your photos and answers. Not a lab test.';
  static const soilFromHands = 'From your hand test. Not a lab test.';
  static const soilAiFailed =
      "The photo check didn't work right now, so this is from your hand test.";
  static const soilAiUnsure =
      'The photos were not clear enough, so this is from your hand test.';
  static const soilUnsure =
      "We can't tell yet. Try again with a clearer photo, or ask a helper.";
  static String confidenceLabel(String c) => switch (c) {
    'high' => 'High confidence',
    'medium' => 'Medium confidence',
    _ => 'Low confidence',
  };
  static String handTestSaid(String label) => 'Your hand test said: $label';
  static const signsSeen = 'Signs';
  static const aiShort = 'AI';
  static const saveSoil = 'Save';
  static String soilNote(String label) => 'Soil check: $label';
  static const squeezedSoilNote = 'Squeezed soil';

  // Live NASA data (team integration)
  static const provenanceHeader = 'Where the weather comes from';
  static const cropsUnknownTitle = 'Crop fit not known yet';
  static const cropsUnknownBody =
      'Your weather is real NASA data. Crop facts for your area are not added yet, so we will not guess which crop fits.';
  static const weatherMonths = 'Weather months';
  static const last12 = 'Use last year (Jan–Dec)';
  static const weatherFrom = 'From';
  static const weatherTo = 'To';
  static const weatherMonthsHelp = 'Finished months only, up to 2 years.';
  static const weatherMonthsBad =
      '"To" must be after "From", and 24 months at most. Not changed yet.';
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

  // Your data (privacy + delete)
  static const yourData = 'Your data';
  static const dataPhoneTitle = 'Kept on this phone';
  static const dataPhoneBody =
      'Your farm pin and shape, your answers, your notes and photos, and your last result.';
  static const dataOnlineTitle = 'Saved online when you sign in';
  static const dataOnlineBody =
      'The same farm, answers, notes, photos and every check result, in Google Firebase (Singapore). Only you can open them.';
  static const dataCountsTitle = 'Counts with no name';
  static const dataCountsBody =
      'Simple counts like "a check was run", with no name, place or notes.';
  static const dataWeatherTitle = 'Weather server';
  static const dataWeatherBody =
      "To get NASA weather, the app sends your farm's location to our server. Its short technical logs are not linked to your account.";
  static const dataNeverTitle = 'Never';
  static const dataNeverBody =
      'No ads and no selling of data. The app never measures anything from your photos.';
  static const deleteAll = 'Delete all my data';
  static const deleteFooter =
      'Deletes everything on this phone and, if you signed in, everything online and your EarthSync account. It cannot be undone.';
  static const deleteConfirmTitle = 'Delete everything?';
  static String deleteConfirmBody({required bool signedIn}) => signedIn
      ? 'Your farm, answers, notes, photos and results will be deleted from this phone and from your online space, and your EarthSync account will be closed. This cannot be undone.'
      : 'Your farm, answers, notes, photos and results will be deleted from this phone. This cannot be undone.';
  static const deleteWord = 'Delete';
  static const allDeleted = 'All your data was deleted.';
  static const deleteFailed =
      "Couldn't finish deleting your online data. Check the internet and try again. Your phone copy was kept.";

  // Sources
  static const sourcesIntro =
      'Every result comes from one of these sources. Satellite numbers describe your area, not your exact farm.';
  static const evidenceTypes = 'Kinds of source';
  static const sourcesUsed = 'Sources used';
  static const evidence = 'Source';
  // Today tab (tasks)
  static const today = 'today';
  static const yesterday = 'yesterday';
  static String daysAgo(int n) => '$n days ago';
  static const todayEmpty = 'Nothing to do right now.';
  static const doneHeader = 'Done';
  static const todayFooter =
      'Advice uses NASA data for about 50 km around your farm and your own answers. It is a guide: your eyes and hands decide.';
  static const recentLoading = 'Getting the latest NASA data…';
  static String recentOld(String date) =>
      'No connection. Showing NASA data saved on $date.';
  static const recentFailed =
      'Could not get NASA data right now. The tasks use your own records.';
  static String nasaRecentSource(String date) =>
      'NASA POWER, modeled, up to $date (NASA is a few days behind).';
  // Water
  static const waterMayNeed = 'Your field may need water';
  static const waterCheck = 'Check if your field needs water';
  static const waterCanWait = 'Water: you can likely wait';
  static const waterNoData = 'We can’t see recent rain right now.';
  static const rainWeekUnknown = 'Rain in the last 7 days: not known.';
  static String rainWeek(int mm, String? compared) =>
      '$mm mm of rain in the last 7 days${compared == null ? '' : ', $compared'}.';
  static const lessThanUsual = 'less than usual here for this time of year';
  static const moreThanUsual = 'more than usual here for this time of year';
  static const aboutUsual = 'about usual here for this time of year';
  static const wetnessDrier =
      'Soil deep down is drier than usual for this time of year.';
  static const wetnessWetter =
      'Soil deep down is wetter than usual for this time of year.';
  static const wetnessUsual =
      'Soil deep down is about as wet as usual for this time of year.';
  static const sandyDries = 'Your sandy soil dries out fast.';
  static const clayHolds = 'Your clay soil holds water longer.';
  static const noWateringYet = 'No watering saved yet.';
  static String lastWatered(String ago) => 'Last watered: $ago.';
  static const feelFirst =
      'Feel the soil a finger deep. Water only if it is dry.';
  static const iWatered = 'I watered today';
  static const stillWet = 'Soil is still wet';
  static const wateredToday = 'Watered today';
  static const soilStillWetToday = 'Soil still wet today: no water needed';
  // Heavy rain
  static const heavyTitle = 'Check for standing water';
  static const heavyChecked = 'Checked for standing water';
  static String heavyFact(String date, int mm, int percent) =>
      'Heavy rain on $date: $mm mm, heavier than $percent% of days here at this time of year.';
  static const heavyYouSaid = 'You said water stays on your field after rain.';
  static const heavyLowParts = 'Water can stay on low parts of a field.';
  static const heavyWalk =
      'Walk the field and look for water standing around the plants.';
  static const checked = 'Checked';
  // Soil
  static const soilTaskNew =
      'Not checked yet. It makes the water advice better.';
  static const soilAgainTitle = 'Check your soil again';
  static String soilTaskOld(String date) =>
      'Last checked on $date. Soil changes with the seasons.';
  static const soilChecked = 'Soil checked';
  static String soilCheckedOn(String date) => 'Soil checked on $date';
  static const startSoilCheck = 'Start soil check';
  // Photo
  static const photoTitle = 'Crop photo this week';
  static const photoNone = 'No crop photos yet. Photos show change over time.';
  static String photoOld(int days) =>
      'Last photo $days days ago. Photos show change over time.';
  static String photoDone(String ago) => 'Crop photo taken $ago';
  static const cropPhotoNote = 'Crop photo';
  // Home (team design)
  static const goodMorning = 'Good morning';
  static const goodAfternoon = 'Good afternoon';
  static const goodEvening = 'Good evening';
  static const homeSubtitle = 'Here’s how your farm is doing';
  static const savedPhone = 'Saved on this phone';
  static const savedGoogle = 'Saved to your Google account';
  static String cropField(String crop) => '$crop field';
  static const yourFarm = 'Your farm';
  static String toDoToday(int n) =>
      n == 1 ? '1 thing to do today' : '$n things to do today';
  static const allDoneToday = 'All done for today';
  static String doneOf(int done, int total) => '$done of $total done today';
  static const growingNow = 'Growing now';
  static const nextCheck = 'Next check';
  static const nothingDue = 'Nothing due';
  static const notAnswered = 'Not answered';
  static const yourFields = 'Your fields';
  static const needsALook = 'Needs a look';
  static const allDone = 'All done';
  static String nToDo(int n) => '$n to do';
  static const checkMyCrops = 'Check my crops';
  static const todayTasks = 'Today';
  static const notifications = 'Things to do';
  // Task short names (for "Next check")
  static const shortWater = 'Water check';
  static const shortHeavy = 'Standing water';
  static const shortSoil = 'Soil check';
  static const shortPhoto = 'Crop photo';
  // Field (team design)
  static const yourFieldsTitle = 'Your fields';
  static const viewFieldDetails = 'View field details';
  static const fieldDetails = 'Field details';
  static const plantHealthChip = 'Plant health';
  static const onTrack = 'On track';
  static const centerFarm = 'Show my farm';
  static String cropAndSize(String crop, String size) => '$crop · $size';
  static const tasksLabel = 'Tasks';
  static const notMarkedYet = 'Corners not marked yet';
  // Weather (team design)
  static const weatherTitle = 'Weather for your farm';
  static String feelsLike(int c) => 'Feels like $c°';
  static const forecast5 = '5-Day Forecast';
  static const todayShort = 'Today';
  static const rainfall = 'Rainfall';
  static const wind = 'Wind';
  static String aboutMm(num mm) => '~ ${mm.round()} mm';
  static String kmh(num v) => '${v.round()} km/h';
  static const forecastNote =
      'Forecast by Open-Meteo · Not a local sensor reading';
  static const rainTomorrow = 'Rain expected tomorrow';
  static String rainTomorrowBody(int mm, int? chance) =>
      'About $mm mm${chance == null ? '' : ', $chance% chance'}. Plan field work around it.';
  static const noRainToday = 'No rain expected today.';
  static String rainToday(int mm) => 'Rain likely today: about $mm mm.';
  static String rainChanceToday(int chance) =>
      'Some chance of rain today ($chance%).';
  static const forecastLoading = 'Getting the forecast…';
  static const forecastFailed =
      'Could not get the forecast right now. Check your connection.';
  static String forecastOld(String time) =>
      'No connection. Forecast from $time.';
  static const nasaLast7 = 'Last 7 days · NASA';
  static const nasaPastYear = 'Past year · NASA';
  static const seeMonths = 'See every month';
  static const pastYearBody =
      'Rain and heat for each month of the past year at your farm, from NASA.';
  static const nasaNotYet = 'NASA data is not here yet.';
  // Screen colours (Field details)
  static const screenColours = 'Screen';
  static const lightMode = 'Light';
  static const darkMode = 'Dark';
  static const phoneMode = 'Phone';
  static const screenColoursNote =
      'Light is easiest to read outside. Phone follows your phone setting.';
  // Engine ET0 (FAO-56 grass reference) in the water task
  static String et0Week(int mm, String? vsRain) =>
      'A grass field lost about $mm mm of water to sun and wind in these 7 days${vsRain == null ? '' : ', $vsRain'}.';
  static const lessThanRain = 'less than the rain';
  static const moreThanRain = 'more than the rain';
  static String et0Partial(int mm, int days, int of) =>
      'A grass field lost about $mm mm of water to sun and wind in $days of these $of days (NASA sunlight data for the rest is not in yet).';
  static const et0Source = 'Water loss: FAO-56, team engine.';
  // NASA HLS greenness (Field map, plant health on)
  static String greenNow(String v, String date) => 'Green cover $v on $date';
  static String greenBefore(String v, String date) => '$v on $date';
  static String greenPixels(int clear, int inside, String sensor) =>
      '$clear of $inside pixels clear · $sensor, NASA HLS 30 m';
  static const greenScale = '0 = bare soil, 1 = dense green';
  static const greenLoading = 'Getting NASA HLS images…';
  static const greenNone =
      'No clear NASA HLS image of your farm in the last 75 days. Showing the coarser MODIS layer.';
  static const greenFailed =
      'NASA HLS images could not be read. Showing the coarser MODIS layer.';
  static const greenBare = 'Bare';
  static const greenDense = 'Dense green';
  static const greenNotSeen = 'Cloud';
}
