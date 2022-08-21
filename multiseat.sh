#!/bin/bash

# drm lease manager and weston 10 build and start on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution

keyboards=('/sys/class/input/input4' )
mouses=('/sys/class/input/input3' )
leases=('card0-VGA-1' )

kiosks=("LIBGL_ALWAYS_SOFTWARE=1 alacritty" "")
wait_time=9s	# time between seat instances start (systemd job)
ms_dir="/home/multiseat"

red="\e[1;31m"
white="\e[0m"
wb="$red[Weston Builder]$white"
ms="$red[MultiSeat]$white"

site=(	"https://raw.githubusercontent.com/garlett/multiseat/main/" \
	"https://gerrit.automotivelinux.org/gerrit/gitweb?p=AGL/meta-agl-devel.git;a=blob_plain;f=meta-agl-drm-lease/recipes-graphics/weston/weston/" \ 
	"" \
)

patch=(	"'${site[1]}0001-backend-drm-Add-method-to-import-DRM-fd.patch'" \
	"'${site[1]}0002-Add-DRM-lease-support.patch'" \
	"'${site[1]}0001-compositor-do-not-request-repaint-in-output_enable.patch'" \
#	"'${site[1]}0003-launcher-do-not-touch-VT-tty-while-using-non-default.patch'" \	# merged on master already
#	"'${site[1]}0004-launcher-direct-handle-seat0-without-VTs.patch'" \		# merged on master already
)

if [ "$EUID" -ne 0 ]
	then 
	echo -e "$wb Please run this as root"
	exit
fi


case "$1" in 
    "-b") # build
	if ! [ -d $ms_dir ]
	then
		echo -e "$wb creating systemctl services .... "
		cat <<- EOF > /etc/systemd/system/drm-lease-manager@.service
			[Unit]
			Description=drm-lease-manager
		
			[Service]
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
			PAMName=login
			Environment=SEATD_VTBOUND=0
			Environment=XDG_SESSION_TYPE=wayland
			Environment=XDG_SEAT=seat_%i
			User=user_%i
			Group=user_%i
			ExecStart=/bin/sh -c "/usr/bin/weston -Bdrm-backend.so --seat=seat_%i --drm-lease=%i ${kiosk}"

			[Install]
			WantedBy=graphical.target"
			EOF

		echo -e "$wb soft linking library files from /usr/local/... to /usr/... "
		cd /usr/
		mkdir -p include/libdlmclient local/lib/pkgconfig 
		for file in include/{libdlmclient/dlmclient.h,toml.h} lib/pkgconfig/{libdlmclient.pc,libtoml.pc} lib/{libdlmclient.so,libtoml.so}
		do
			! [ -e $file ] && ( ln -s /usr/local/$file $( dirname $file ) || exit 30 )
		done
		
		echo -e "$wb installing required packages .... "
		pacman -Sy --noconfirm git make meson ninja wget alacritty gcc cmake pkgconfig libdrm  \
			sudo fakeroot wayland libxkbcommon libinput libunwind pixman cairo libjpeg-turbo libwebp mesa libegl libgles \
			pango lcms2 mtdev libva colord pipewire wayland-protocols freerdp patch || exit 40

		mkdir -p $ms_dir/weston
		cd $ms_dir || exit 45

		echo -e "$wb git clone tomlc99 library .... "
		git clone "http://github.com/cktan/tomlc99.git"
		mv tomlc99/libtoml.pc.sample tomlc99/libtoml.pc

		echo -e "$wb git clone and build drm-lease-manager .... "
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
	echo -e "$wb Using pacman to remove previus weston installation .... "
	pacman -R weston --noconfirm
	echo -e "$wb Removing previus weston build .... "
	rm -r src/ pkg/
	echo -e "$wb Downloading and building weston .... "
	sudo -u${ms_dir##*/} makepkg -f --skippgpcheck || exit 110 # TODO: insert keys on user and remove skippgpcheck flag
	pacman -U weston-*.pkg.tar.zst --noconfirm || exit 120
	;;

    "-c") # create config
	# set "master-of-seat" on input devices
	sed -i 's/SUBSYSTEM=="input", KERNEL=="input\*", TAG+="seat"/&, TAG+="master-of-seat"/' /usr/lib/udev/rules.d/71-seat.rules || exit 130
	udevadm control --reload && udevadm trigger || exit 140

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
	#vi $0
	;;
	
    "-e") # enable config
	seat_pos=0
	for lease in ${leases[@]};
	do
		echo -e "$ms Creating weston seat $lease ... "
		loginctl attach seat_$lease ${keyboards[$seat_pos]} ${mouses[$seat_pos]} || exit 170
		useradd --badname user_$lease 2>/dev/null # || exit 180 # user name may not contain uppercase
		mkdir -p /home/user_$lease
		loginctl seat-status seat_$lease | cat
		seat_pos=$(($seat_pos + 1))
	done
	#loginctl list-seats
	echo -e "$ms you may need to run this command multiple times"
	;;

    "-s") # start services
	echo -e "$ms Starting drm-lease-manager server service ... "
	systemctl stop weston-seat* drm-lease-manager*
	rm /var/local/run/drm-lease-manager/card*
	systemctl start `systemd-escape --template=drm-lease-manager@.service /dev/dri/card*` || exit 180 # udev job ?
	sleep $wait_time # re-test if dlm works with --wait, notify, forking and systemd socket, ELSE replace with:
	#while ! [ -e /var/local/run/drm-lease-manager/* ] ; do sleep 0.1s done

	seat_pos=0
	for lease in ${leases[@]};
	do
		echo -e "$ms Starting weston seat $lease ... ${kiosks[$seat_pos]} "
		chown user_$lease:user_$lease /var/local/run/drm-lease-manager/$lease{,.lock} || exit 190

		systemctl unset-environment kiosk
		[[ ${kiosks[$seat_pos]} != "" ]] && systemctl set-environment kiosk= \
			"--shell=kiosk-shell.so & ( sleep $wait_time ; WAYLAND_DISPLAY=wayland-1 ${kiosks[$seat_pos]} ) &"
		# if weston supports systemd api, change to kiosk-seat@ .service

		systemctl start weston-seat@$lease.service || exit 210
		sleep $wait_time # check if weston supports systemd api
		seat_pos=$(($seat_pos + 1))
	done

	s=$(loginctl | grep root)
	loginctl kill-session ${s:0:7}
	;;

    #"-r") # run 
		#systemd-run --collect -E XDG_SESSION_TYPE=wayland -E XDG_SEAT=seat_$lease -E XDG_RUNTIME_DIR=/run/user/1007 --uid=1007 -p PAMName=login \ 
		#		-p User=user_$lease -p Group=user_$lease weston || exit 210

    *)
	cat <<- EOF
		$ms github.com/garlett/multiseat

		 -b Build
		 -c Create Config
		 -e Enable Config
		 -s Start Services

		 last error: echo \$?
		 logs: journalctl -xe
		 undo seats config: loginctl flush-devices
		EOF
	;;
esac

# killall weston $kiosk_app # && cat log_weston.log
# echo -e "$ms stopping drm-lease-manager server service ... "
# systemctl stop `systemd-escape --template=drm-lease-manager@.service /dev/dri/card*`



