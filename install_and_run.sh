#!/bin/bash
pacman -S --needed git
git clone -b wlroots-0.20 https://github.com/Sturm0/multiseat.git
cd multiseat
cp ./multiseat.sh /usr/local/bin/multiseat.sh
cp ./login/login.sh 	  /usr/local/bin/login.sh
mkdir -p /usr/local/etc/multiseat/login
cp ./login/alacritty.toml /usr/local/etc/multiseat/login/alacritty.toml
cp ./login/autostart /usr/local/etc/multiseat/login/autostart
chmod +x /usr/local/bin/multiseat.sh
chmod +x /usr/local/bin/login.sh
chmod 644 "/usr/local/etc/multiseat/login/alacritty.toml" # me aseguro que el usuario del "kiosco" pueda leerlo

/usr/local/bin/multiseat.sh -a 

