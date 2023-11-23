#!/bin/bash

# tomlc, drm lease manager and weston 11.0.0 builder on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution

unset inputs leases usbdvs
# config start
inputs[0]+='/sys/class/input/input2 ' ## AT Translated Set 2 keyboard
inputs[1]+='/sys/class/input/input4 ' ##   USB Keyboard
inputs[1]+='/sys/class/input/input7 ' # Microsoft Microsoft 5-Button Mouse with IntelliEyeTM
inputs[0]+='/sys/class/input/input9 ' # ImPS/2 Generic Wheel Mouse
leases[0]='card0-DVI-I-1'
leases[1]='card0-VGA-1'
#leases[2]='card1-DVI-I-2'
#leases[3]='card1-TV-1'
#leases[4]='card1-VGA-2'
usbdvs[0]+='1-1.1 ' # USB Hub 2.0 - ALCOR
usbdvs[1]+='2-1.3 ' # C270 HD WEBCAM - 
usbdvs[0]+='2-1.4 ' # Futronic Fingerprint Scanner 2.0 - Futronic Technology Company Ltd.
usbdvs[1]+='2-1.6 ' # DCP-T820DW - Brother
# config end

k=('' 'exec firefox' 'LIBGL_ALWAYS_SOFTWARE=1 exec alacritty' 'LIBGL_ALWAYS_SOFTWARE=1 exec alacritty -e /home/login.sh')
kiosks=("${k[3]}" "${k[0]}" "${k[3]}" "${k[0]}" )

ms_dir="/home/multiseat"

