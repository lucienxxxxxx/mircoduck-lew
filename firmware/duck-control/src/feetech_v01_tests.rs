use super::*;

#[test]
fn v01_capture_layout_scale_flags_and_wrap() {
    let raw = [0xe8,0xff,0x14,0,0x14,0,0xc3,0x39,0x16,0x33,0x15,0xac,
        0xb1,0xf3,0x87,0x1d,0xa9,0xfb,0x40,0xc7];
    let sample = ImuSample::decode_v01(&raw).unwrap();
    assert_eq!(sample.sequence, 64);
    assert_eq!(sample.status, 0xc7);
    assert_eq!(sample.block, raw[..12]);
    assert_eq!(sample.age_ms, None);
    assert_eq!(sample.age_upper_bound_ms, Some(100));
    assert!(sample.is_fresh(20_000));
    assert!(!sample.is_fresh(20_001));
    for flags in [0xcf,0xd7,0xe7,0x87,0xc3,0xc5,0x47] {
        let mut bad = raw;
        bad[19] = flags;
        assert!(!ImuSample::decode_v01(&bad).unwrap().is_fresh(0), "flags {flags:02x}");
    }
    let mut wrap = raw;
    for count in [254,255,0,1] {
        wrap[18]=count;
        assert_eq!(ImuSample::decode_v01(&wrap).unwrap().sequence,u32::from(count));
    }
    // Accel values at 12..18 must never act as count/status/reserved.
    wrap[12..18].fill(0xff);
    assert!(ImuSample::decode_v01(&wrap).unwrap().ready);
    let mut nan=raw;
    nan[6..8].copy_from_slice(&0x7e00u16.to_le_bytes());
    assert!(ImuSample::decode_v01(&nan).is_err());
    let mut unit=raw;
    unit[6..12].fill(0);
    let unit=ImuSample::decode_v01(&unit).unwrap();
    let mut unit_decoder=SflpDecoder::new([1.,0.,0.,0.]);
    for _ in 0..25 {unit.sensor(&mut unit_decoder);}
    assert!(unit_decoder.ready());
    assert_eq!(unit.sensor(&mut unit_decoder).quat,[1.,0.,0.,0.]);
    // Existing SFLP decoder already uses 0.0175 deg/s per count.
    let mut decoder = SflpDecoder::new([1.,0.,0.,0.]);
    let mut core = sample.block;
    core[..2].copy_from_slice(&100i16.to_le_bytes());
    for _ in 0..30 { decoder.decode(&core); }
    let decoded = decoder.decode(&core);
    assert!((decoded.gyro[0] - 1.75_f64.to_radians()).abs() < 1e-9);
}

#[cfg(target_os="linux")]
#[test]
fn v01_unicast_after_servo_group_and_sensor_error_propagation() {
    use serialport::SerialPort;
    let (mut device, mut port) = serialport::TTYPort::pair().unwrap();
    device.set_timeout(Duration::from_secs(2)).unwrap();
    port.set_timeout(Duration::from_millis(2)).unwrap();
    let ids = crate::model::JOINT_IDS.to_vec();
    let expected_ids = ids.clone();
    let worker = std::thread::spawn(move || {
        for step in 0..5 {
            let mut header=[0;4]; device.read_exact(&mut header).unwrap();
            let mut body=vec![0;header[3] as usize]; device.read_exact(&mut body).unwrap();
            assert_eq!(header[..2],[255,255]);
            assert_eq!(header[2..].iter().chain(body.iter()).fold(0u8,|a,b|a.wrapping_add(*b)),255);
            match step {
                0 => {
                    assert_eq!((header[2],body[0],body[1],body[2]),(200,READ,0,5));
                    device.write_all(&packet(200,0,&IMU_V01_IDENTITY).unwrap()).unwrap();
                }
                1|3 => {
                    assert_eq!((header[2],body[0],body[1],body[2]),(254,SYNC_READ,56,15));
                    assert_eq!(&body[3..body.len()-1],expected_ids);
                    let responses=expected_ids.iter().flat_map(|id|packet(*id,0,&[0;15]).unwrap()).collect::<Vec<_>>();
                    device.write_all(&responses).unwrap();
                }
                2|4 => {
                    assert_eq!((header[2],body[0],body[1],body[2]),(200,READ,124,20));
                    let mut raw=[0;20];raw[18]=255;raw[19]=0xc7;
                    device.write_all(&packet(200,if step==4 {2}else{0},&raw).unwrap()).unwrap();
                }
                _ => unreachable!(),
            }
        }
        // Keep the PTY alive until the reader has consumed the final frame.
        std::thread::sleep(Duration::from_millis(40));
    });
    let mut bus=Bus {port:Box::new(port),timeout:Duration::from_millis(60),read_only:true,
        last_sync:SyncTrace::default(),imu_v01:false};
    bus.identify_imu().unwrap();
    let blocks=bus.telemetry(&ids).unwrap();
    assert_eq!(blocks.len(),16);
    assert_eq!(blocks[&200].len(),20);
    assert!(ImuSample::decode(&blocks[&200]).unwrap().ready);
    assert!(bus.telemetry(&ids).is_err());
    assert!(bus.last_sync.missing_ids.contains(&200));
    worker.join().unwrap();
}
