#!/bin/bash

# tomlc, drm lease manager and weston 10.0.2 builder on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution

unset inputs leases usbdvs
# config start
inputs[3]+='/sys/class/input/input11 ' # PIXART USB OPTICAL MOUSE
inputs[3]+='/sys/class/input/input12 ' # HID 04f30103#
inputs[0]+='/sys/class/input/input16 ' # ImPS/2 Generic Wheel Mouse
inputs[0]+='/sys/class/input/input2 ' # AT Translated Set 2 keyboard#
inputs[2]+='/sys/class/input/input4 ' # Logitech USB Keyboard#
inputs[1]+='/sys/class/input/input7 ' # Microsoft Microsoft 5-Button Mouse with IntelliEyeTM
inputs[1]+='/sys/class/input/input8 ' #   USB Keyboard#
leases[0]='card0-DVI-I-1'
leases[1]='card0-VGA-1'
leases[2]='card1-DVI-I-2'
#leases[3]='card1-TV-1'
leases[3]='card1-VGA-2'
usbdvs[0]+='1-1.1 ' # USB Hub 2.0 - ALCOR
usbdvs[1]+='1-1.2 ' # USB Hub 2.0 - ALCOR
usbdvs[2]+='1-1.2.1 ' # USB SmartCard Reader - Gemalto
usbdvs[3]+='1-1.1.4 ' # USB SmartCard Reader - Gemplus
usbdvs[0]+='1-1.2.4 ' #  - 
usbdvs[1]+='2-1.5 ' # Futronic Fingerprint Scanner 2.0 - Futronic Technology Company Ltd.
usbdvs[2]+='2-1.6 ' # C270 HD WEBCAM - 
# config end

k=('' 'LIBGL_ALWAYS_SOFTWARE=1 exec alacritty' 'LIBGL_ALWAYS_SOFTWARE=1 exec alacritty -e /home/login.sh')
kiosks=("${k[0]}" "${k[0]}" "${k[2]}" "${k[0]}" )

ms_dir="/home/multiseat"

site=(	"https://raw.githubusercontent.com/garlett/multiseat/10.0.2/" \
	"https://gerrit.automotivelinux.org/gerrit/gitweb?p=AGL/meta-agl-devel.git;a=blob_plain;f=meta-agl-drm-lease/recipes-graphics/weston/weston/" \ 
)
patch=(	"'${site[0]}0001-backend-drm-Add-method-to-import-DRM-fd.patch'" \
	"'${site[0]}0002-Add-DRM-lease-support.patch'" \
	"'${site[1]}0001-compositor-do-not-request-repaint-in-output_enable.patch'" \
#	"'${site[1]}0003-launcher-do-not-touch-VT-tty-while-using-non-default.patch'" \	# merged on master already
#	"'${site[1]}0004-launcher-direct-handle-seat0-without-VTs.patch'" \		# merged on master already
)


if [ "$EUID" -ne 0 ]
then 
	echo -e "$wb Please run this as root"
	exit
fi

wait_time=0.1s	# time between exist checks (systemd job) (inotifywait ?)
red="\e[1;31m"
white="\e[0m"
wb="$red[Weston Builder]$white"
ms="$red[MultiSeat]$white"


function get_usb_path_port() {
	dev=$( basename $1 )
	bus=$( basename ${1/"$dev"/} )
	path=$( grep -Przl "BUSNUM=${bus}\nDEVNUM=$dev" /sys/devices/*/*/usb*/ 2> /dev/null )
	echo ${path/uevent/}
}


function set_usb_owner() {
	i=0
	port=$( basename $( get_usb_path_port $1 ) 2> /dev/null )
	[[ $port == *.* ]] && for lease in ${leases[@]};
	do
		[[ "${usbdvs[$((i++))]}" == *$port* ]] && chown user_$lease $1 && return 0
	done
}