site=(	"https://raw.githubusercontent.com/garlett/multiseat/10.0.94/patch/" \
	"https://gerrit.automotivelinux.org/gerrit/gitweb?p=AGL/meta-agl-devel.git;a=blob_plain;f=meta-agl-drm-lease/recipes-graphics/weston/weston/" \ 
)
patch=(	"'${site[0]}0001-backend-drm-Add-method-to-import-DRM-fd.patch'" \
	"'${site[0]}0002-Add-DRM-lease-support.patch'" \
	"'${site[0]}0001-compositor-do-not-request-repaint-in-output_enable.patch'" \
#	"'${site[1]}0003-launcher-do-not-touch-VT-tty-while-using-non-default.patch'" \	# merged on master already
#	"'${site[1]}0004-launcher-direct-handle-seat0-without-VTs.patch'" \		# merged on master already
)
sed_pkg_weston_ver="s/\(pkgver=\).*$/\110.0.93/ ; s/\(sums=(\).*$/\1'SKIP'/" # set weston ver = 10.0.93




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
	cat <<- EOF > /etc/systemd/system/multiseat-usbowner.service
		[Unit]
		Description=Multiseat Usb Owner Agent

		[Service]
		ExecStart=$ms_path -u
		RemainAfterExit=yes

		[Install]
		WantedBy=multi-user.target
		EOF

	cat <<- EOF > /etc/systemd/system/multiseat.service
		[Unit]
		Description=MultiSeat Starter
		After=systemd-user-sessions.service
		Conflicts=getty@tty1.service

		[Service]
		ExecStart=$ms_path -s
		ExecStopPost=$ms_path -q
		RemainAfterExit=yes

		[Install]
		WantedBy=multi-user.target
		EOF

	cat <<- EOF > /etc/systemd/system/multiseat-dlm@.service
		[Unit]
		Description=Drm Lease Manager
		After=systemd-user-sessions.service

		[Service]
		#Type=forking notify Group=video UMask=0007
		ExecStart=/usr/local/bin/drm-lease-manager %I
		EOF

	cat <<- 'EOF' > /etc/systemd/system/multiseat-weston@.service
		[Unit]
		Description=Multiseat Weston Launcher
		After=systemd-user-sessions.service

		[Service]
		PAMName=login
		Environment=SEATD_VTBOUND=0
		Environment=WAYLAND_DISPLAY=wayland-1
		Environment=XDG_SESSION_TYPE=wayland
		Environment=XDG_SEAT=seat_%i
		User=user_%i
		
		#Type=notify
		#ExecStart=/bin/sh -c "/usr/bin/weston --seat=seat_%i --drm-lease=%i -Bdrm-backend.so --modules=systemd-notify.so $( [ -z "${kiosk:0:9}" ] || echo '--shell=kiosk-shell.so' )"
		
		# use the following if you want parent set to weston
		Type=simple
		ExecStart=/bin/sh -c "( while ! [ -e ${XDG_RUNTIME_DIR}/wayland-1 ] ; do sleep 0.1s; done; ${kiosk} ) & x=1; /usr/bin/weston --seat=seat_%i --drm-lease=%i -Bdrm-backend.so $( [ -z "${kiosk:0:9}" ] || echo '--shell=kiosk-shell.so' )"
		EOF

	cat <<- 'EOF' > /etc/systemd/system/multiseat-kiosk@.service
		[Unit]
		Description=Multiseat Application Launcher
		After=multiseat-weston@%i.service
		BindsTo=multiseat-weston@%i.service

		[Service]
		PAMName=login
		Environment=SEATD_VTBOUND=0
		Environment=WAYLAND_DISPLAY=wayland-1
		Environment=XDG_SESSION_TYPE=wayland
		Environment=XDG_SEAT=seat_%i
		User=user_%i
		ExecStart=/bin/sh -c "${kiosk}"
		Restart=always
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

	useradd ${ms_dir##*/}
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
	sed -i "s/'SKIP'/&{,,,}/g ; $sed_pkg_weston_ver" PKGBUILD
	echo "source+=( ${patch[@]} )" >> PKGBUILD
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
	chown -R ${ms_dir##*/} ../weston/ || exit 105
	sudo -u${ms_dir##*/} makepkg -f --skippgpcheck || exit 110 # TODO: insert keys on user and remove skippgpcheck flag
	pacman -U weston-*.pkg.tar.zst --noconfirm || exit 120
	echo -e "$wb Building complete !!!"
	;;


    "-c" | "-C" ) # create config
	echo -e "$ms Creating simple config ...."
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
	for editor in gedit kate nano nvim vim vi
	do
		$editor /tmp/ms_config.sh && break
	done
	config=$( cat /tmp/ms_config.sh | tr -cd "[:alnum:][]+='#/.\n -" )
	sed -zi "s:\(# config start\n\).*\(# config end\n\):\1${config//$'\n'/\\n}\n\2:" $0

	[[ "$1" == "-c" ]] && $0 -e # enable config
	;;
	

    "-e") # enable config
	# set "master-of-seat" on input devices
	sed -i 's/SUBSYSTEM=="input", KERNEL=="input\*", TAG+="seat"$/&, TAG+="master-of-seat"/' \
		/usr/lib/udev/rules.d/71-seat.rules || exit 140
	udevadm control --reload && udevadm trigger || exit 150

	$0 -f # disable previus config
	seat_pos=-1
	for lease in ${leases[@]};
	do
		seat_pos=$((seat_pos + 1))
		name=$( cat ${inputs[$seat_pos]//' '/'/name '} | tr '\n' ' ' )
		echo -e "$ms Creating seat $seat_pos '$lease' with: $name"
		[[ "$name" == "" ]] && echo -e "$ms fail: inputs could not be found." && continue

		useradd --badname user_$lease 2>/dev/null # || exit 170 # user name may not contain uppercase
		mkdir -p /home/user_$lease
		chown user_$lease /home/user_$lease || exit 160
		
		while ! loginctl --no-pager seat-status seat_$lease 2> /dev/null
		do
			loginctl attach seat_$lease ${inputs[$seat_pos]}
		done
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
	systemctl start `systemd-escape --template=multiseat-dlm@.service /dev/dri/card*` || exit 180 # udev job ?
	while ! ls /var/local/run/drm-lease-manager/* >& /dev/null ; do sleep $wait_time; done
	;;


    "-r") # restart seats [with arg $2 == lease]
	loginctl attach seat0 /sys/devices/pci*/*/*/drm/card*
	seat_pos=0
	for lease in ${leases[@]};
	do
		if [[ "$2" == ""  ]] || [[ "$2" == "$lease" ]] || [[ "$2" == "$seat_pos" ]]
		then
			echo -e "$ms Starting weston seat $lease ... ${kiosks[$seat_pos]} "
			chown user_$lease /var/local/run/drm-lease-manager/$lease{,.lock} || exit 190
			
			# allocate the drm only to keep the seat active in case of all inputs disconnects
			( sleep $((($seat_pos+1)*9))s ; loginctl attach seat_$lease \
				/sys/devices/pci*/*/*/drm/card*/$lease ) & job+="$! "
			
			systemctl set-environment usbdvs="${usbdvs[$seat_pos]}"
			systemctl set-environment kiosk="${kiosks[$seat_pos]}"
#			systemctl stop multiseat-weston@$lease.service
#			systemctl restart multiseat-kiosk@$lease.service || \
			systemctl restart multiseat-weston@$lease.service || \
				( systemctl status multiseat-weston@$lease.service -l --no-pager && exit 200 )

			while ! [ -e /run/user/$( id -u user_$lease )/wayland-1 ] ; do sleep $wait_time; done;
		fi
		seat_pos=$(($seat_pos + 1))
	done
	sleep $wait_time
	wait $job
	;;


    "-s") # start services
	. $0 -Q # quit services
	. $0 -d # start dlm-lease-manager services
	. $0 -r # start weston seats services

	O=$(loginctl | grep root) && loginctl kill-session ${O:0:7}
	systemctl stop getty*
	deallocvt
	;;


    #"-x") # execute 
		#systemd-run --collect -E XDG_SESSION_TYPE=wayland -E XDG_SEAT=seat_$lease -E XDG_RUNTIME_DIR=/run/user/1007 \ 
		#   --uid=1007 -p PAMName=login -p User=user_$lease -p Group=user_$lease weston || exit 210


    "-q" | "-Q") # quit services
	systemctl stop multiseat-weston* multiseat-dlm*
	rm /var/local/run/drm-lease-manager/* >& /dev/null
	
	if [[ "$1" == "-q" ]] # looks better with service
	then
		systemctl start getty@tty1.service
		sleep 1s
		chvt 2
		chvt 1
		deallocvt
	fi 
	;;


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


    "-j") # journal logs 
	journalctl -xeu multiseat*
	;;


    *) # -a auto
	echo -e	"$ms github.com/garlett/multiseat"
	cat <<- EOF
		 -b 		[Git clone, link and] build
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

		 after system upgrades, its recommended to run -b then -c
		 before download again run:  rm -R $ms_dir
		 kiosk app will fail: without connected drm output, or with weston >= 10.0.94
		 last error: echo \$?
		EOF
	;;
esac
