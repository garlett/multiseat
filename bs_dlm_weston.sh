#!/bin/bash

# drm lease manager and weston 10 build and start on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution

wait_time=0.9s 			# time between seat instances start (systemd job)
kiosk=--shell=kiosk-shell.so 	# comment this line to not tun on kiosk mode
log=--log=log_weston.log	# comment this to not generate log on file
kiosk_app=alacritty		# weston-terminal  firefox --no-remote --profile /root/.mozilla/firefox/*.p1/ # starts new instance on profile p1, you may need to "cp -r *" from default profile

# after installed, you need to attach seatX (for X>0) devices, like:
#  loginctl seat-status
#  loginctl attach seat1 /sys/devices/pci0000:00/0000:00:1a.0/usb1 
#  loginctl attach seat1 /sys/devices/pci0000:00/0000:00:1a.0/usb1/1-1/1-1.3 # keyboard2
#  loginctl attach seat1 /sys/devices/pci0000:00/0000:00:1a.0/usb1/1-1/1-1.4 # mouse2

# current status:
#  non root user needs logind api dbus



if [ "$EUID" -ne 0 ]
	then 
	echo -e "\e[1;31m[weston builder]\e[0m Please run this as root"
	exit
fi

if [[ "$1" == "-c" ]] # check for compile flag
then
	useradd -m userdw
	cd /home/userdw || exit 10

	if ! [ -d drm-lease-manager ]
	then
		echo -e "\e[1;31m[weston builder]\e[0m updating system and installing required packages .... "
		pacman -Syu git meson ninja wget alacritty --noconfirm || exit 20

		echo -e "\e[1;31m[weston builder]\e[0m git clone and build drm-lease-manager .... "
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

		sed -i 's/SUBSYSTEM=="usb", ATTR{bDeviceClass}=="09", TAG+="seat$"/&, TAG+="master-of-seat"/' /usr/lib/udev/rules.d/71-seat.rules || exit 82
		udevadm control --reload || exit 84 # probably not working, you may need to reboot 

		# TODO: change to: for card in /dev/dri/card*    and insert $card argumet
		echo -e "[Unit]\nDescription=drm-lease-manager\n\n[Service]\nExecStart=/usr/local/bin/drm-lease-manager\n\n[Install]\nWantedBy=multi-user.target" > /etc/systemd/system/drm-lease-manager.service  || exit 86
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
else
	echo -e "\e[1;31m[weston builder]\e[0m if you want to download, compile and install, type: ./bs_dlm_weston.sh -c"
fi


echo -e "\e[1;31m[multiseat]\e[0m starting drm-lease-manager server service ... "
rm /var/local/run/drm-lease-manager/card*
systemctl start drm-lease-manager || exit 170
sleep $wait_time
unset DISPLAY
#echo "" > log_weston.log


seat_count=0
for lease in /var/local/run/drm-lease-manager/card*;
do
	if ! [[ $lease =~ '.lock' ]]
	then
		seat=seat$seat_count
		lease=$(basename $lease)
		echo -e "\e[1;31m[multiseat]\e[0m Creating weston $seat on $lease ... "
		#useradd -m $seat
		#seat_dir=/run/user/`id -u $seat`
		#mkdir -p $seat_dir || exit 200
		#chown userdw:userdw $seat_dir || exit 210
		#chmod 0700 $seat_dir || exit 220
		#sudo -uuserdw XDG_RUNTIME_DIR=$seat_dir \
		SEATD_VTBOUND=0 weston $log $kiosk -Bdrm-backend.so --seat=$seat --drm-lease=$lease &
		seat_count=$(($seat_count + 1))
		sleep $wait_time
	fi
done


if ! [ "$kiosk" = "" ]
then
	for display in /run/user/0/wayland-*; # /run/user/*/wayland-1;
	do
		if ! [[ $display =~ '.lock' ]]
		then
			WAYLAND_DISPLAY=$(basename $display) LIBGL_ALWAYS_SOFTWARE=1 $kiosk_app &
		fi
	done
fi

#sleep 1m && killall weston # && cat log_weston.log
echo -e "\e[1;31m[multiseat]\e[0m stopping drm-lease-manager server service ... "
systemctl stop drm-lease-manager
