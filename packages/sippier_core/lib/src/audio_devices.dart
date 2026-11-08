/// An audio input or output device. [id] is what the core opens: the
/// CoreAudio UID on macOS, the module's device name elsewhere.
class AudioDevice {
  const AudioDevice(this.id, this.name);

  AudioDevice.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String? ?? json['id'] as String;

  final String id;
  final String name;
}

/// The devices the core can use, and the system's current defaults.
class AudioDevices {
  const AudioDevices({
    this.inputs = const [],
    this.outputs = const [],
    this.defaultInput,
    this.defaultOutput,
  });

  factory AudioDevices.fromJson(Map<String, dynamic> json) {
    List<AudioDevice> list(String key) => [
      for (final d in json[key] as List? ?? const [])
        AudioDevice.fromJson(d as Map<String, dynamic>),
    ];
    return AudioDevices(
      inputs: list('input'),
      outputs: list('output'),
      defaultInput: json['defaultInput'] as String?,
      defaultOutput: json['defaultOutput'] as String?,
    );
  }

  final List<AudioDevice> inputs;
  final List<AudioDevice> outputs;
  final String? defaultInput;
  final String? defaultOutput;
}
