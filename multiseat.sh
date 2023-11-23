#!/bin/bash

# tomlc, drm lease manager and weston 10.0.93 builder on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution

conf=/root/multiseat.conf

ms_dir="/home/multiseat"

sed_pkg_weston_ver="s/\(pkgver=\).*$/\110.0.93/ ; s/\(sums=(\).*$/\1'SKIP'/" # set weston ver = 10.0.93

site=(	"https://raw.githubusercontent.com/garlett/multiseat/main/patch" \
	"https://gerrit.automotivelinux.org/gerrit/gitweb?p=AGL/meta-agl-devel.git;a=blob_plain;f=meta-agl-drm-lease/recipes-graphics/weston/weston/" \ 
)
patch=(	"'${site[0]}0001-backend-drm-Add-method-to-import-DRM-fd.patch'" \
	"'${site[0]}0002-Add-DRM-lease-support.patch'" \
	"'${site[0]}0001-compositor-do-not-request-repaint-in-output_enable.patch'" \
#	"'${site[1]}0003-launcher-do-not-touch-VT-tty-while-using-non-default.patch'" \	# merged already
#	"'${site[1]}0004-launcher-direct-handle-seat0-without-VTs.patch'" \		# merged already
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



function wait_files(){
	count=99 # timeout * $wait_time
	for file in $2
	do
		while ! ls $1$file >& /dev/null
		do
 			sleep $wait_time
			[ $((count--)) -lt 0 ] && echo -e "$ms could not find: $1$file" && break
		done
	done
}

function addc(){
	arg=${1%%#- *}
	echo "$cfgs" | sed "s|$arg.*$|$1|"
	arg=${arg//'\n'/}
	[[ "$cfgs" == *$arg* ]] || echo "$1"
}

function start_seat(){ # $1 lease   $2 attach    $3 kiosk   $4 usbdvs  $5 pos

	echo -e "$ms Starting weston seat[$((pos++))] $1 ... $3 "

	useradd -m --badname user_$1 2>/dev/null

	chown user_$1 /home/user_$1 #|| exit 160
	chown user_$1 /var/local/run/drm-lease-manager/$1{,.lock} || exit 190

	while ! loginctl --no-pager seat-status seat_$1 2> /dev/null
	do
		loginctl attach seat_$1 $2
	done
	# allocate the drm, to make the seat active in case of all inputs disconnects
	( sleep ${5}69s ; loginctl attach seat_$1 /sys/devices/pci*/*/*/drm/card*/$1 )& #job+="$! "

			
	systemctl set-environment kiosk="$3"
	systemctl set-environment usbdvs="$4"
	systemctl restart multiseat-weston@$1.service || \
	  ( systemctl status multiseat-weston@$1.service -l --no-pager && exit 200 )

	while ! [ -e /run/user/$( id -u user_$1 )/wayland-1 ] ; do sleep $wait_time; done;
}

function get_usb_path_port() { # $1 = /dev/bus/usb/001/016
	 
	dev=$( basename $1 )
	bus=$( basename ${1/"$dev"/} )
	path=$( grep -Przl "BUSNUM=${bus}\nDEVNUM=$dev" /sys/devices/*/*/usb*/ 2> /dev/null )
	echo ${path/uevent/} # /sys/devices/pci0000:00/0000:00:1a.0/usb1/1-1/1-1.2
}


function set_usb_owner() { # $1 = /dev/bus/usb/001/016

	port=$( basename $( get_usb_path_port $1 ) 2> /dev/null )
	lease=$( grep -oz card.*$port $conf | grep -a card* | tail -n 1 )
	[[ "$lease" != "" ]] && [[ "${lease:0:1}" != "#" ]] && chown user_$lease $1
}



case "$1" in


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
	. $0 -b1
	. $0 -b2
	. $0 -b3
	;;

    "-b1") # build
	echo -e "$wb building tomlc parser ...."
	cd $ms_dir/tomlc99/
	make || exit 60
	make install || exit 70
	;;

    "-b2") # build
	echo -e "$wb building drm-lease-manager ...."
	cd $ms_dir/drm-lease-manager
	meson build || exit 80
	ninja -C build || exit 90
	ninja -C build install || exit 100
	;;

    "-b3") # build
	cd $ms_dir/weston
	echo -e "$wb Using pacman to remove previus weston installations ...."
	pacman -R weston --noconfirm
	echo -e "$wb Removing previus weston build ...."
	rm -r src/ pkg/
	echo -e "$wb Downloading and building weston ...."
	chown -R ${ms_dir##*/} ../weston/ || exit 105
	sudo -u${ms_dir##*/} makepkg -f --skippgpcheck || exit 110 # TODO: add user keys, del --skippgpcheck
	pacman -U weston-*.pkg.tar.zst --noconfirm || exit 120
	echo -e "$wb Building complete !!!"
	;;




    "-f") # disable config
	echo -e "$ms Flushing seats ...."
	while [ $( loginctl list-seats | wc -l ) -gt 4 ]
	do
		loginctl flush-devices
	done
	;;


    "-c") # update config file
	unset drm d mouse m keyboard k usbd u
        
	# find leaseable crtcs
	drm=( $( basename -a /sys/devices/pci*/*/*/drm/card*/card*) )
	d=${#drm[@]}

	# find ps2 devices
	for dev in /sys/class/input/input*/capabilities/key;
	do
		key_cap=( $(cat $dev | rev) )
		dev=${dev/'/capabilities/key'/}

		[[ $(cat $dev/phys) =~ usb.* ]] && continue

		dev_p_d="$( basename $( dirname $(cat $dev/phys)))	#- $(cat $dev/name))"

		[[ ${key_cap[0]} == efffffffffffffff ]]  && keyboard[$((k++))]="	ps2k $dev_p_d"

		[ "$(echo ${key_cap[4]} | rev)" \> "1" ] &&    mouse[$((m++))]="	ps2m $dev_p_d"

		done

	# find usb devices
	for dev in /dev/bus/usb/*/*;
       	do
		path_port=$( get_usb_path_port $dev )
		port=$( basename $path_port 2> /dev/null )
		[[ $port != *.* ]] && continue

		dev_id=$( cat $path_port/idVendor 2> /dev/null ):$( cat $path_port/idProduct 2> /dev/null )
		name=$( lsusb | grep " $dev_id " | head -n 1 )
		name=${name:33}
		serial="$( [ -e $path_port/serial ] && echo " - $( cat $path_port/serial )" )"
		dev_p_d="$port	#- $name$serial"


		[[ ${name,,} =~ .*keyboard.* ]] && keyboard[$((k++))]="	usbk $dev_p_d" && continue

		[[ ${name,,} =~ .*mouse.* ]]    && mouse[$((m++))]="	usbm $dev_p_d" && continue

		! [[ ${name,,} =~ .*\ hub\ .* ]] && usbd[$((u++))]="	usbd $dev_p_d" && continue
	done

	# update multiseat.conf with discovered devices
	cfgs=$( cat $conf 2> /dev/null )

	p=0 # create config for new devices
 	while [ $d -gt $p ] || [ $k -gt $p ] || [ $m -gt $p ] || [ $u -gt $p ]
	do
		[ $d -gt $p ] && cfgs=$(addc "\n$( ([ $p -ge $k ] && [ $p -ge $m ]) && echo '#')${drm[$p]}")
		[ $k -gt $p ] && cfgs=$(addc "${keyboard[$p]}" )
		[ $m -gt $p ] && cfgs=$(addc "${mouse[$p]}" )
		[ $u -gt $p ] && cfgs=$(addc "${usbd[$p]}" )
		p=$((p+1))
	done

	echo -e "$cfgs" > $conf
	;;





    "-d") # dlm service
	echo -e "$ms Starting drm-lease-manager services ... "	
	
	wait_files "/dev/dri/" "$( grep ^card[0-9] $conf -o )"

	systemctl start `systemd-escape --template=multiseat-dlm@.service /dev/dri/card*` || exit 180 # udev ?
	
	wait_files "/var/local/run/drm-lease-manager/" "$( grep ^card* $conf )"
	;;




    "-r") # read config and start_seat     $2 seat name or pos
	# set "master-of-seat" on input devices
        sed -i 's/SUBSYSTEM=="input", KERNEL=="input\*", TAG+="seat"$/&, TAG+="master-of-seat"/' \
	        /usr/lib/udev/rules.d/71-seat.rules || exit 140
	udevadm control --reload && udevadm trigger || exit 150

        cfgs=$( cat $conf 2> /dev/null )
	cfgs=$( echo -e "$cfgs" | sed -e "s/#.*//g ;s/[\t]//g; /^[[:space:]]*$/d" ) # remove comments

	pos=0
	unset attach lease kiosk usbd
	IFS=$'\n'
	for cfg in $cfgs eof
	do
		if [[ ${cfg:0:4} == "ps2k" ]] || [[ ${cfg:0:4} == "ps2m" ]]; then

			attach+="$( echo /sys/devices/platform/*/${cfg:5}/input/input*/ ) "

		elif [[ ${cfg:0:4} == "usbm" ]] || [[ ${cfg:0:4} == "usbk" ]]; then

			attach+="$( echo /sys/devices/pci*/*/usb*/*/${cfg:5}/*/*/input/input*/ ) "

		elif [[ ${cfg:0:4} == "open" ]]; then

			kiosk=${cfg:5}

		elif [[ ${cfg:0:4} == "usbd" ]]; then

			usbd+="${cfg:5} " #set_usb_owner() qemu: add_device $server/seat*/qemu_qmp.socket

		elif [[ ${cfg:0:4} == "card" ]] || [[ ${cfg:0:4} == "eof" ]]; then

			if [[ "$lease" != "" ]] ; then
				[[ "$2" == ""  ]] || [[ "$2" == "$lease" ]] || [[ "$2" == "$((pos++))" ]] \
				&& start_seat $lease "$attach" "$kiosk" "$usbd" $pos
			fi
			lease=$cfg
			unset attach kiosk usbd
		fi
	done

	;;



    "-s") # start services
	. $0 -Q # quit services
	. $0 -d # start dlm-lease-manager services
	. $0 -r # start weston seats services

	O=$(loginctl | grep root) && loginctl kill-session ${O:0:7}
	systemctl stop getty*
	deallocvt
	;;



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


    "-j") # journal logs 
	#journalctl -xe -u multiseat* 
	journalctl -S -15h -t sh -t multiseat.sh
	;;

    "-a") # auto
	. $0 -b
	. $0 -c
	. $0 -s
	;;

    *)
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
		 -f 		Free/Flush/Disable config
		 -j 		Journal logs

		 type 'systemctl enable multiseat' to run at boot and replace agetty
		 after system upgrades, its recommended to run -b3 then -c
		 before download again run:  rm -R $ms_dir
		 kiosk app will fail: without connected drm output, or with weston >= 10.0.94
		 last error: echo \$?
		EOF
	;;
esac
