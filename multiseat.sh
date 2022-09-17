#!/bin/bash

# drm lease manager and weston 10 build and start on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution

leases=('card0-DVI-I-1' 'card0-VGA-1' )
keyboards=('/sys/class/input/input2' '/sys/class/input/input6' )
mouses=('/sys/class/input/input4' '/sys/class/input/input5' )
kiosks=('' 'LIBGL_ALWAYS_SOFTWARE=1 exec alacritty ') #-e /home/login.sh' '')


site=(	"https://raw.githubusercontent.com/garlett/multiseat/main/" \
	"https://gerrit.automotivelinux.org/gerrit/gitweb?p=AGL/meta-agl-devel.git;a=blob_plain;f=meta-agl-drm-lease/recipes-graphics/weston/weston/" \ 
	"" \
)
patch=(	"'${site[0]}0001-backend-drm-Add-method-to-import-DRM-fd.patch'" \
	"'${site[0]}0002-Add-DRM-lease-support.patch'" \
	"'${site[1]}0001-compositor-do-not-request-repaint-in-output_enable.patch'" \
#	"'${site[1]}0003-launcher-do-not-touch-VT-tty-while-using-non-default.patch'" \	# merged on master already
#	"'${site[1]}0004-launcher-direct-handle-seat0-without-VTs.patch'" \		# merged on master already
)
ms_dir="/home/multiseat"


if [ "$EUID" -ne 0 ]
	then 
	echo -e "$wb Please run this as root"
	exit
fi

wait_time=0.1s	# time between exist checks (systemd job)
red="\e[1;31m"
white="\e[0m"
wb="$red[Weston Builder]$white"
ms="$red[MultiSeat]$white"
			
