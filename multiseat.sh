#!/bin/bash

# tomlc, drm lease manager and weston 13.0.1 builder on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution

# [[ "-S" == "$1" ]] && systemctl disable multiseat # comment this line when reboot is working

ms_dir="/home/multiseat"

site=(	"https://raw.githubusercontent.com/garlett/multiseat/13.0.1/patch/" \
	"https://gerrit.automotivelinux.org/gerrit/gitweb?p=AGL/meta-agl-devel.git;a=blob_plain;f=meta-agl-drm-lease/recipes-graphics/weston/weston/"\
	"https://gitlab.archlinux.org/archlinux/packaging/packages/weston/-/raw/main/" \
)
patch=(	"'${site[0]}0001-backend-drm-Add-method-to-import-DRM-fd.patch'" \
	"'${site[0]}0002-Add-DRM-lease-support.patch'" \
	"'${site[0]}0001-compositor-do-not-request-repaint-in-output_enable.patch'" \
#	"'${site[1]}0003-launcher-do-not-touch-VT-tty-while-using-non-default.patch'" \	# merged already
#	"'${site[1]}0004-launcher-direct-handle-seat0-without-VTs.patch'" \		# merged already
)

wait_time=0.1s	# time between exist checks 




if [ "$EUID" -ne 0 ]
then 
	echo -e "$wb Please run this as root"
	exit
fi

red="\e[1;31m"
white="\e[0m"
wb="$red[Weston Builder]$white"
ms="$red[MultiSeat]$white"
oIFS=$IFS

shopt -s nullglob



