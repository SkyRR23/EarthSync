import 'package:flutter/widgets.dart';

/// Presentation copy for 7L. Burmese is a navigation preview requiring native
/// and agricultural domain review; evidence retains its original source text.
abstract final class UiCopy {
  static const en = <String, String>{
    'mapLayer': 'Map layer',
    'map_standard': 'Standard · OpenStreetMap',
    'map_satellite': 'Satellite · NASA MODIS',
    'hybridUnavailable':
        'Hybrid labels unavailable: NASA reference tiles returned HTTP 500 at field-scale zooms. Terrain is not configured.',
    'pointHelp':
        'Pan and zoom. Tap to choose your farm point, or enter coordinates.',
    'boundaryHelp':
        'Tap corners in order. Select a numbered vertex, then tap its new position. Confirm or cancel before saving the farm.',
    'zoomIn': 'Zoom in',
    'zoomOut': 'Zoom out',
    'centerFarm': 'Center on farm point',
    'drawBoundary': 'Draw boundary',
    'editBoundary': 'Edit boundary',
    'pointOnly': 'Use point only',
    'undo': 'Undo',
    'cancelBoundary': 'Cancel boundary edits',
    'confirmBoundary': 'Confirm boundary',
    'deleteVertex': 'Delete selected vertex',
    'home': 'Home',
    'farm': 'My Farm',
    'explore': 'Explore',
    'assistant': 'Assistant',
    'settings': 'Settings',
    'tagline': 'Understand your land.\nExplore your options.',
    'welcome': 'Welcome to EarthSync',
    'welcomeBody':
        'A clearer view of your land, with NASA climate records, satellite context and your own observations.',
    'evidenceFirst': 'Grounded in evidence. Guided by you.',
    'discover': 'Your next step starts here',
    'discoverBody': 'Explore any region. Add your farm whenever you are ready.',
    'areaAction': 'Explore an Area',
    'farmAction': 'Add My Farm',
    'overview': 'Your land, in perspective',
    'overviewBody':
        'See what is known, what is missing, and what to record next.',
    'climate': 'Historical climate',
    'climateBody':
        'Rainfall and temperature from NASA POWER. Regional modeled context, not current weather.',
    'satellite': 'A view from above',
    'satelliteBody':
        'Dated imagery and observation quality. Display images are not field measurements.',
    'planning': 'Plan with a clearer picture',
    'planningBody':
        'Record your crop history and explore evidence gaps before making a decision.',
    'ask': 'Ask EarthSync',
    'askBody':
        'Plain-language explanations, connected to the evidence and its sources.',
    'sources': 'Sources & limitations',
    'sourceNote':
        'Satellite and climate data can help us explore field conditions, but they are not substitutes for direct field observations.',
    'appearance': 'Appearance',
    'system': 'Use device setting',
    'light': 'Light',
    'dark': 'Dark',
    'language': 'Language',
    'languageNote':
        'Burmese navigation preview is machine-drafted and requires native/domain review. Scientific evidence and remaining workflows are in English.',
    'privacy': 'Your data & privacy',
    'privacyBody':
        'Farm and area choices are stored on this device. GPS is optional. Photo metadata requires consent; private workspace tokens stay in session memory.',
    'forecast': 'Current weather & forecast',
    'forecastBody':
        'Current observations and official warnings are unavailable. Saved farms can request dated NOAA temperature forecasts in Persisted farm evidence. NASA POWER remains historical climate.',
    'fieldTitle': 'Know your field',
    'fieldBody':
        'Available evidence and the information still needed. Data availability is not a field health score.',
    'notEvaluated': 'Not yet evaluated',
    'point': 'Confirmed farm point',
    'areaPoint': 'Exploration point',
    'noLocation': 'Choose an area to begin',
    'mapConsent': 'Load the interactive map',
    'mapPrivacy':
        'Map tiles are requested from OpenStreetMap only when you open the map.',
    'history': 'Your crop history',
    'historyBody':
        'Farmer-reported context, retained on this device. It does not authorize crop recommendations.',
    'previous': 'Previous crops',
    'current': 'Current crop',
    'next': 'Next season',
    'unknownCrop': 'Not recorded',
    'photoTitle': 'Your field, through your lens',
    'photoBody':
        'Keep dated observations together. Photos do not establish a diagnosis or confirm a farm location.',
    'emptyPhotos': 'A place for your field observations',
    'emptyPhotosBody':
        'Connect your private local workspace to upload, review and manage photos.',
    'referenceOnly': 'Reference only · not recommendation eligible',
    'assessment': 'Crop planning & assessment',
    'dateStart': 'Planting date',
    'dateEnd': 'Harvest date',
    'about': 'About EarthSync',
    'aboutBody':
        'NASA Space Apps 2026 · Field Shift\nAgricultural exploration and decision support · v1.0.0',
    'saved': 'Saved on this device',
    'retry': 'Try again',
    'unavailable': 'Unavailable',
    'back': 'Back to dashboard',
  };
  static const my = <String, String>{
    'home': 'ပင်မ',
    'farm': 'ကျွန်ုပ်၏လယ်ယာ',
    'explore': 'လေ့လာရန်',
    'assistant': 'အကူအညီ',
    'settings': 'ဆက်တင်များ',
    'welcome': 'EarthSync မှ ကြိုဆိုပါသည်',
    'tagline': 'သင့်မြေကို နားလည်ပါ။\nသင့်ရွေးချယ်မှုများကို လေ့လာပါ။',
    'language': 'ဘာသာစကား',
    'appearance': 'အသွင်အပြင်',
    'sources': 'အချက်အလက်ရင်းမြစ်များ',
  };
  static String text(BuildContext context, String key) =>
      (Localizations.localeOf(context).languageCode == 'my' ? my[key] : null) ??
      en[key] ??
      key;
}