case "$1" in 
    "-b") # build
	if ! [ -d $ms_dir ]
	then
		echo -e "$wb creating systemctl services .... "
		cat <<- EOF > /etc/systemd/system/drm-lease-manager@.service
			[Unit]
			Description=Drm Lease Manager
		
			[Service]
			#Type=forking notify Group=video UMask=0007
			ExecStart=/usr/local/bin/drm-lease-manager %I

			[Install]
			WantedBy=multi-user.target
			EOF
		cat <<- 'EOF' > /etc/systemd/system/weston-seat@.service
			[Unit]
			Description=Weston User Seat Service
			After=systemd-user-sessions.service

			[Service]
			Type=simple
			#Type=notify
			PAMName=login
			Environment=SEATD_VTBOUND=0
			Environment=XDG_SESSION_TYPE=wayland
			Environment=XDG_SEAT=seat_%i
			User=user_%i
			Group=user_%i
			ExecStart=/bin/sh -c "${kiosk} /usr/bin/weston -Bdrm-backend.so --seat=seat_%i --drm-lease=%i $k"

			[Install]
			WantedBy=graphical.target
			EOF
		cat <<- EOF > /etc/systemd/system/multiseat.service
			[Unit]
			Description=MultiSeat Starter
		
			[Service]
			ExecStart=$0 -s
			ExecStop=$0 -q

			#[Install]
			#WantedBy=multi-user.target
			EOF
		systemctl daemon-reload

		echo -e "$wb soft linking library files from /usr/local/... to /usr/... "
		cd /usr/
		mkdir -p include/libdlmclient local/lib/pkgconfig 
		for file in include/{libdlmclient/dlmclient.h,toml.h} lib/pkgconfig/{libdlmclient.pc,libtoml.pc} lib/{libdlmclient.so.0,libtoml.so}
		do
			! [ -e $file ] && ( ln -s /usr/local/$file $( dirname $file ) || exit 30 )
		done
		
		echo -e "$wb installing required packages .... "
		pacman -Sy --noconfirm git make meson ninja wget alacritty gcc cmake pkgconfig libdrm sudo fakeroot wayland \
			libxkbcommon libinput libunwind pixman cairo libjpeg-turbo libwebp mesa libegl libgles pango lcms2 \ 
			mtdev libva colord pipewire wayland-protocols freerdp patch || exit 40

		mkdir -p $ms_dir/weston
		cd $ms_dir || exit 45

		echo -e "$wb git clone tomlc99 library .... "
		git clone "http://github.com/cktan/tomlc99.git"
		mv tomlc99/libtoml.pc{.sample,}

		echo -e "$wb git clone drm-lease-manager .... "
		git clone "https://gerrit.automotivelinux.org/gerrit/src/drm-lease-manager.git" || exit 50

		echo -e "$wb preparing weston arch package file descriptor .... "
		useradd ${ms_dir##*/}
		chown ${ms_dir##*/}:${ms_dir##*/} weston/ || exit 50
		cd $ms_dir/weston
		wget https://raw.githubusercontent.com/archlinux/svntogit-community/packages/weston/trunk/PKGBUILD || exit 55
		sed -i "s/-D simple-dmabuf-drm=auto//g;s/'SKIP')/'SKIP'{,,,})/g" PKGBUILD
		echo "source+=( ${patch[@]} )" >> PKGBUILD

	fi

	echo -e "$wb building tomlc parser .... "
	cd $ms_dir/tomlc99/
	make || exit 60
	make install || exit 70

	echo -e "$wb building drm-lease-manager .... "
	cd $ms_dir/drm-lease-manager
	meson build || exit 80
	ninja -C build || exit 90
	ninja -C build install || exit 100

	cd $ms_dir/weston
	echo -e "$wb Using pacman to remove previus weston installations .... "
	pacman -R weston --noconfirm
	echo -e "$wb Removing previus weston build .... "
	rm -r src/ pkg/
	echo -e "$wb Downloading and building weston .... "
	sudo -u${ms_dir##*/} makepkg -f --skippgpcheck || exit 110 # TODO: insert keys on user and remove skippgpcheck flag
	pacman -U weston-*.pkg.tar.zst --noconfirm || exit 120
	;;

    "-c") # create config
	# set "master-of-seat" on input devices
	sed -i 's/SUBSYSTEM=="input", KERNEL=="input\*", TAG+="seat"/&, TAG+="master-of-seat"/' \
		/usr/lib/udev/rules.d/71-seat.rules || exit 130
	udevadm control --reload && udevadm trigger || exit 140

	unset keyboards mouses leases 
	for dev in /sys/class/input/input*/capabilities/key;
	do
		[ "$(cat $dev | rev | cut -d ' ' -f 1 | rev)" == "fffffffffffffffe" ] && skeyboards+="'${dev/'/capabilities/key'/}' "
		[ "$(cat $dev | rev | cut -d ' ' -f 5 | rev)" \> "1" ]                && smouses+="'${dev/'/capabilities/key'/}' "
		# TODO .... saudio+="'${dev/'/capabilities/key'/}' "
	done
	
	for lease in $(loginctl seat-status | grep drm:card[0-9]- | grep -o card.*);
	do
		sleases+="'$lease' "
	done

	# save found devices paths on this file header
	sed -i "s/keyboards=(.*)$/keyboards=($(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$skeyboards"))/" $0 || exit 163
	sed -i "s/mouses=(.*)$/mouses=($(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$smouses"))/" $0 || exit 164
	sed -i "s/leases=(.*)$/leases=($(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$sleases"))/" $0 || exit 165
	#vi $0
	echo -e "$ms done, you need to review it inside $0, and then enable with '-e'"
	;;
	
    "-e") # enable config
	seat_pos=0
	for lease in ${leases[@]};
	do
		echo -e "$ms Creating weston seat $lease with ${keyboards[$seat_pos]} and ${mouses[$seat_pos]} ... "
		loginctl attach seat_$lease ${keyboards[$seat_pos]} ${mouses[$seat_pos]} || exit 170
		seat_pos=$(($seat_pos + 1))
		useradd --badname user_$lease 2>/dev/null # || exit 180 # user name may not contain uppercase
		mkdir -p /home/user_$lease
		chown user_$lease:user_$lease /home/user_$lease || exit 175
		loginctl seat-status seat_$lease | cat
	done
	#loginctl list-seats
	echo -e "$ms you may need to run this command multiple times"
	;;

    "-f") # disable config
	loginctl flush-devices
	loginctl list-seats
	echo -e "$ms you may need to run this command multiple times"
	;;

    "-r") # restart seats [with arg $2 == lease]
	seat_pos=0
	for lease in ${leases[@]};
	do
		if [[ "$2" == ""  ]] || [[ "$2" == "$lease" ]] || [[ "$2" == "$seat_pos" ]]
		then
			echo -e "$ms Starting weston seat $lease ... ${kiosks[$seat_pos]} "
			chown user_$lease:user_$lease /var/local/run/drm-lease-manager/$lease{,.lock} || exit 190

			systemctl set-environment kiosk=" $( [[ ${kiosks[$seat_pos]} == "" ]] && echo "" || echo \
				"( while ! [ -e \${XDG_RUNTIME_DIR}/wayland-1 ] ; do sleep $wait_time; done;" \
				"WAYLAND_DISPLAY=wayland-1 ${kiosks[$seat_pos]} ) & k='--shell=kiosk-shell.so'; " )" # exec

			systemctl restart weston-seat@$lease.service || exit 210
			while ! [ -e /run/user/$( id -u user_$lease )/wayland-1 ] ; do sleep $wait_time; done;
		fi
		seat_pos=$(($seat_pos + 1))
	done

	;;

    "-s") # start services
	echo -e "$ms Starting drm-lease-manager server service ... "
	systemctl stop weston-seat* drm-lease-manager*
	rm /var/local/run/drm-lease-manager/* >& /dev/null
	systemctl start `systemd-escape --template=drm-lease-manager@.service /dev/dri/card*` || exit 180 # udev job ?
	while ! ls /var/local/run/drm-lease-manager/* >& /dev/null ; do sleep $wait_time; done

	. $0 -r # start seats
	
	sleep $wait_time
	O=$(loginctl | grep root)
	loginctl kill-session ${O:0:7}
	# TODO: disable background agetty until next reboot
	;;

    #"-x") # execute 
		#systemd-run --collect -E XDG_SESSION_TYPE=wayland -E XDG_SEAT=seat_$lease -E XDG_RUNTIME_DIR=/run/user/1007 \ 
		#   --uid=1007 -p PAMName=login -p User=user_$lease -p Group=user_$lease weston || exit 210

    "-q") # quit services
	systemctl stop weston-seat* drm-lease-manager*
	# reenable agetty
	chvt 2
	chvt 1
	;;

    *)
	cat <<- EOF
		$ms github.com/garlett/multiseat

		 -b 		Build
		 -c 		Create config
		 -e 		Enable config
		 -r LEASE  	Restart weston seat service with LEASE name or pos
		 -s 		Start drm-lease-manager and weston services
		 -q 		Quit multiseat
		 -f 		Disable config

		 last error: echo \$?
		 logs: journalctl -xe
		EOF
	;;
esac

# killall weston $kiosk_app # && cat log_weston.log
# echo -e "$ms stopping drm-lease-manager server service ... "
# systemctl stop `systemd-escape --template=drm-lease-manager@.service /dev/dri/card*`



