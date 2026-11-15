import '../../app/strings.dart';
import '../../data/environment/recent_conditions.dart';
import '../../data/models/farmer_input.dart';
import '../../data/models/field_note.dart';
import '../../data/models/soil_texture.dart';
import '../../state/providers.dart';
import '../../state/today.dart';

enum TaskKind { heavyRain, water, soil, photo }

/// Water advice from data only. No amounts: crop water rules are not
/// accepted yet, so the farmer's hand check always has the last word.
enum WaterVerdict { mayNeed, check, canWait }

class FarmTask {
  const FarmTask({
    required this.kind,
    required this.title,
    this.facts = const [],
    this.done = false,
    this.verdict,
    this.source,
  });

  final TaskKind kind;
  final String title;

  /// Plain sentences: what the data and the farmer's own records say.
  final List<String> facts;
  final bool done;
  final WaterVerdict? verdict;

  /// Where the numbers come from (shown small under the card).
  final String? source;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String _ago(int days) => switch (days) {
  0 => S.today,
  1 => S.yesterday,
  _ => S.daysAgo(days),
};

/// The farm's to-do list for [now], newest-signal first. Done tasks are kept
/// (with `done: true`) so the farmer sees what is finished today.
List<FarmTask> buildTasks({
  required FarmerDraft draft,
  required RecentConditions? recent,
  required List<DateTime> waterLog,
  required List<FieldNote> notes,
  required Map<String, String> marks,
  required DateTime now,
  bool canTakePhotos = true,
  Et0? et0,
}) {
  final today = dayOf(now);
  final todo = <FarmTask>[], done = <FarmTask>[];
  void add(FarmTask t) => (t.done ? done : todo).add(t);

  final source = recent?.asOf == null
      ? null
      : S.nasaRecentSource(shortDate(recent!.asOf!));

  // 1. Heavy rain: only when this place's own record says it was unusual,
  // and the farmer said water stays (or does not know).
  final drain = draft.drainage;
  if (recent != null &&
      recent.heaviestUnusual &&
      recent.heaviestDay != null &&
      (drain == null || drain == Drainage.poor || drain == Drainage.unknown)) {
    final day = recent.heaviestDay!;
    final checked = marks['heavy_checked'] == dayKey(day);
    add(
      FarmTask(
        kind: TaskKind.heavyRain,
        title: checked ? S.heavyChecked : S.heavyTitle,
        done: checked,
        source: source,
        facts: [
          S.heavyFact(
            shortDate(day),
            recent.heaviestMm!.round(),
            recent.heavierThanPercent ?? 90,
          ),
          drain == Drainage.poor ? S.heavyYouSaid : S.heavyLowParts,
          S.heavyWalk,
        ],
      ),
    );
  }

  // 2. Water: skipped when the farmer said the field gets rain only.
  if (draft.irrigation != Irrigation.none) {
    final last = waterLog.isEmpty ? null : waterLog.first;
    final since = last == null ? null : today.difference(dayOf(last)).inDays;
    if (since == 0) {
      add(
        const FarmTask(kind: TaskKind.water, title: S.wateredToday, done: true),
      );
    } else if (marks['water_ok'] == dayKey(today)) {
      add(
        const FarmTask(
          kind: TaskKind.water,
          title: S.soilStillWetToday,
          done: true,
        ),
      );
    } else {
      add(_waterTask(draft, recent, since, source, et0));
    }
  }

  // 3. Soil: when never checked, or last checked over a season ago.
  final checkedOn = draft.soilCheckedOn;
  if (draft.soilTexture == null) {
    add(
      const FarmTask(
        kind: TaskKind.soil,
        title: S.soilTitle,
        facts: [S.soilTaskNew],
      ),
    );
  } else if (checkedOn != null &&
      today.difference(dayOf(checkedOn)).inDays > 120) {
    add(
      FarmTask(
        kind: TaskKind.soil,
        title: S.soilAgainTitle,
        facts: [S.soilTaskOld(shortDate(checkedOn))],
      ),
    );
  } else {
    add(
      FarmTask(
        kind: TaskKind.soil,
        title: checkedOn == null
            ? S.soilChecked
            : S.soilCheckedOn(shortDate(checkedOn)),
        done: true,
      ),
    );
  }

  // 4. A crop photo each week.
  if (canTakePhotos) {
    DateTime? lastPhoto;
    for (final n in notes) {
      if (n.photo == null && n.cloudPhoto == null) continue;
      if (lastPhoto == null || n.createdAt.isAfter(lastPhoto)) {
        lastPhoto = n.createdAt;
      }
    }
    final age = lastPhoto == null
        ? null
        : today.difference(dayOf(lastPhoto)).inDays;
    if (age != null && age < 7) {
      add(
        FarmTask(
          kind: TaskKind.photo,
          title: S.photoDone(_ago(age)),
          done: true,
        ),
      );
    } else {
      add(
        FarmTask(
          kind: TaskKind.photo,
          title: S.photoTitle,
          facts: [age == null ? S.photoNone : S.photoOld(age)],
        ),
      );
    }
  }

  return [...todo, ...done];
}

FarmTask _waterTask(
  FarmerDraft draft,
  RecentConditions? recent,
  int? since,
  String? source,
  Et0? et0,
) {
  final facts = <String>[];
  var verdict = WaterVerdict.check;
  if (recent == null || recent.asOf == null) {
    facts.add(S.waterNoData);
  } else {
    final rain = recent.rainVsPast, wet = recent.wetnessVsPast;
    // Rain against the engine's grass water loss (FAO-56), only when the
    // engine had every day; a partial week is shown but not used.
    final loss = et0?.totalMm, mm7 = recent.rain7dMm;
    final balance = loss == null || mm7 == null
        ? null
        : mm7 >= loss
        ? Compared.higher
        : Compared.lower;
    final wetter =
        rain == Compared.higher ||
        wet == Compared.higher ||
        balance == Compared.higher;
    final drier =
        rain == Compared.lower ||
        wet == Compared.lower ||
        balance == Compared.lower;
    if (wetter && !drier) verdict = WaterVerdict.canWait;
    if (drier && !wetter) verdict = WaterVerdict.mayNeed;
    final mm = recent.rain7dMm;
    facts.add(
      mm == null
          ? S.rainWeekUnknown
          : S.rainWeek(mm.round(), switch (rain) {
              Compared.lower => S.lessThanUsual,
              Compared.higher => S.moreThanUsual,
              Compared.usual => S.aboutUsual,
              Compared.unknown => null,
            }),
    );
    final w = switch (wet) {
      Compared.lower => S.wetnessDrier,
      Compared.higher => S.wetnessWetter,
      Compared.usual => S.wetnessUsual,
      Compared.unknown => null,
    };
    if (w != null) facts.add(w);
    if (loss != null) {
      facts.add(
        S.et0Week(loss.round(), switch (balance) {
          Compared.higher => S.lessThanRain,
          Compared.lower => S.moreThanRain,
          _ => null,
        }),
      );
    } else if (et0?.partialMm != null) {
      facts.add(
        S.et0Partial(et0!.partialMm!.round(), et0.usableDays, et0.expectedDays),
      );
    }
  }
  final soil = soilClassFromName(draft.soilTexture)?.engine6;
  if (soil == 'sand' || soil == 'sandy_loam') facts.add(S.sandyDries);
  if (soil == 'clay' || soil == 'clay_loam') facts.add(S.clayHolds);
  facts.add(since == null ? S.noWateringYet : S.lastWatered(_ago(since)));
  facts.add(S.feelFirst);
  return FarmTask(
    kind: TaskKind.water,
    verdict: verdict,
    title: switch (verdict) {
      WaterVerdict.mayNeed => S.waterMayNeed,
      WaterVerdict.canWait => S.waterCanWait,
      WaterVerdict.check => S.waterCheck,
    },
    facts: facts,
    source: source == null || et0 == null ? source : '$source ${S.et0Source}',
  );
}
