{ iio-sensor-proxy }:

iio-sensor-proxy.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./patches/0003-iio-sensor-proxy-start-preclaimed-coldplug-sensor.patch
    ./patches/0004-iio-sensor-proxy-serialize-ssc-accel-polling.patch
    ./patches/0005-iio-sensor-proxy-cancel-released-pending-claims.patch
    ./patches/0006-iio-sensor-proxy-broadcast-sensor-availability.patch
  ];
})
