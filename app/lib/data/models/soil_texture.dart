/// Soil texture from the farmer's own "texture by feel" test (FAO/USDA
/// hand-texturing: ball → ribbon → feel). Farmer-reported, not a lab value.
/// Names match the Rust engine's `SoilTexture` (snake_case on the wire).
enum SoilTexture { sand, sandyLoam, loam, silt, clayLoam, clay }

extension SoilTextureInfo on SoilTexture {
  /// Engine JSON value.
  String get engineName => switch (this) {
    SoilTexture.sand => 'sand',
    SoilTexture.sandyLoam => 'sandy_loam',
    SoilTexture.loam => 'loam',
    SoilTexture.silt => 'silt',
    SoilTexture.clayLoam => 'clay_loam',
    SoilTexture.clay => 'clay',
  };

  String get label => switch (this) {
    SoilTexture.sand => 'Sand',
    SoilTexture.sandyLoam => 'Sandy loam',
    SoilTexture.loam => 'Loam',
    SoilTexture.silt => 'Silt',
    SoilTexture.clayLoam => 'Clay loam',
    SoilTexture.clay => 'Clay',
  };

  String get emoji => switch (this) {
    SoilTexture.sand => '🏖️',
    SoilTexture.sandyLoam => '🟫',
    SoilTexture.loam => '🌱',
    SoilTexture.silt => '🌫️',
    SoilTexture.clayLoam => '🧱',
    SoilTexture.clay => '🏺',
  };
}

SoilTexture? soilTextureFromName(String? name) =>
    SoilTexture.values.where((t) => t.engineName == name).firstOrNull;

enum Ribbon { none, short, medium, long }

enum Feel { gritty, smooth, neither }

/// The hand-texturing key, simplified to the engine's six classes:
/// - no ball → sand
/// - ball, no ribbon → sandy loam
/// - ribbon over 5 cm → clay; 2.5–5 cm → clay loam
/// - ribbon under 2.5 cm → gritty: sandy loam, smooth: silt, neither: loam
/// Returns null while an answer is still missing.
SoilTexture? soilFromFeelTest({bool? makesBall, Ribbon? ribbon, Feel? feel}) {
  if (makesBall == null) return null;
  if (!makesBall) return SoilTexture.sand;
  return switch (ribbon) {
    null => null,
    Ribbon.none => SoilTexture.sandyLoam,
    Ribbon.long => SoilTexture.clay,
    Ribbon.medium => SoilTexture.clayLoam,
    Ribbon.short => switch (feel) {
      null => null,
      Feel.gritty => SoilTexture.sandyLoam,
      Feel.smooth => SoilTexture.silt,
      Feel.neither => SoilTexture.loam,
    },
  };
}
