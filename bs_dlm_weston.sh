#!/bin/bash

# drm lease manager and weston 10 build and start on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution

# bug: root bash session stays attached to keyboard

wait_time=9s	# time between seat instances start (systemd job)
#kiosks=("LIBGL_ALWAYS_SOFTWARE=1 alacritty", "firefox" ) # not working yet
#keyboards=()
#mouses=()

red="\e[1;31m"
white="\e[0m"
wb="$red[weston builder]$white"
ms="$red[multiseat]$white"

if [ "$EUID" -ne 0 ]
	then 
	echo -e "$wb Please run this as root"
	exit
fi


if [[ "$1" == "-c" ]] # check for compile flag
then
	useradd -m userdw
	cd /home/userdw || exit 10

	if ! [ -d drm-lease-manager ]
	then
		echo -e "$wb Updating system and installing required packages .... "
		pacman -Syu git meson ninja wget alacritty --noconfirm || exit 20

		echo -e "$wb git clone and build drm-lease-manager .... "
		git clone "https://gerrit.automotivelinux.org/gerrit/src/drm-lease-manager.git" || exit 30
		cd drm-lease-manager
		meson build || exit 40
		ninja -C build || exit 50
		ninja -C build install || exit 60

		echo -e "$wb Linking dlmclient library .... "
		cd /usr/
		mkdir -p include/libdlmclient || exit 70
		for file in local/include/libdlmclient/dlmclient.h local/lib/pkgconfig/libdlmclient.pc local/lib/libdlmclient.so*
		do
			if ! [ -e $( dirname ${file/local\//} ) ]
			then
				ln -s /usr/$file $( dirname ${file/local\//} ) || exit 80
			fi
		done

		echo -e "[Unit]\nDescription=drm-lease-manager\n\n[Service]\nExecStart=/usr/local/bin/drm-lease-manager %I\n\n[Install]\nWantedBy=multi-user.target" > /etc/systemd/system/drm-lease-manager@.service  || exit 86
		echo -e "[Unit]\nDescription=Weston User Seat Service\nAfter=systemd-user-sessions.service\n\n[Service]\nType=simple\nPAMName=login\nEnvironment=SEATD_VTBOUND=0\nEnvironment=XDG_SESSION_TYPE=wayland\n\nEnvironment=XDG_SEAT=seat_%i\nUser=user_%i\nGroup=user_%i\nExecStart=/bin/sh -c \"/usr/bin/weston -Bdrm-backend.so --seat=seat_%i --drm-lease=%i ${kiosk}\"\n\n[Install]\nWantedBy=graphical.target" > /etc/systemd/system/weston-seat@.service || exit 88
	fi


	cd /home/userdw || exit 90
	mkdir -p weston || exit 100
	chown userdw:userdw weston/ || exit 110
	cd weston

	if ! [ -e PKGBUILD ]
	then
		echo -e "$wb Preparing weston arch package file descriptor .... "

		wget https://raw.githubusercontent.com/archlinux/svntogit-community/packages/weston/trunk/PKGBUILD || exit 120

		sed -i "s/-D simple-dmabuf-drm=auto//g;s/'SKIP')/'SKIP'{,,,})/g" PKGBUILD  # echo "md5sums+=('SKIP'{,,,})" >> PKGBUILD

		echo "source+=(\"https://raw.githubusercontent.com/garlett/multiseat/main/\"{0001-backend-drm-Add-method-to-import-DRM-fd,0002-Add-DRM-lease-support}\".patch\")" >> PKGBUILD
		echo "source+=(\"https://gerrit.automotivelinux.org/gerrit/gitweb?p=AGL/meta-agl-devel.git;a=blob_plain;f=meta-agl-drm-lease/recipes-graphics/weston/weston/0001-compositor-do-not-request-repaint-in-output_enable.patch\")" >> PKGBUILD
		# ,0003-launcher-do-not-touch-VT-tty-while-using-non-default,	### merged on master already
		# ,0004-launcher-direct-handle-seat0-without-VTs		### merged on master already

	else
		echo -e "$wb Using pacman to remove previus weston installation .... "
		pacman -R weston --noconfirm # || exit 11
		echo -e "$wb Removing previus weston build .... "
		rm -r src/ pkg/ # || exit 140  #  rm src/weston-*/compositor/drm-lease.{c,h} 2>/dev/null  # || exit 12 # patch does not keep track of previus newly created files
	fi

	echo -e "$wb Downloading and building weston .... "
	sudo -uuserdw makepkg -f -s --skippgpcheck || exit 150 # TODO: insert keys on user and remove skippgpcheck flag
	pacman -U weston-*.pkg.tar.zst --noconfirm || exit 160
else
	echo -e "$wb If you want to download, compile and install, type: ./bs_dlm_weston.sh -c ... for logs type: journalctl -xe"
fi

# set "master-of-seat" on input devices
sed -i 's/SUBSYSTEM=="input", KERNEL=="input*", TAG+="seat"/&, TAG+="master-of-seat"/' /usr/lib/udev/rules.d/71-seat.rules || exit 163
udevadm control --reload && udevadm trigger || exit 164

# keyboards and mouses auto detect
[[ $keyboards == "" && $mouses == "" ]] && for dev in /sys/class/input/input*/capabilities/key;
do
	[ "$(cat $dev | rev | cut -d ' ' -f 1 | rev)" == "fffffffffffffffe" ] && keyboards+=(${dev/"/capabilities/key"/})
	[ "$(cat $dev | rev | cut -d ' ' -f 5 | rev)" \> "1" ]                && mouses+=(${dev/"/capabilities/key"/})
done


echo -e "$ms Starting drm-lease-manager server service ... "
systemctl stop weston-seat* drm-lease-manager*
rm /var/local/run/drm-lease-manager/card*
systemctl start `systemd-escape --template=drm-lease-manager@.service /dev/dri/card*` || exit 170 # udev job ?
sleep $wait_time # because dlm does not work with --wait, notify, forking and systemd socket, replace with: while ! [ -e /var/local/run/drm-lease-manager/* ] ; do sleep 0.1s done
unset DISPLAY

seat_pos=0
shopt -s extglob
for lease in /var/local/run/drm-lease-manager/card!(*.lock); # udev job ?
do
	lease=$(basename $lease)
	echo -e "$ms Creating weston seat $lease ... "
	loginctl attach seat_$lease ${keyboards[$seat_pos]} ${mouses[$seat_pos]} || exit 180

	useradd -m --badname user_$lease 2>/dev/null # || exit 190 # user name may not contain uppercase
	chown user_$lease:user_$lease /var/local/run/drm-lease-manager/$lease{,.lock} || exit 200
	mkdir -p /home/user_$lease/.config

#	systemctl set-environment kiosk="--shell=kiosk-shell.so & ( sleep $wait_time ; WAYLAND_DISPLAY=wayland-1 LIBGL_ALWAYS_SOFTWARE=1 alacritty ) &"
	# if weston supports systemd api, change to kiosk-seat@ .service
	systemctl start weston-seat@$lease.service || exit 210
	#systemd-run --collect -E XDG_SESSION_TYPE=wayland -E XDG_SEAT=seat_$lease -E XDG_RUNTIME_DIR=/run/user/1007 --uid=1007 -p PAMName=login -p User=user_$lease -p Group=user_$lease weston || exit 210
	sleep $wait_time
	seat_pos=$(($seat_pos + 1))
done
 
# killall weston $kiosk_app # && cat log_weston.log
# echo -e "$ms stopping drm-lease-manager server service ... "
# systemctl stop `systemd-escape --template=drm-lease-manager@.service /dev/dri/card*`


