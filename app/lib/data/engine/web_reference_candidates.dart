import '../environment/nasa_power_client.dart';
import '../models/farmer_input.dart';
import 'live_integration.dart';

const pulseReferenceUrl =
    'https://www.aciar.gov.au/sites/default/files/legacy/green_gram_and_black_gram_final.pdf';

/// Published examples for exploration, never reviewed field-specific advice.
/// The native bridge keeps its existing climate-only request builder.
Map<String, dynamic> buildWebIntegrationRequest(
  FarmerInput input,
  NasaPowerEvidence evidence,
) {
  final request = buildLiveIntegrationRequest(input, evidence);
  if (input.currentCrop != 'rice') return request;

  const sourceId = 'irri_myanmar_pulses_2016';
  Map<String, dynamic> profile(String crop, String name) => {
    'profile_id': '${crop}_reference',
    'crop_id': crop,
    'common_name': name,
    'production_system': null,
    'crop_family': null,
    'planting_months': null,
    'soil_textures': null,
    'drainage': {
      'value': ['well'],
      'source_refs': [sourceId],
    },
    'water_requirement': null,
    'unsupported_requirements': [
      {
        'value':
            'Local variety, residual soil moisture, salinity, pH and planting/harvest dates need review; this reference is not a validated field prescription.',
        'source_refs': [sourceId],
      },
    ],
  };
  Map<String, dynamic> step(String crop) => {
    'crop_id': crop,
    'profile_id': crop == 'rice' ? null : '${crop}_reference',
    'production_system': null,
    'growing_window': null,
  };
  request['crop_references'] = {
    'sources': [
      {
        'id': sourceId,
        'citation':
            'IRRI (2016), Guidelines for Production and Management of Green Gram and Black Gram Grown in Rice Paddy: A Case in Myanmar. ACIAR CoP29. Pages 1–4, 9–11. $pulseReferenceUrl',
        'scope':
            'Case studies in Maubin (Ayeyarwady) and Daik Oo (Bago), Myanmar. Applicability to the selected field has not been reviewed.',
        'status': 'reference_only',
      },
    ],
    'profiles': [
      profile('mung_bean', 'Mung bean / green gram'),
      profile('black_gram', 'Black gram'),
    ],
  };
  request['scenarios'] = [
    {
      'id': 'reported_rice',
      'label': 'Rice — reported current crop',
      'is_baseline': true,
      'steps': [step('rice')],
    },
    for (final crop in ['mung_bean', 'black_gram'])
      {
        'id': 'rice_then_$crop',
        'label': 'Rice → ${Crops.label(crop)} · reference option',
        'is_baseline': false,
        'steps': [step('rice'), step(crop)],
      },
  ];
  return request;
}
