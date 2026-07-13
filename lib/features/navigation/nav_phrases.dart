/// Turns an OSRM maneuver ("turn left", "roundabout", "depart", …) into Russian
/// banner + spoken phrases. The backend forwards OSRM's `maneuver.type modifier`
/// verbatim in `RouteStep.instruction`, so this is where it becomes human.
class NavPhrase {
  final String banner; // short, for the top banner
  final String spoken; // full clause for TTS (distance prefix added by caller)
  const NavPhrase(this.banner, this.spoken);
}

class NavPhrases {
  static NavPhrase fromOsrm(String instruction, String roadName) {
    final s = instruction.toLowerCase().trim();
    final onRoad = roadName.trim().isNotEmpty ? ' на $roadName' : '';

    if (s.contains('uturn')) return const NavPhrase('Разворот', 'выполните разворот');
    if (s.startsWith('depart')) return NavPhrase('Старт', 'начните движение$onRoad');
    if (s.startsWith('arrive')) return const NavPhrase('Прибытие', 'вы прибыли на место');
    if (s.contains('roundabout') || s.contains('rotary')) {
      return NavPhrase('Кольцо', 'на кольце держитесь по маршруту$onRoad');
    }
    if (s.startsWith('merge')) return NavPhrase('Перестройтесь', 'перестройтесь$onRoad');
    if (s.startsWith('fork')) {
      if (s.contains('left')) return const NavPhrase('Левее', 'на развилке держитесь левее');
      if (s.contains('right')) return const NavPhrase('Правее', 'на развилке держитесь правее');
      return const NavPhrase('Развилка', 'держитесь по маршруту на развилке');
    }
    if (s.contains('sharp left')) return NavPhrase('Резко налево', 'резко налево$onRoad');
    if (s.contains('sharp right')) return NavPhrase('Резко направо', 'резко направо$onRoad');
    if (s.contains('slight left')) return NavPhrase('Левее', 'плавно налево$onRoad');
    if (s.contains('slight right')) return NavPhrase('Правее', 'плавно направо$onRoad');
    if (s.contains('left')) return NavPhrase('Налево', 'поверните налево$onRoad');
    if (s.contains('right')) return NavPhrase('Направо', 'поверните направо$onRoad');
    return NavPhrase('Прямо', 'продолжайте движение прямо$onRoad');
  }

  /// Rounds a distance to a spoken form: "через 200 метров", "через 1,2 км".
  static String distancePrefix(double meters) {
    if (meters >= 1000) {
      final km = (meters / 100).round() / 10.0;
      return 'через ${km.toString().replaceAll('.', ',')} км';
    }
    final m = (meters / 10).round() * 10;
    return 'через $m метров';
  }
}
