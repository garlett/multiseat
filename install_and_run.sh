#!/bin/bash
pacman -S --needed git
git clone -b wlroots-0.20 https://github.com/Sturm0/multiseat.git
cd multiseat

install -Dm755 ./multiseat.sh /usr/local/bin/multiseat.sh
install -Dm755 ./login/login.sh /usr/local/bin/login.sh
install -Dm644 ./login/alacritty.toml /usr/local/etc/multiseat/login/alacritty.toml
install -Dm644 ./login/autostart /usr/local/etc/multiseat/login/autostart
install -Dm644 ./autostart /etc/xdg/labwc/autostart

/usr/local/bin/multiseat.sh -a

