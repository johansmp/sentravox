/// Perfiles de voz que ve el usuario.
///
/// Son cinco opciones cerradas. Los dos primeros usan una voz femenina Piper,
/// los dos siguientes una masculina y el último una femenina más neutra. La
/// velocidad se ajusta por perfil; la voz neuronal se sintetiza offline y el
/// TTS del sistema queda como respaldo.
class VoiceProfile {
  final String id;
  final String label;
  final bool male;
  final double speed;

  /// Voz de espeak-ng que corresponde al modelo Piper.
  final String espeakVoice;

  /// Valores de respaldo para el TTS del sistema.
  final String systemGender;
  final double systemRate;
  final double systemPitch;

  const VoiceProfile({
    required this.id,
    required this.label,
    required this.male,
    required this.speed,
    required this.espeakVoice,
    required this.systemGender,
    required this.systemRate,
    required this.systemPitch,
  });
}

const List<VoiceProfile> voiceProfiles = [
  VoiceProfile(
    id: 'femenina_natural',
    label: 'Femenina natural',
    male: false,
    speed: 0.95,
    espeakVoice: 'es-419',
    systemGender: 'femenina',
    systemRate: 0.88,
    systemPitch: 1.0,
  ),
  VoiceProfile(
    id: 'femenina_calida',
    label: 'Femenina cálida',
    male: false,
    speed: 0.88,
    espeakVoice: 'es-419',
    systemGender: 'femenina',
    systemRate: 0.82,
    systemPitch: 1.05,
  ),
  VoiceProfile(
    id: 'masculina_natural',
    label: 'Masculina natural',
    male: true,
    speed: 0.95,
    espeakVoice: 'es',
    systemGender: 'masculina',
    systemRate: 0.88,
    systemPitch: 0.92,
  ),
  VoiceProfile(
    id: 'masculina_serena',
    label: 'Masculina serena',
    male: true,
    speed: 0.90,
    espeakVoice: 'es',
    systemGender: 'masculina',
    systemRate: 0.82,
    systemPitch: 0.95,
  ),
  VoiceProfile(
    id: 'neutra_profesional',
    label: 'Neutra profesional',
    male: false,
    speed: 1.0,
    espeakVoice: 'es-419',
    systemGender: 'femenina',
    systemRate: 0.9,
    systemPitch: 1.0,
  ),
];

VoiceProfile voiceProfileFor(String? id) {
  return voiceProfiles.firstWhere(
    (profile) => profile.id == id,
    orElse: () => voiceProfiles.first,
  );
}
