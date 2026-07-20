#!/bin/bash
pacman -S git
git clone -b wlroots-0.20 https://github.com/Sturm0/multiseat.git
cd multiseat
mv ./multiseat.sh /usr/local/bin/multiseat.sh
mv ./login.sh 	  /usr/local/bin/login.sh
chmod +x /usr/local/bin/multiseat.sh
chmod +x /usr/local/bin/login.sh
/usr/local/bin/multiseat.sh -a 
