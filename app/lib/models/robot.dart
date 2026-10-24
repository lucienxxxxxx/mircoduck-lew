import 'dart:math' as math;

const jointNames = <int, String>{
  20: '左髋旋转',
  21: '左髋侧摆',
  22: '左髋俯仰',
  23: '左膝',
  24: '左踝',
  30: '颈部',
  31: '头部俯仰',
  32: '头部转向',
  33: '头部侧倾',
  34: '嘴巴',
  10: '右髋旋转',
  11: '右髋侧摆',
  12: '右髋俯仰',
  13: '右膝',
  14: '右踝',
};
double? finite(dynamic value) =>
    value is num && value.isFinite ? value.toDouble() : null;

class Joint {
  final int id;
  final double? radians, raw, temperature, voltage, currentRaw, target;
  const Joint(
    this.id,
    this.radians,
    this.raw,
    this.temperature,
    this.voltage,
    this.currentRaw,
    this.target,
  );
  factory Joint.fromRow(List<dynamic> row) => Joint(
        (row[0] as num).toInt(),
        finite(row[1]),
        finite(row[2]),
        finite(row[3]),
        finite(row[4]),
        finite(row[5]),
        finite(row[6]),
      );
  String get name => jointNames[id] ?? 'ID$id';
  double? get degrees => radians == null ? null : radians! * 180 / math.pi;
}

class RobotState {
  String mode = '', phase = '', build = '', inputMode = 'drive', error = '';
  bool serverFresh = false, homed = false, policy = false, realGamepad = false;
  dynamic torque;
  double? age, hz, roll, pitch;
  DateTime? received;
  final Map<int, Joint> joints = {};
  DateTime? jointsAt;
  List<double>? gyro;
  bool? imuValid;
  int? imuSequence;
  String modeJob = '';
  final Map<int, DateTime> jointReceived = {};
  final Map<int, bool> jointValid = {};
  bool jointFresh(int id) =>
      fresh &&
      jointValid[id] == true &&
      jointReceived[id] != null &&
      DateTime.now().difference(jointReceived[id]!).inMilliseconds < 600;
  bool get fresh =>
      serverFresh &&
      received != null &&
      DateTime.now().difference(received!).inMilliseconds < 600;
  bool get jointsFresh =>
      fresh &&
      jointsAt != null &&
      DateTime.now().difference(jointsAt!).inMilliseconds < 600;
  void status(Map<String, dynamic> d) {
    mode = d['mode'] as String? ?? '';
    phase = d['phase'] as String? ?? '';
    build = d['build'] as String? ?? '';
    serverFresh = d['fresh'] == true;
    homed = d['homed'] == true;
    policy = d['policy'] == true;
    realGamepad = d['real_gamepad'] == true;
    inputMode = d['input_mode'] as String? ?? 'drive';
    error = d['error'] as String? ?? '';
    age = finite(d['age']);
    hz = finite(d['hz']);
    torque = d['torque'];
    imuValid = d['imu_valid'] as bool?;
    imuSequence = (d['imu_seq'] as num?)?.toInt();
    final job = d['mode_job'];
    modeJob = job is Map
        ? (job['success'] == null
            ? '正在切换服务…'
            : job['success'] == true
                ? ''
                : '服务切换失败：${job['message']}')
        : '';
    final g = d['g'];
    if (g is List && g.length == 3 && g.every((v) => finite(v) != null)) {
      final x = finite(g[0])!, y = finite(g[1])!, z = finite(g[2])!;
      roll = math.atan2(-y, -z) * 180 / math.pi;
      pitch = math.atan2(x, math.sqrt(y * y + z * z)) * 180 / math.pi;
    } else {
      roll = null;
      pitch = null;
    }
    final w = d['gyro'];
    gyro = w is List && w.length == 3 && w.every((v) => finite(v) != null)
        ? w.map((v) => finite(v)!).toList()
        : null;
    received = DateTime.now();
  }

  void jointPacket(Map<String, dynamic> d) {
    for (final row in d['rows'] as List? ?? []) {
      if (row is List && row.length == 9 && row[0] is num) {
        final j = Joint.fromRow(row);
        if (jointNames.containsKey(j.id)) {
          joints[j.id] = j;
          jointReceived[j.id] = DateTime.now();
          jointValid[j.id] = row[7] == true;
        }
      }
    }
    jointsAt = DateTime.now();
  }
}