function wait_files(){ # $1 path    $2 files
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


# wait vga cards
vga_count=$( lspci | grep VGA | wc -l )
while [ $vga_count -gt 0 ]
do
	wait_files /sys/class/drm/ card$((--vga_count))
done

# config file based on current hardware path configuration
conf=$( echo /sys/devices/pci*/*/*/drm/card*/card* /sys/devices/pci*/*/drm/card*/card* )
[[ "$conf" != "" ]] && conf=/etc/multiseat_$( basename -a $conf | tr -cd "[:alnum:]" ).conf
conf=${conf//card/}
[[ "$conf" != "" ]] && ln -sf $conf /tmp/multiseat.conf
! [ -e "$conf" ] && [[ "-S" == "$1" ]] && ( echo -e "$ms Config '$conf' not found!"; systemctl start getty@tty1.service ; killall multiseat.sh )




function set_usb_owner() { #  $1 user        $2 2-1.3
	usbdev=$( grep -h "DEVNAME=.*$" /sys/devices/*/*/usb2/driver/$2/uevent | head -n 1 )
	[[ "$usbdev" != "" ]] && chown $1 /dev/${usbdev/"DEVNAME="/} # /dev/bus/usb/002/003
} # qemu: add_device $server/seat_$1/qemu_qmp.socket


function start_guard(){ # "$0-VGA-1;dev1;dev2... \n seat;....  "

	echo -e "$ms Starting seat guard ... "
	while : ;
	do
		IFS=$'\n'
		for seat in $1
		do
			unset er kiosk
			IFS=';'
			for dev in $seat
			do
				[[ "$dev" == "" ]] && continue

				[[ "$er" == "" ]] && er=$( basename $dev ) && er=${er/card/}

				[[ "$er" != "" ]] && [[ "$kiosk" == "" ]] && kiosk="$dev " && continue

				[[ "${dev:0:12}" != "/sys/devices" ]] && set_usb_owner u$er $dev && continue
		
				loginctl attach seat_$er $dev &
			done
		done
		
		[ $((x++)) -gt 0 ] && x=0;
		grep -q speed /proc/mdstat && \
			for led in /sys/class/leds/input*scrolllock/brightness ;
			do
				echo $x > $led ;
			done
		sleep $2
	done
	IFS=$oIFS
}


function start_seat(){  # /sys/card;kiosk;/sys/dev1;/sys/dev2;2-1.6=usb

	echo -e "$ms start_seat $3 $2 $1"
	unset er kiosk usbdvs
	IFS=';'
	for dev in $1
	do
		[[ "$er" != "" ]] && [[ "$kiosk" == "" ]] && kiosk="$( [[ "$dev" != "" ]] && echo "--shell=kiosk-shell.so") $dev" && continue

		[[ "$er" == "" ]] && er=$( basename $dev ) && er=${er/card/}

		[[ "${dev:0:12}" != "/sys/devices" ]] && usbdvs+=" $dev" && continue
		
		[[ "$2" != "" ]] && [[ "$2" != "$3" ]] && [[ "$2" != "$er" ]] && echo -e "$ms ignoring seat $3 " && return
		
		count=29 # timeout * $wait_time
		while [[ $( loginctl --no-pager seat-status seat_$er 2> /dev/null ) != *$( basename $dev )* ]]
		do
			sleep $wait_time
			[ $((count--)) -lt 0 ] && echo -e "$ms [warn] seat_$er does not have: $( basename $dev )" && break
		done
		
	done
	IFS=$oIFS

	wait_files /var/local/run/drm-lease-manager/ "card$er card$er.lock"
	useradd -m --badname u$er 2>/dev/null
	chown u$er: -R /home/u$er #|| exit 160
	chown u$er: /var/local/run/drm-lease-manager/card$er{,.lock} || exit 190

	systemctl set-environment usbdvs="$usbdvs"
	systemctl set-environment kiosk="$kiosk"
	systemctl restart multiseat-weston@$er.service || \
	  ( systemctl status multiseat-weston@$er.service -l --no-pager && exit 200 )
}




function get_conf(){ # $1 [ seat name || seat pos ]

	unset attach lease kiosk usbd guard seats
        cfgs=$( cat $conf 2> /dev/null )
	cfgs=$( echo -e "$cfgs" | sed -e "s/#.*//g ;s/[\t]//g; /^[[:space:]]*$/d" ) # remove comments
	pos=0

	oIFS=$IFS
	IFS=$'\n'
	for cfg in $cfgs eof
	do
		IFS=$oIFS
		case ${cfg:0:4} in

			"ps2k" | "ps2m" )
				attach+=" $( echo /sys/devices/platform/*/${cfg:5}/input/input* )"
				;;


			"usbm" | "usbk" )
				attach+=" $( echo /sys/devices/pci*/*/usb2/driver/[0-9]${cfg:6}/*/*/input/input* )"
				;; # path set to usb2 istead of usb*   # after usb: driver or * ?

			"open" )
				kiosk="${cfg:5}"
				;;

			"usbd" )
				attach+=" $( basename /sys/devices/*/*/usb2/driver/[0-9]${cfg:6} )" # attach+=" ${cfg:5}" 
				;;

			"spkr" )
				attach+=" $( echo /sys/devices/pci*/*/sound/card${cfg:5} )"
				;;

			"card" | "eof" )

				if [[ "$lease" != "" ]]
				then
					if [[ "$2" == "" ]] || [[ "$2" == "$lease" ]] || [[ "$2" == "$pos" ]]
					then
						echo "$( echo /sys/devices/pci*/*/{,*/}drm/card*/card$lease );$kiosk${attach// /;}"
					fi
					pos=$((pos+1))
				fi
				lease=${cfg//card/}
				unset attach kiosk
				;;
		esac
		
	done
}



