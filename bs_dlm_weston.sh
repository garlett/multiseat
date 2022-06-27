#!/bin/bash

# drm lease manager and weston 10 build and start on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution

wait_time=9s	# time between seat instances start (systemd job)
#kiosks=("LIBGL_ALWAYS_SOFTWARE=1 alacritty", "firefox" ) #not working
keyboards=()
mouses=()
leases=()

red="\e[1;31m"
white="\e[0m"
wb="$red[weston builder]$white"
ms="$red[multiseat]$white"

if [ "$EUID" -ne 0 ]
	then 
	echo -e "$wb Please run this as root"
	exit
fi

# set "master-of-seat" on input devices
sed -i 's/SUBSYSTEM=="input", KERNEL=="input*", TAG+="seat"/&, TAG+="master-of-seat"/' /usr/lib/udev/rules.d/71-seat.rules || exit 3
udevadm control --reload && udevadm trigger || exit 5

case "$1" in 

    "-b") # build
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
		echo -e "[Unit]\nDescription=Weston User Seat Service\nAfter=systemd-user-sessions.service\n\n[Service]\nType=simple\nPAMName=login\nEnvironment=SEATD_VTBOUND=0\nEnvironment=XDG_SESSION_TYPE=wayland\n\nEnvironment=XDG_SEAT=seat_%i\nUser=user_%i\nGroup=user_%i\nExecStart=/bin/sh -c \"/usr/bin/weston -Bdrm-backend.so --seat=seat_%i --drm-lease=%i \${kiosk}\"\n\n[Install]\nWantedBy=graphical.target" > /etc/systemd/system/weston-seat@.service || exit 88
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
	;;

    "-c") # create config

	unset keyboards mouses leases 
	for dev in /sys/class/input/input*/capabilities/key;
	do
		[ "$(cat $dev | rev | cut -d ' ' -f 1 | rev)" == "fffffffffffffffe" ] && skeyboards+="'${dev/'/capabilities/key'/}' "
		[ "$(cat $dev | rev | cut -d ' ' -f 5 | rev)" \> "1" ]                && smouses+="'${dev/'/capabilities/key'/}' "
	done
	
	for lease in $(loginctl seat-status | grep drm:card[0-9]- | grep -o card.*);
	do
		sleases+="'$lease' "
	done
	
	sed -i "s/keyboards=(.*)$/keyboards=($(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$skeyboards"))/" $0 || exit 163
	sed -i "s/mouses=(.*)$/mouses=($(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$smouses"))/" $0 || exit 164
	sed -i "s/leases=(.*)$/leases=($(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$sleases"))/" $0 || exit 165
	vi $0
	;;
	
    "-e") # enable config
	seat_pos=0
	for lease in ${leases[@]};
	do
		echo -e "$ms Creating weston seat $lease ... "
		loginctl attach seat_$lease ${keyboards[$seat_pos]} ${mouses[$seat_pos]} || exit 170
		useradd -m --badname user_$lease 2>/dev/null # || exit 180 # user name may not contain uppercase
		seat_pos=$(($seat_pos + 1))
		loginctl seat-status seat_$lease | cat
	done
	#loginctl list-seats
	echo -e "$ms you may need to run this command multiple times"
	;;

    "-s") # start services
	echo -e "$ms Starting drm-lease-manager server service ... "
	systemctl stop weston-seat* drm-lease-manager*
	rm /var/local/run/drm-lease-manager/card*
	systemctl start `systemd-escape --template=drm-lease-manager@.service /dev/dri/card*` || exit 190 # udev job ?
	sleep $wait_time # because dlm does not work with --wait, notify, forking and systemd socket, replace with:
	#while ! [ -e /var/local/run/drm-lease-manager/* ] ; do sleep 0.1s done
	unset DISPLAY

	seat_pos=0
	for lease in ${leases[@]};
	do
		echo -e "$ms Starting weston seat $lease ... ${kiosks[$seat_pos]} "
		chown user_$lease:user_$lease /var/local/run/drm-lease-manager/$lease{,.lock} || exit 190

		systemctl unset-environment kiosk
		[[ ${kiosks[$seat_pos]} != "" ]] && systemctl set-environment kiosk="--shell=kiosk-shell.so & ( sleep $wait_time ; ${kiosks[$seat_pos]} ) &"
		# if weston supports systemd api, change to kiosk-seat@ .service

		systemctl start weston-seat@$lease.service || exit 210
		sleep $wait_time # check if weston supports systemd api
		seat_pos=$(($seat_pos + 1))
	done

	s=$(loginctl | grep root)
	loginctl kill-session ${s:0:7}
	;;

    #"-r") # run 
		#systemd-run --collect -E XDG_SESSION_TYPE=wayland -E XDG_SEAT=seat_$lease -E XDG_RUNTIME_DIR=/run/user/1007 --uid=1007 -p PAMName=login -p User=user_$lease -p Group=user_$lease weston || exit 210

    *)
	echo -e "\n $ms github.com/garlett/multiseat\n\n -b Build \n -c Create Config\n -e Enable Config \n -s Start Services\n\n last error: echo \$?\n logs: journalctl -xe\n undo seats config: loginctl flush-devices\n"
	;;
esac

 
# killall weston $kiosk_app # && cat log_weston.log
# echo -e "$ms stopping drm-lease-manager server service ... "
# systemctl stop `systemd-escape --template=drm-lease-manager@.service /dev/dri/card*`


#	shopt -s extglob
#/var/local/run/drm-lease-manager/card!(*.lock); # udev job ?
#		lease=$(basename $lease)

