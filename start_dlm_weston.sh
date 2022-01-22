#!/bin/bash

systemctl start drm-lease-manager 

echo "[multiseat]" > log_weston.log

weston --drm-lease=card0-VGA-1 --log=log_weston.log

cat log_weston.log