case "$1" in 
	
    "-l") # create services and links
	echo -e "$wb creating systemctl services ...."
	ms_path=$( cd $( dirname $0 ) && pwd )/$( basename $0 )
	cat <<- EOF > /etc/systemd/system/drm-lease-manager@.service
		[Unit]
		Description=Drm Lease Manager
		After=systemd-user-sessions.service

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
		#Group=user_%i
		ExecStart=/bin/sh -c "${kiosk} /usr/bin/weston -Bdrm-backend.so --seat=seat_%i --drm-lease=%i $k"

		[Install]
		WantedBy=graphical.target
		EOF
	cat <<- EOF > /etc/systemd/system/multiseat.service
		[Unit]
		Description=MultiSeat Starter
		After=systemd-user-sessions.service
		Conflicts=getty@tty1.service

		[Service]
		ExecStart=$ms_path -s
		ExecStop=$ms_path -q
		RemainAfterExit=yes

		[Install]
		WantedBy=multi-user.target
		EOF
	cat <<- EOF > /etc/systemd/system/usbowner.service
		[Unit]
		Description=Usb Owner Monitor

		[Service]
		ExecStart=$ms_path -u
		RemainAfterExit=yes

		[Install]
		WantedBy=multi-user.target
		EOF
	systemctl daemon-reload

	echo -e "$wb soft linking library files from /usr/local/... to /usr/..."
	cd /usr/
	mkdir -p include/libdlmclient local/lib/pkgconfig 
	for file in include/{libdlmclient/dlmclient.h,toml.h} lib/pkgconfig/{libdlmclient.pc,libtoml.pc} lib/{libdlmclient.so.0,libtoml.so}
	do
		! [ -e $file ] && ( ln -s /usr/local/$file $( dirname $file ) || exit 30 )
	done
	;;


    "-g") # git clones
	echo -e "$wb installing required packages ...."
	pacman -Sy --noconfirm --needed git make meson ninja wget alacritty gcc cmake pkgconfig libdrm sudo \
		fakeroot wayland libxkbcommon libinput libunwind pixman cairo libjpeg-turbo libwebp mesa libegl \
		libgles pango lcms2 mtdev libva colord pipewire wayland-protocols freerdp patch inotify-tools || exit 40

	mkdir -p $ms_dir/weston
	cd $ms_dir || exit 45

	echo -e "$wb git clone tomlc99 library ...."
	git clone "http://github.com/cktan/tomlc99.git" || exit 48
	mv tomlc99/libtoml.pc{.sample,}

	echo -e "$wb git clone drm-lease-manager ...."
	git clone "https://gerrit.automotivelinux.org/gerrit/src/drm-lease-manager.git" || exit 50

	echo -e "$wb preparing weston arch package file descriptor ...."
	cd $ms_dir/weston
	wget https://raw.githubusercontent.com/archlinux/svntogit-community/packages/weston/trunk/PKGBUILD || exit 55
	sed -i "s/\(pkgver=\).*$/\110.0.2/ ; s/\(sums=(\).*$/\1/ ; s/'SKIP'/&{,,,,}/g" PKGBUILD
	echo "source+=( ${patch[@]} )" >> PKGBUILD
	cd ..
	useradd ${ms_dir##*/}
	chown -R ${ms_dir##*/} weston/ || exit 57
	;;


    "-b") # build
	[ -d $ms_dir ] || ( $0 -l ; $0 -g ) # links and git clones 

	echo -e "$wb building tomlc parser ...."
	cd $ms_dir/tomlc99/
	make || exit 60
	make install || exit 70

	echo -e "$wb building drm-lease-manager ...."
	cd $ms_dir/drm-lease-manager
	meson build || exit 80
	ninja -C build || exit 90
	ninja -C build install || exit 100

	cd $ms_dir/weston
	echo -e "$wb Using pacman to remove previus weston installations ...."
	pacman -R weston --noconfirm
	echo -e "$wb Removing previus weston build ...."
	rm -r src/ pkg/
	echo -e "$wb Downloading and building weston ...."
	sudo -u${ms_dir##*/} makepkg -f --skippgpcheck || exit 110 # TODO: insert keys on user and remove skippgpcheck flag
	pacman -U weston-*.pkg.tar.zst --noconfirm || exit 120
	echo -e "$wb Building complete !!!"
	;;


    "-c") # create config
	keybd_pos=0
	mouse_pos=0
	for dev in /sys/class/input/input*/capabilities/key;
	do
		key_cap=( $(cat $dev | rev) )
		dev=${dev/'/capabilities/key'/}	

		[[ ${key_cap[0]} == efffffffffffffff ]] && config+="inputs[$((keybd_pos++))]+='$dev ' ## $(cat $dev/name)\n"
		[ "$(echo ${key_cap[4]} | rev)" \> "1" ] && config+="inputs[$((mouse_pos++))]+='$dev ' #@ $(cat $dev/name)\n"
		# TODO ? audio
	done
	[ $keybd_pos -lt $mouse_pos ] && keybd_pos=$mouse_pos

	lease_pos=0
	for lease in $(loginctl seat-status | grep drm:card[0-9]- | grep -o card.*);
	do
		config+="$( [ $lease_pos -ge $keybd_pos ] && echo "#" )leases[$((lease_pos++))]='$lease'\n"
	done
	
	usb_pos=0 
	for dev in /dev/bus/usb/*/*;
       	do 
		path_port=$( get_usb_path_port $dev )
		port=$( basename $path_port 2> /dev/null )
		name="$( cat $path_port/product 2> /dev/null ) - $( cat $path_port/manufacturer 2> /dev/null )"
		[[ $port == *.* ]] && ! [[ ${name,,} =~ .*(mouse|keyboard).* ]] && \
			config+="usbdvs[$((usb_pos++))]+='$port ' # $name\n"
		[ $usb_pos -ge $keybd_pos ] && usb_pos=0
	done

	# review and save config on this file header
	echo -e "$config" > /tmp/ms_config.sh
	for editor in gedit kate nvim vim vi nano
	do
		$editor /tmp/ms_config.sh && break
	done
	config=$( cat /tmp/ms_config.sh | tr -cd "[:alnum:][]+='#/.\n -" )
	sed -zi "s:\(# config start\n\).*\(# config end\n\):\1${config//$'\n'/\\n}\n\2:" $0

	$0 -e # enable config
	;;
	

    "-e") # enable config
	# set "master-of-seat" on input devices
	sed -i 's/SUBSYSTEM=="input", KERNEL=="input\*", TAG+="seat"$/&, TAG+="master-of-seat"/' \
		/usr/lib/udev/rules.d/71-seat.rules || exit 140
	udevadm control --reload && udevadm trigger || exit 150

	$0 -f # disable previus config
	seat_pos=0
	for lease in ${leases[@]};
	do
		echo -e "$ms Creating seat $seat_pos '$lease' with: $( cat ${inputs[$seat_pos]//' '/'/name '} | tr '\n' ' ' )"
		useradd --badname user_$lease 2>/dev/null # || exit 170 # user name may not contain uppercase
		mkdir -p /home/user_$lease
		chown user_$lease /home/user_$lease || exit 160
		
		while ! loginctl --no-pager seat-status seat_$lease 2> /dev/null
		do
			loginctl attach seat_$lease ${inputs[seat_pos]}
		done
		seat_pos=$(( seat_pos + 1 ))
	done
	;;


    "-f") # disable config
	echo -e "$ms Flushing seats ...."
	while [ $( loginctl list-seats | wc -l ) -gt 4 ]
	do
		loginctl flush-devices
	done
	;;


    "-d") # dlm service
	echo -e "$ms Starting drm-lease-manager server service ... "
	systemctl start `systemd-escape --template=drm-lease-manager@.service /dev/dri/card*` || exit 180 # udev job ?
	while ! ls /var/local/run/drm-lease-manager/* >& /dev/null ; do sleep $wait_time; done
	;;


    "-r") # restart seats [with arg $2 == lease]
	seat_pos=0
	for lease in ${leases[@]};
	do
		if [[ "$2" == ""  ]] || [[ "$2" == "$lease" ]] || [[ "$2" == "$seat_pos" ]]
		then
			echo -e "$ms Starting weston seat $lease ... ${kiosks[$seat_pos]} "
			chown user_$lease /var/local/run/drm-lease-manager/$lease{,.lock} || exit 190

			systemctl set-environment usbdvs="$usbdvs"
			systemctl set-environment kiosk=" $( [[ ${kiosks[$seat_pos]} == "" ]] && echo "" || echo \
				"( while ! [ -e \${XDG_RUNTIME_DIR}/wayland-1 ] ; do sleep $wait_time; done;" \
				"WAYLAND_DISPLAY=wayland-1 ${kiosks[$seat_pos]} ) & k='--shell=kiosk-shell.so'; " )" # exec

			systemctl restart weston-seat@$lease.service || \
				( systemctl status weston-seat@$lease.service -l --no-pager && exit 200 )
			while ! [ -e /run/user/$( id -u user_$lease )/wayland-1 ] ; do sleep $wait_time; done;
		fi
		seat_pos=$(($seat_pos + 1))
	done
	sleep $wait_time
	;;


    "-s") # start services
	. $0 -Q # quit services
	. $0 -d # start dlm-lease-manager services
	. $0 -r # start weston seats services

	O=$(loginctl | grep root) && loginctl kill-session ${O:0:7}
	systemctl stop getty*
	;;


    #"-x") # execute 
		#systemd-run --collect -E XDG_SESSION_TYPE=wayland -E XDG_SEAT=seat_$lease -E XDG_RUNTIME_DIR=/run/user/1007 \ 
		#   --uid=1007 -p PAMName=login -p User=user_$lease -p Group=user_$lease weston || exit 210


    "-u") # start usb owner monitor
	for dev in /dev/bus/usb/*/*;
       	do 
		set_usb_owner $dev
	done
	inotifywait /dev/bus/usb -mre create | while read dir action file;
	do
		set_usb_owner $dir$file
	done &
	;;


    "-q" | "-Q") # quit services
	systemctl stop weston-seat* drm-lease-manager*
	rm /var/local/run/drm-lease-manager/* >& /dev/null
	if [[ "$1" == "-q" ]]
	then
#		sleep 1s #$wait_time
#		systemctl start getty@tty2
		chvt 2
#		sleep 1s #$wait_time
#		chvt 1
#		reset
#		sleep 9s
	fi # this section kind of works only on shutdown, "alt+Fn" is required on quit
	;;


    "-j") # journal logs 
	journalctl -xeu weston-seat* -u drm-lease-manager*
	;;


    *) # -a auto
	echo -e	"$ms github.com/garlett/multiseat"
	cat <<- EOF
		 -b 		[Download, link and] build
		 -c 		Create, review and enable config
		 -s 		Start drm-lease-manager and weston services
		 -q 		Quit multiseat

		 -r [LEASE]  	Restart weston seat service [with LEASE name or pos]
		 -d		Start drm-lease-manager
		 -u		Start usb owner monitor
		 -g		Git clone repositories
		 -l		Create library links
		 -e 		Enable config
		 -f 		Disable config
		 -j 		Journal logs

		 last error: echo \$?
		EOF
	;;
esac
