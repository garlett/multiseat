#!/bin/bash

# drm lease manager and weston 10 build and start on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution

# you need to:
# config lease-names in the end of this script, run drm-lease-manager to get a list
# edit /usr/lib/udev/rules.d/71-seat.rules and at the `Allow USB hubs` append: , TAG+="master-of-seat"
# then attach seat1 devices, like:
#  loginctl seat-status
#  loginctl attach seat1 /sys/devices/pci0000:00/0000:00:1a.0/usb1 
#  loginctl attach seat1 /sys/devices/pci0000:00/0000:00:1a.0/usb1/1-1/1-1.3 # keyboard2
#  loginctl attach seat1 /sys/devices/pci0000:00/0000:00:1a.0/usb1/1-1/1-1.4 # mouse2
# reboot ### udevadm control --reload # not working

if [ "$EUID" -ne 0 ]
  then 
  echo -e "\e[1;31m[weston builder]\e[0m Please run this as root"
  su
  exit
fi

if [[ "$1" == "" ]] # run without recompile
then
	useradd -m userdw
	cd /home/userdw || exit 10

	if ! [ -d drm-lease-manager ]
	then
	    echo -e "\e[1;31m[weston builder]\e[0m updating system and installing required packages .... "
	    pacman -Syu git meson ninja wget --noconfirm || exit 20

	    echo -e "\e[1;31m[weston builder]\e[0m git clone and build drm-lease-mangaer .... "
	    git clone "https://gerrit.automotivelinux.org/gerrit/src/drm-lease-manager.git" || exit 30
	    cd drm-lease-manager
	    meson build || exit 40
	    ninja -C build || exit 50
	    ninja -C build install || exit 60

	    echo -e "\e[1;31m[weston builder]\e[0m linking dlmclient library .... "
	    cd /usr/
	    mkdir -p include/libdlmclient || exit 70
	    for file in local/include/libdlmclient/dlmclient.h local/lib/pkgconfig/libdlmclient.pc local/lib/libdlmclient.so*
	    do
        	if ! [ -e $( dirname ${file/local\//} ) ]
	        then        
        	     	ln -s /usr/$file $( dirname ${file/local\//} ) || exit 80
	        fi
	    done

	    echo -e "[Unit]\nDescription=drm-lease-manager\n\n[Service]\nExecStart=/usr/local/bin/drm-lease-manager\n\n[Install]\nWantedBy=multi-user.target" > /etc/systemd/system/drm-lease-manager.service  || exit 85
        # TODO: insert dlm cardX parameter	
        fi


	cd /home/userdw || exit 90
	mkdir -p weston || exit 100
	chown userdw:userdw weston/ || exit 110
	cd weston

	if ! [ -e PKGBUILD ]
	then
	    echo -e "\e[1;31m[weston builder]\e[0m preparing weston arch package file descriptor .... "

	    wget https://raw.githubusercontent.com/archlinux/svntogit-community/packages/weston/trunk/PKGBUILD || exit 120

	    sed -i "s/-D simple-dmabuf-drm=auto//g;s/'SKIP')/'SKIP'{,,,})/g" PKGBUILD  # echo "md5sums+=('SKIP'{,,,})" >> PKGBUILD

	    echo "source+=(\"https://raw.githubusercontent.com/garlett/multiseat/main/\"{0001-backend-drm-Add-method-to-import-DRM-fd,0002-Add-DRM-lease-support}\".patch\")" >> PKGBUILD
	    echo "source+=(\"https://gerrit.automotivelinux.org/gerrit/gitweb?p=AGL/meta-agl-devel.git;a=blob_plain;f=meta-agl-drm-lease/recipes-graphics/weston/weston/0001-compositor-do-not-request-repaint-in-output_enable.patch\")" >> PKGBUILD
	    # ,0003-launcher-do-not-touch-VT-tty-while-using-non-default,	### merged on master already
	    # ,0004-launcher-direct-handle-seat0-without-VTs			### merged on master already

	else
	    echo -e "\e[1;31m[weston builder]\e[0m using pacman to remove previus weston installation .... "
	    pacman -R weston --noconfirm # || exit 11
	    echo -e "\e[1;31m[weston builder]\e[0m removing previus weston build .... "
	    rm -r src/ pkg/ # || exit 140  #  rm src/weston-*/compositor/drm-lease.{c,h} 2>/dev/null  # || exit 12 # patch does not keep track of previus newly created files
	fi

	echo -e "\e[1;31m[weston builder]\e[0m downloading and building weston .... "
	sudo -uuserdw makepkg -f -s --skippgpcheck || exit 150 # TODO: insert keys on user and remove skippgpcheck flag
	pacman -U weston-*.pkg.tar.zst --noconfirm || exit 160
fi


echo -e "\e[1;31m[multiseat]\e[0m starting drm-lease-manager server service ... "
systemctl start drm-lease-manager || exit 170
sleep 1

echo "" > log_weston.log
echo -e "\e[1;31m[multiseat]\e[0m starting weston seat1 ... "
sleep 1
SEATD_VTBOUND=0 weston -Bdrm-backend.so --seat=seat1 --drm-lease=card0-DVI-I-1 --log=log_weston.log &

echo -e "\e[1;31m[multiseat]\e[0m starting weston seat0 ... "
sleep 2
weston -Bdrm-backend.so --drm-lease=card0-VGA-1 --log=log_weston.log # --shell=kiosk-shell.so -c /root/kiosk.ini

cat log_weston.log
echo -e "\e[1;31m[multiseat]\e[0m stoping drm-lease-manager server service ... "
systemctl stop drm-lease-manager

