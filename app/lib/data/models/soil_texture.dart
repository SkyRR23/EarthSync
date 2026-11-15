/// Soil from the farmer's photos and hand test: the 12 USDA texture classes,
/// plus visible signs. Results are farmer-reported or an AI estimate, never a
/// lab value. Wire names (snake_case) match the backend `soil.py` and the
/// category names engine v0.3 crop rules should use.
enum SoilClass {
  sand,
  loamySand,
  sandyLoam,
  loam,
  siltLoam,
  silt,
  sandyClayLoam,
  clayLoam,
  siltyClayLoam,
  sandyClay,
  siltyClay,
  clay,
}

extension SoilClassInfo on SoilClass {
  String get wireName => switch (this) {
    SoilClass.sand => 'sand',
    SoilClass.loamySand => 'loamy_sand',
    SoilClass.sandyLoam => 'sandy_loam',
    SoilClass.loam => 'loam',
    SoilClass.siltLoam => 'silt_loam',
    SoilClass.silt => 'silt',
    SoilClass.sandyClayLoam => 'sandy_clay_loam',
    SoilClass.clayLoam => 'clay_loam',
    SoilClass.siltyClayLoam => 'silty_clay_loam',
    SoilClass.sandyClay => 'sandy_clay',
    SoilClass.siltyClay => 'silty_clay',
    SoilClass.clay => 'clay',
  };

  /// The 6 soil types today's engine (v0.2) understands.
  String get engine6 => switch (this) {
    SoilClass.sand => 'sand',
    SoilClass.loamySand || SoilClass.sandyLoam => 'sandy_loam',
    SoilClass.loam => 'loam',
    SoilClass.siltLoam || SoilClass.silt => 'silt',
    SoilClass.sandyClayLoam ||
    SoilClass.clayLoam ||
    SoilClass.siltyClayLoam => 'clay_loam',
    SoilClass.sandyClay || SoilClass.siltyClay || SoilClass.clay => 'clay',
  };

  String get label => switch (this) {
    SoilClass.sand => 'Sand',
    SoilClass.loamySand => 'Loamy sand',
    SoilClass.sandyLoam => 'Sandy loam',
    SoilClass.loam => 'Loam',
    SoilClass.siltLoam => 'Silt loam',
    SoilClass.silt => 'Silt',
    SoilClass.sandyClayLoam => 'Sandy clay loam',
    SoilClass.clayLoam => 'Clay loam',
    SoilClass.siltyClayLoam => 'Silty clay loam',
    SoilClass.sandyClay => 'Sandy clay',
    SoilClass.siltyClay => 'Silty clay',
    SoilClass.clay => 'Clay',
  };

  String get emoji => switch (engine6) {
    'sand' => '🏖️',
    'sandy_loam' => '🟫',
    'loam' => '🌱',
    'silt' => '🌫️',
    'clay_loam' => '🧱',
    _ => '🏺',
  };
}

SoilClass? soilClassFromName(String? name) =>
    SoilClass.values.where((t) => t.wireName == name).firstOrNull;

/// Engine (v0.2) soil name for a saved 12-class name; null when unknown.
String? engineSoilName(String? name) => soilClassFromName(name)?.engine6;

enum Ribbon { fallsApart, none, short, medium, long }

enum Feel { gritty, smooth, sticky }

extension RibbonWire on Ribbon {
  String get wire => switch (this) {
    Ribbon.fallsApart => 'falls_apart',
    Ribbon.none => 'none',
    Ribbon.short => 'short',
    Ribbon.medium => 'medium',
    Ribbon.long => 'long',
  };
}

/// Hand-texture key (after Thien 1979) — the same table as the backend's
/// `hand_key`. Ribbon length gives the family; gritty/smooth gives the sandy
/// or silty member. Null when the ribbon is not known.
SoilClass? handKey(Ribbon? ribbon, Feel? feel) {
  if (ribbon == null) return null;
  if (ribbon == Ribbon.fallsApart) return SoilClass.sand;
  final (gritty, smooth, base) = switch (ribbon) {
    Ribbon.none => (
      SoilClass.loamySand,
      SoilClass.siltLoam,
      SoilClass.sandyLoam,
    ),
    Ribbon.short => (SoilClass.sandyLoam, SoilClass.siltLoam, SoilClass.loam),
    Ribbon.medium => (
      SoilClass.sandyClayLoam,
      SoilClass.siltyClayLoam,
      SoilClass.clayLoam,
    ),
    _ => (SoilClass.sandyClay, SoilClass.siltyClay, SoilClass.clay),
  };
  return switch (feel) {
    Feel.gritty => gritty,
    Feel.smooth => smooth,
    _ => base,
  };
}

/// Things a farmer can see in soil; several matter beyond texture
/// (salt, waterlogging, heavy cracking clay).
enum SoilSign {
  cracks,
  whiteCrust,
  greySpots,
  stones,
  darkTopsoil,
  waterlogged,
  rootsOrWorms,
}

extension SoilSignInfo on SoilSign {
  String get wire => switch (this) {
    SoilSign.cracks => 'cracks',
    SoilSign.whiteCrust => 'white_crust',
    SoilSign.greySpots => 'grey_spots',
    SoilSign.stones => 'stones',
    SoilSign.darkTopsoil => 'dark_topsoil',
    SoilSign.waterlogged => 'waterlogged',
    SoilSign.rootsOrWorms => 'roots_or_worms',
  };

  String get emoji => switch (this) {
    SoilSign.cracks => '🏜️',
    SoilSign.whiteCrust => '🧂',
    SoilSign.greySpots => '🌫️',
    SoilSign.stones => '🪨',
    SoilSign.darkTopsoil => '🟤',
    SoilSign.waterlogged => '💧',
    SoilSign.rootsOrWorms => '🪱',
  };
}

SoilSign? soilSignFromWire(String? w) =>
    SoilSign.values.where((s) => s.wire == w).firstOrNull;
