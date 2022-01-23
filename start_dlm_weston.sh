#!/bin/bash

if [ "$EUID" -ne 0 ]
  then 
  echo -e "\e[1;31m[multiseat]\e[0m Please run this as root."
  su
  exit
fi

echo -e "\e[1;31m[multiseat]\e[0m starting drm-lease-manager server service ... " 
systemctl start drm-lease-manager || exit 1
sleep 1

echo "" > log_weston.log

echo -e "\e[1;31m[multiseat]\e[0m starting weston client ... " 
weston --drm-lease=card0-VGA-1 --log=log_weston.log

cat log_weston.log

echo -e "\e[1;31m[multiseat]\e[0m stoping drm-lease-manager server service ... " 
systemctl stop drm-lease-manager
 