# reads global var $cfgs, updates or appends it with config from $1, then outputs on stdout
function addc(){  # $1 new config
	arg=${1%%#- *}
	echo "$cfgs" | sed "s|$arg.*$|$1|"
	arg=${arg//'\n'/}
	[[ "$cfgs" == *$arg* ]] || echo "$1"
}



case "$1" in


    "-l") # create services and links
	echo -e "$wb creating systemctl services ...."
	ms_path=$( cd $( dirname $0 ) && pwd )/$( basename $0 )

	cat <<- EOF > /etc/systemd/system/multiseat.service
		[Unit]
		Description=MultiSeat Starter
		#After=systemd-user-sessions.service
		Requires=multi-user.target
		After=multi-user.target
		Conflicts=getty@tty1.service

		[Service]
		ExecStart=$ms_path -S
		ExecStopPost=$ms_path -q
		RemainAfterExit=yes
		Type=idle

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
		User=u%i
		
		#Type=notify
		#ExecStart=/bin/sh -c "/usr/bin/weston --seat=seat_%i --drm-lease=card%i -Bdrm-backend.so --modules=systemd-notify.so ${kioski:0:22}"
		
		# use the following if you want weston as kiosk parent
		Type=simple
		ExecStart=/bin/sh -c "( while [ -v kiosk ] && ! [ -e ${XDG_RUNTIME_DIR}/wayland-1 ] ; do sleep 0.2s; done; ${kiosk:22} ) & x=1; /usr/bin/weston --seat=seat_%i --drm-lease=card%i -Bdrm-backend.so ${kiosk:0:22}"
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
		User=u%i
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
		libgles pango lcms2 mtdev libva colord pipewire wayland-protocols freerdp freerdp2 patch neatvnc \
		xorg-xwayland xcb-util-cursor || exit 40

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
	wget "${site[2]}PKGBUILD" || exit 55
	echo "source+=( ${patch[@]} ); sha256sums+=( SKIP{,,} ); source[2]=\"${site[2]}\${source[2]}\"" >> PKGBUILD
	;;


    "-b") # build
	[ -d $ms_dir ] || ( $0 -l ; $0 -g ) # links and git clones 
	$0 -b1
	$0 -b2
	$0 -b3
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
	echo -e "$wb Removing previus weston build and source code ...."
	rm -r pkg/ src/

	echo -e "$wb Downloading weston ...."
	chown -R ${ms_dir##*/} ../ || exit 105
	sudo -u${ms_dir##*/} makepkg --nobuild --skippgpcheck --noprepare || exit 110

	echo -e "$wb Building weston ...."
	sudo -u${ms_dir##*/} makepkg --force --skippgpcheck || exit 110 # TODO: add user keys, del --skippgpcheck

	echo -e "$wb Using pacman to remove previus weston installations ...."
	pacman -R weston --noconfirm

	echo -e "$wb Installing weston ...."
	pacman -U weston-*.pkg.tar.zst --noconfirm || exit 120
	
	echo -e "$wb Instalation complete !!!"
	;;




    "-f") # disable config
	echo -e "$ms Flushing seats ...."
	while [ $( loginctl list-seats | wc -l ) -gt 4 ]
	do
		loginctl flush-devices
	done
	echo -e "$ms Flushed."
	;;


    "-c" | "-C" ) # update config file
	unset drm mouse keyboard usbd audio spkr 
        d=0
        m=0
	k=0
	u=0
	a=0
	s=0

	# find leaseable crtcs
	drm=($( basename -a /sys/devices/pci*/*/*/drm/card*/card* /sys/devices/pci*/*/drm/card*/card* ) )
	d=${#drm[@]}

	# find audio devices
#	for dev in /sys/devices/pci*/*/sound/card*/input* 
#	do
#		spkr[$((s++))]="spkr $(echo "$dev" | sed 's|/sys/[^ ]*sound/card||g')	#- $(cat $dev/name)"
#	done


	# find ps2 devices
	for dev in /sys/class/input/input*/capabilities/key;
	do
		key_cap=( $(cat $dev | rev) )
		dev=${dev/'/capabilities/key'/}

		[[ $(cat $dev/phys) =~ usb.* ]] && continue

		dev_p_d="$( basename $( dirname $(cat $dev/phys)))	#- $(cat $dev/name))"

		[[ ${key_cap[0]} == efffffffffffffff ]]  && keyboard[$((k++))]="ps2k $dev_p_d"

		[ "$(echo ${key_cap[4]} | rev)" \> "1" ] &&    mouse[$((m++))]="ps2m $dev_p_d"

		done

	# find usb devices
	for path_port in /sys/devices/*/*/usb2/driver/*.*
       	do
		port=$( basename $path_port 2> /dev/null )
		[[ $port != *.* ]] && continue

		dev_id=$( cat $path_port/idVendor 2> /dev/null ):$( cat $path_port/idProduct 2> /dev/null )
		name=$( lsusb | grep " $dev_id " | head -n 1 )
		name=${name:33}
		serial="$( [ -e $path_port/serial ] && echo " - $( cat $path_port/serial )" )"
		dev_p_d="$port	#- $name$serial"


		[[ ${name,,} =~ .*keyboard.* ]] && keyboard[$((k++))]="usbk $dev_p_d" && continue

		[[ ${name,,} =~ .*mouse.* ]]    && mouse[$((m++))]="usbm $dev_p_d" && continue

		! [[ ${name,,} =~ .*\ hub\ .* ]] && usbd[$((u++))]="usbd $dev_p_d" && continue
	done

	# update $conf with discovered devices
	cfgs=$( cat $conf 2> /dev/null )
	[[ "$cfgs" == ""  ]] && cfgs="#	open alacritty -e /home/login.sh"

	p=0 # create config for new devices
 	while [ $d -gt $p ] || [ $s -gt $p ] || [ $k -gt $p ] || [ $m -gt $p ] || [ $u -gt $p ]
	do
		[ $d -gt $p ] && cfgs=$(addc "\n$( ([ $p -ge $k ] && [ $p -ge $m ]) && echo '#')${drm[$p]}")
		[ $s -gt $p ] && cfgs=$(addc "	${spkr[$p]}" )
		[ $k -gt $p ] && cfgs=$(addc "	${keyboard[$p]}" )
		[ $m -gt $p ] && cfgs=$(addc "	${mouse[$p]}" )
		[ $u -gt $p ] && cfgs=$(addc "	${usbd[$p]}" )
		p=$((p+1))
	done

	echo -e "$cfgs" > $conf
	[[ "$1" == "-C"  ]] && echo -e "$ms now you should edit $conf ..." || sleep 2s && vim $conf
	;;



    "-r") # read config and start_seat     $2 seat name or pos
	
	# set "master-of-seat" on input devices
        sed -i 's/SUBSYSTEM=="input", KERNEL=="input\*", TAG+="seat"$/&, TAG+="master-of-seat"/' \
	        /usr/lib/udev/rules.d/71-seat.rules || exit 140
	udevadm control --reload && udevadm trigger || exit 150


	cfgs="$( get_conf $2 )"

	#ps -fC multiseat.sh > /dev/null ||
	[[ "$2" == "" ]] && start_guard "$cfgs" 1.69s &

	pos=0
	IFS=$'\n'
	for seat in $cfgs
	do
		start_seat "$seat" "$2" $pos &
		seats+="$! "
		pos=$(( pos+1 ))
	done
	IFS=$oIFS
	[[ "$seats" != "" ]] && wait $seats

	;;



    "-d") # dlm service
	
	echo -e "$ms Starting drm-lease-manager services ... "	
	
	wait_files "/dev/dri/" "$( grep "^card[0-9]" $conf -o )"  # wait configured cards

	systemctl start `systemd-escape --template=multiseat-dlm@.service /dev/dri/card*` || exit 180 # udev ?

	wait_files "/var/local/run/drm-lease-manager/" "$( grep "^card*" $conf )" # wait configured crtcs 
	;;


    "-s" | "-S") # start services

#	. $0 -Q # quit services
	. $0 -d # start dlm-lease-manager services
	. $0 -r # start weston seats services

	[[ "$1" == "-s" ]] && read -p " waiting to stop root session ..."
	O=$(loginctl | grep root) && loginctl kill-session ${O:0:7}
	systemctl stop getty*
	deallocvt
	;;



    "-q" | "-Q") # quit services
	echo -e "$ms Stopping ... "
	systemctl stop "multiseat-weston*" "multiseat-dlm*"
	rm /var/local/run/drm-lease-manager/* >& /dev/null
	
	if [[ "$1" == "-q" ]] # looks better with service
	then
		systemctl start getty@tty1.service
		echo -ne '\007' > /dev/tty6
		sleep 1s
		chvt 2
		echo -ne '\007' > /dev/tty6
		chvt 1
		deallocvt
		echo -ne '\007' > /dev/tty6
	fi

	;;


    "-j") # journal logs 
	#journalctl -xe -u multiseat* 
	journalctl -S -12h -t sh -t multiseat.sh
	;;

    "-a") # auto
	. $0 -b
	. $0 -c
	. $0 -s
	;;

    *)
	echo -e	"$ms github.com/garlett/multiseat \n    argument $1"
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
		 -f 		Free/Flush/Disable config
		 -j 		Journal logs

		 Type 'systemctl enable multiseat' to run at boot and replace agetty
		 After system upgrades, you may need to run -b3 and -c
		 After update multiseat.sh, its recommended to run -l
		 Before download again run:  rm -R $ms_dir
		 Kiosk app will fail: without connected drm output
		 Last error: echo \$?
		EOF
	;;
esac
