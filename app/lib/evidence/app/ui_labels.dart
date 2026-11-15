/// Shared English fallback copy for supporting workflows. Navigation and primary
/// presentation translations live in ui_copy.dart. These labels are deliberately
/// English until native/domain-reviewed translations are available.
abstract final class UiLabels {
  static const datesNotRecorded = 'Dates not recorded';
  static String cropPeriod(String start, String end) =>
      'Planting $start / harvest $end';
  static const platformRequiresLoopback =
      'The local evidence platform requires a loopback URL. Review PLATFORM_URL.';
  static const savedCropNotesUnavailable = 'Saved crop notes unavailable';
  static const tryLoadingYourNotesAgainExistingNotesHave =
      'Try loading your notes again. Existing notes have not been replaced.';
  static const retryNotes = 'Retry notes';
  static const saveFailed = 'save failed';
  static const couldNotSaveCropNotesPleaseTryAgain =
      'Could not save crop notes. Please try again.';
  static const enterAnExactDateAsYYYYMMDD =
      'Enter an exact date as YYYY-MM-DD, or leave blank.';
  static const harvestMustFollowPlanting = 'Harvest must follow planting.';
  static const dateUnknown = 'Date unknown';
  static const recordCropHistoryFarmContext =
      'Record crop history & farm context';
  static const previousPlantingDate = 'Previous planting date';
  static const previousHarvestDate = 'Previous harvest date';
  static const productionSystemOptional = 'Production system (optional)';
  static const irrigationOptional = 'Irrigation (optional)';
  static const drainageOptional = 'Drainage (optional)';
  static const farmerPrioritiesOptional = 'Farmer priorities (optional)';
  static const saveCropNotes = 'Save crop notes';
  static const theseNotesAreNotAutomaticallySuppliedToRust =
      'These notes are not automatically supplied to Rust. The reference gap assessment below uses only its declared profile, farm point and growing dates.';
  static const dailyClimateLocalPlatform = 'Daily climate · local platform';
  static const dailyHistoricalClimate = 'Daily historical climate';
  static const nasaPOWERMERRA2LSTExplicitLocalOnly7I =
      'NASA POWER · MERRA2 · LST. Explicit local-only 7I connection; not monthly climate, current weather or a forecast.';
  static const thisQueryIsRegionalAndDoesNotUpload =
      'This query is regional and does not upload or create a farm record. Daily extrema do not establish crop suitability.';
  static const chooseHistoricalDates = 'Choose historical dates';
  static const requestDailyClimate = 'Request daily climate';
  static const theLocalPlatformIsNotConfiguredExistingMonthly =
      'The local platform is not configured. Existing monthly climate remains available from the dashboard.';
  static const dailyClimateUnavailable = 'Daily climate unavailable';
  static const refreshJobStatus = 'Refresh job status';
  static const cancelJob = 'Cancel job';
  static const completedProcessingCanStillContainMissingOrRejected =
      'Completed processing can still contain missing or rejected source evidence.';
  static const dailyValuesSourceUnitsQuality =
      'Daily values, source units & quality';
  static const nasaSpaceAppsFieldShift = 'NASA Space Apps · Field Shift';
  static const exploreTheWorld = 'Explore the world';
  static const thisPointStaysFixedWhenYouChangeYour =
      'This point stays fixed when you change your area. It is not a field boundary.';
  static const regionalContextOnlyNoPersonalizedCropRecommendations =
      'Regional context only. No personalized crop recommendations.';
  static const fieldSituation = 'Field situation';
  static const addMyFarm = 'Add My Farm';
  static const editMyFarm = 'Edit My Farm';
  static const openFarmQuestionnaire = 'Open Farm Questionnaire';
  static const locationPermissionWasDeniedChooseAnAreaOr =
      'Location permission was denied. Choose an area or explore without GPS.';
  static const deviceLocationIsUnavailableBrowsersUsuallyNeedHTTPS =
      'Device location is unavailable. Browsers usually need HTTPS or localhost. You can choose an area manually.';
  static const tryClearlyLabeledExampleRegionsYangonNairobiOr =
      'Try clearly labeled example regions: Yangon, Nairobi or São Paulo in Choose an Area. No data are loaded until you select an area.';
  static const changeHistoricalDates = 'Change historical dates';
  static const fieldPhotos = 'Field photos';
  static const switchArea = 'Switch Area';
  static const confirmAFarmFirst = 'Confirm a farm first.';
  static const fieldConditionIsUnknown = 'Field condition is unknown';
  static const regionalEstimatesAndPhotosDoNotEstablishSoil =
      'Regional estimates and photos do not establish soil health, crop stress or disease. A confirmed point is not a field boundary.';
  static const readTheEvidenceInContext = 'Read the evidence in context';
  static const availableMeansASourceReturnedDataNotThat =
      'Available means a source returned data, not that a field is healthy. Partial, missing, stale, rejected and not-yet-evaluated evidence cannot establish safe conditions.';
  static const noLocationSpecificEvidenceLoaded =
      'No location-specific evidence loaded';
  static const chooseAnAreaOrConfirmAFarmTo =
      'Choose an area or confirm a farm to inspect its climate records. No source dates, values or quality are assumed.';
  static const loadingClimateSourceInformation =
      'Loading climate source information';
  static const climateSourceUnavailable = 'Climate source unavailable';
  static const theClimateServiceDidNotReturnAValidated =
      'The climate service did not return a validated response. No example readings were substituted.';
  static const nasaPOWERHistoricalClimate = 'NASA POWER · historical climate';
  static const unitsRainfallMmPerMonthTemperatureMonthlyMean =
      'Units: rainfall mm per month; temperature monthly mean °C. Historical modeled context, not a field measurement.';
  static const sourceDatesCoverageQualityLimitations =
      'Source dates, coverage, quality & limitations';
  static const nasaGIBSDisplayImagery = 'NASA GIBS · display imagery';
  static const modisTerraTrueColourProvisionalDisplayLayer =
      'MODIS Terra true colour · provisional display layer';
  static const requestedImageDatesAreShownWithEachView =
      'Requested image dates are shown with each view. The requested date does not establish a usable acquisition. Display imagery is never numerical NDVI input.';
  static const technicalIntegrationTrace = 'Technical integration trace';
  static const cropProfilesRemainReferenceOnly =
      'Crop profiles remain reference only';
  static const theGlobalCatalogIsRecommendationIneligibleAProfile =
      'The global catalog is recommendation-ineligible. A profile, a successful request or a completed calculation does not establish that a crop is suitable for this farm.';
  static const openstreetmapContributors = '© OpenStreetMap contributors';
  static const couldNotSavePreferencesTryAgain =
      'Could not save preferences. Try again.';
  static const navigationPreview = 'မြန်မာ · navigation preview';
  static const dailyClimateLocalEvidencePlatform =
      'Daily climate · local evidence platform';
  static const exploreClimateAndSatelliteImagesForAnyArea =
      'Explore climate and satellite images for any area. Add your farm when you are ready.';
  static const yourLocationHelpsFindAnAreaItDoes =
      'Your location helps find an area. It does not mark your farm. You can continue without location permission.';
  static const choicesAndConfirmedFarmPointsStayOnThis =
      'Choices and confirmed farm points stay on this device. Selected coordinates go to our climate service and NASA POWER. Satellite views request NASA GIBS images. Opening the map requests OpenStreetMap tiles. No account is required.';
}
