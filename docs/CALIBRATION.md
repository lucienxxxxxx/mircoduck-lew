# Per-robot calibration

Every assembled robot needs its own joint and IMU calibration. This repository
contains an uncalibrated example only. Never copy another robot's encoder zeros
or its IMU mounting quaternion just because its hardware looks similar.

Use commissioning mode with torque confirmed OFF. Record known physical joint
angles, verified direction and measured limits through the service capture flow.
An encoder centre of 2048 is not proof of mechanical zero.

The IMU field is a normalized sensor-to-body quaternion in **W X Y Z** order.
The runtime applies it to gyro and orientation together. Do not merely swap
Euler-angle labels. A 3D model floating above the floor is a height-display issue
and must not be fixed by changing this rotation.

For installation-axis validation:

1. Support the torso truly upright and static; collect multiple fresh samples.
2. Tilt the whole torso forward, keeping lateral tilt small.
3. Return upright and tilt toward the robot's own left, keeping fore/aft tilt small.
4. Confirm axis signs and fit an orthonormal rotation. Back up the previous file.
5. Save through the formal `robot.busCommand` / `verify-imu` route; re-read values.
6. Return upright and check residual pitch/roll. Use a rigid reference for precise zeroing.

Hand-held captures only establish approximate axes. They are not a precision
fixture calibration, absolute heading measurement, or motion acceptance test.
Six-axis fusion cannot provide an absolute yaw reference or absolute height.
Keep motion disabled until installation and mechanical calibration have been
checked on the actual robot. Do not set verification flags to bypass a failed test.
