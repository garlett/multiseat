#!/bin/bash

# tomlc, drm lease manager, wlroots and labwc builder on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution

# [[ "-S" == "$1" ]] && systemctl disable multiseat # uncomment this line until reboot is working

ms_dir="/home/multiseat"
wait_time=0.31s	# time between exist checks 
guest_login_cmd="xfce4-terminal --fullscreen --hide-menubar --hide-scrollbar --zoom=4 -e /home/login.sh"
default_compositor="labwc ; sfwbar ; pcmanfm-qt --desktop" #; swayidle -w timeout 420 'wlopm --off \*' resume 'wlopm --on \*'
create_home=no # create home folder for new users [yes|no]

#echo echo$((e++)) >&2

#XDG_RUNTIME_DIR=/run/user/1060 xfce4-terminal --fullscreen -e 'watch -n.1 "dmesg -T | tail -n 25"'

if [ "$EUID" -ne 0 ]
then 
	echo -e "$wb Please run this as root"
	exit 10
fi

red="\e[1;31m"
white="\e[0m"
wb="$red[MultiSeat Builder]$white"
ms="$red[MultiSeat]$white"
oIFS=$IFS
isnumber='^[0-9]+$'

shopt -s nullglob

function sli(){ # scroll lock invert
	for led in /sys/class/leds/input*scrolllock/brightness ;
	do
		echo $(( $( cat $led ) ^ 1 )) > $led ;
	done
	sleep 1s
}



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
	return 0
}


# wait vga cards
vga_count=$( lspci | grep VGA | wc -l )
while [ $vga_count -gt $( echo /sys/class/drm/card[0-9] | wc -w ) ]
do
	sleep $wait_time #wait_files /sys/class/drm/ card$((--vga_count))
done

# config file name based on current hardware path configuration
conf=$( echo /sys/devices/pci*/*/{,*/}drm/card*/card* )
[[ "$conf" != "" ]] && conf=/etc/multiseat/_$( basename -a $conf | tr -cd "[:alnum:]" ).conf
conf=${conf//card/}

[[ "$conf" != "" ]] && ln -sf $conf /tmp/multiseat.conf
! [ -e "$conf" ] && [[ "-S" == "$1" ]] && ( echo -e "$ms Config '$conf' not found!"; systemctl start getty@tty1.service ; killall multiseat.sh )




function start_seat2(){  # $1 lease    $2 user

	# do not restart when running from inside seat
	[[ "$XDG_SEAT" == "seat-$1" ]] && exit
	
	echo -e "$ms start_seat: lease $1 arg '$2'"
	
	systemctl stop multiseat-$1 2> /dev/null 
	systemctl reset-failed       	


	IFS=\;
	apps=( $( get_conf2 open $1 ) )
	comp=( $( get_conf2 comp $1 ) )
	[[ ${comp[@]} == "" ]] && comp=( $default_compositor )

	if [[ "$2" == "" ]] || [[ $2 == 'guest' ]]
	then
		if [[ $2 == 'guest' ]]
		then
			apps=( $guest_login_cmd )
			comp=( ${comp[0]} sfwbar ) # change to greeter with idle_timer display turn off
		fi
		user=${1/card/u}
		user=${user,,}
	else
		user=$2
	fi
	IFS=$oIFS
	resta="--property=RestartSec=1s --property=Restart=always "
	param="$( [[ ${comp[0]} == "weston" ]] && echo --drm-lease=$1 ) "
 	user_id=$( id -u $user )
  	envs="--uid=$user_id "


	useradd $user --no-user-group 2> /dev/null
	if [ ! -d /home/$user/.config/labwc ]
	then
		if [[ "$create_home" == "yes" ]] then
			mkdir -p /home/$user/{Desktop,.config}
			ln -s /etc/multiseat/labwc/ /home/$user/.config/
			chown $user: -R /home/$user
		else
			mkdir -p /tmp/$user/{Desktop,.config}
			ln -s /etc/multiseat/labwc/ /tmp/$user/.config/
			chown $user: -R /tmp/$user
			
			[ -d /home/$user/ ] || ln -s /tmp/$user/ /home/$user
		fi
	fi


	wait_files /var/local/run/drm-lease-manager/ "$1 $1.lock"
	chown $user: /var/local/run/drm-lease-manager/$1{,.lock} || exit 20

	# compositor
	systemctl set-environment \
		SEATD_VTBOUND=0 \
		XDG_SESSION_TYPE=wayland \
		XKB_DEFAULT_LAYOUT=br \
		XDG_SEAT=seat-$1 \
		DRM_LEASE=$1 \
		usbdvs="$( get_conf2 usbd $1 )" \
		open=""
	systemd-run $envs $resta --unit=multiseat-$1 --property=PAMName=login --property=ExecStartPre="/bin/sleep .001" ${comp[0]} $param # -dVVV 
									# sleep: wlroots or systemd is not openning session on first try
	wait_files /run/user/$user_id/ wayland-0{,.lock}


	envs+="--property=After=multiseat-$1.service "
	envs+="--property=PartOf=multiseat-$1.service "
	envs+="--setenv=XDG_CURRENT_DESKTOP=wlroots "
	envs+="--setenv=WAYLAND_DISPLAY=wayland-0 " # pam_systemd: using one guest user, conflicts on this 4 lines
 	envs+="--setenv=XDG_RUNTIME_DIR=/run/user/$user_id " 
	envs+="--setenv=DBUS_SESSSION_BUS_ADDRESS=unix:path=/run/user/$user_id/bus "
	envs+="--setenv=DISPLAY=$( basename $( find /tmp/.X11-unix/ -maxdepth 1 -user $user ) | tr X : ) "
	
	# auto restart services
 	for serv in "${comp[@]:1}"
 	do
		systemd-run $envs $resta $serv
	done

	# run once applications
	for app in "${apps[@]}"
	do
		systemd-run $envs $app
	done
}




function get_conf2(){ #  $1 field    $2 card || seat pos || ""

	# load cfgs, remove comments, append EOF delimiter
	cfgs=$( sed -e "s/[[:space:]]*#.*//g ;s/[\t]//g; /^[[:space:]]*$/d" $conf )$'\n'cardcard
	
	# return cards list
	[[ "$1" == "card" ]] && [[ "$2" == "" ]] && echo -e "$cfgs" | grep "^card[0-9]" 
	[[ "$2" == "" ]] && return
	
	# convert pos to card name
	[[ "$2" =~ $isnumber ]] && card=$( echo -e "$cfgs" | grep -m$2 "^card" | tail -n1 ) || card="card${2/card/}"

	# select card configs
	card_cfgs=$( echo  "$cfgs" | grep -Pzo "(?s)\Q$card\E.*?(?=\Qcard\E)" | tr -d '\0' )

	IFS=$'\n'
	for cfg in $card_cfgs
	do
#echo $cfg >&2		
		case ${cfg:0:4} in
			
			"card")
				[[ $1 == "card" ]] && echo -n "" ${cfg}
				;;

			"comp")
				[[ $1 == "comp" ]] && echo -n "" ${cfg:5}
				;;

			"open")
				[[ $1 == "open" ]] && echo -n "" ${cfg:5}
				;;
			
			"spkr")
				[[ $1 == "spkr" ]] && echo -n "" /sys/devices/pci*/*/sound/card${cfg:5}
				;;
				
			"ps2k" | "ps2m")
				[[ $1 == "devs" ]] && echo -n "" /sys/devices/platform/*/${cfg:5}/input/input*
				;;

			"usbm" | "usbk")
				unset dev
				[[ $1 == 'devs' ]] && dev=$( echo /sys/bus/usb/devices/*${cfg:17} )
				[[ $dev != '' ]] && echo -n "" $( readlink -f ${dev// /$'\n'/} | grep ${cfg:5:12} | sort -u )/*-*/*/input/input*
				;; 

			"usbd") # usbX 1d.0-1.4.4
				unset dev
				[[ $1 == 'usbd' ]] && dev=$( echo /sys/bus/usb/devices/*${cfg:17} )
				[[ $dev != '' ]] && dev=$( readlink -f ${dev// /$'\n'/} | grep ${cfg:5:12} | sort -u ) 
				[[ $dev != '' ]] && echo -n "" $( basename -a ${dev// /$'\n'/} )
				;;
		esac
	done
	IFS=$oIFS
}

#get_conf2 $1 1 ; echo ----
#get_conf2 $1 2 ; echo ----
#get_conf2 $1 3 ; echo ----
#get_conf2 $1 4 ; echo ----
#exit




case "$1" in


    "-l") # create service and links
	echo -e "$wb creating systemctl services ...."
	ms_path=$( cd $( dirname $0 ) && pwd )/$( basename $0 )

	cat <<- EOF > /etc/systemd/system/multiseat.service
		[Unit]
		Description=MultiSeat Launcher
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
	systemctl daemon-reload

	echo -e "$wb soft linking library files from /usr/local/... to /usr/..."
	cd /usr/
	mkdir -p include/libdlmclient local/lib/pkgconfig 
	for file in include/{libdlmclient/dlmclient.h,toml.h} lib/pkgconfig/{libdlmclient.pc,libtoml.pc} lib/{libdlmclient.so.0,libtoml.so,libwlroots-0.18.so}
	do
		! [ -e $file ] && ( ln -s /usr/local/$file $( dirname $file ) || exit 30 )
	done
	# ? change this to ldconfig or PKGBUILD (pacman can handle dependencies)(needs noupdate on pacman.conf)
		
	echo -e "$wb creating build+cfg directories ..."
	mkdir -p $ms_dir
	mkdir -m 2750 /etc/multiseat
	chown -R :users /etc/multiseat
	;;


    "-gp") # git clones
	echo -e "$wb installing required packages ...."
	pacman -S --noconfirm --needed git make meson ninja wget alacritty gcc cmake pkgconfig libdrm sudo \
		fakeroot wayland libxkbcommon libinput libunwind pixman cairo libjpeg-turbo libwebp mesa libegl \
		libgles pango lcms2 mtdev libva colord pipewire wayland-protocols freerdp freerdp2 patch neatvnc \
		libxml2 glib2 hwdata libdisplay-info libliftoff xorg-xwayland libxcb xcb-util-renderutil xcb-util-wm \
		gtk-layer-shell pcmanfm-qt xfce4-terminal || exit 40 # swayidle 

	# redo this with requeriments for: wlroots, labwc, sfwbar, pcmanfm-qt  ## maybe pacman --somenthing_like__install_required
	# download sfwbar config to /etc/multiseat/{sfwbar/,labwc/} and set config location as argument?
    ;;


    "-g" | "-b") # $2 app index

	if [[ "$2" == "" ]]
	then 
		for i in {0..5} 
		do 
			$0 $1 $i 
		done 
		exit
	fi

	[ -d $ms_dir ] || ( $0 -l ; $0 -gp ) # links and pacman

	cd $ms_dir || exit 50

	href=( 'gitlab.freedesktop.org/wlroots/wlroots' 'github.com/labwc/labwc' 'github.com/LBCrion/sfwbar' \
		'github.com/cktan/tomlc99' 'gerrit.automotivelinux.org/gerrit/src/drm-lease-manager' 'git.sr.ht/~leon_plickat/wlopm' \
		 )

	name=$( basename ${href[$2]} )
	if ! cd $name/ 2> /dev/null || [[ "$1" == "-g" ]]
	then
		echo -e "$wb clonning/updating ($1 $2) $name ...."

		if [[ "$name" != $( basename $( pwd ) ) ]]
		then
			git clone "https://${href[$2]}" || exit 60
			cd $name
		fi

		git reset --hard
		branch=( '0.19' )
		[[ "${branch[$2]}" != "" ]] && git checkout ${branch[$2]}
		git pull
		
	
		patch_href=( 'raw.githubusercontent.com/garlett/multiseat/refs/heads/wlroots-0.18/multiseat' ) # /wlroots
		if [[ "${patch_href[$2]}" != "" ]]
		then
			echo -e "$wb patching with $( basename ${patch_href[$2]} ) ...."
			wget "https://${patch_href[$2]}.patch" --output-document=p$2.patch
			patch -Np1 < p$2.patch
		fi

		echo -e "$wb applying configs ...."

	       	[[ "$name" == "tomlc99" ]] && mv libtoml.pc{.sample,}
		[[ "$name" == "labwc" ]] && ln -s $ms_dir/wlroots $ms_dir/labwc/subprojects/
		[[ "$name" == "sfwbar" ]] && ! grep -q idle_timer $ms_dir/sfwbar/config/sfwbar.config && sed -i 's/Function("SfwbarInit") {/Module("idle")\nTriggerAction "idle_timer", Exec "wlopm --off *"\nTriggerAction "idle_resume", Exec "wlopm --on *"\nFunction("SfwbarInit") {\n\tIdleTimeout "idle_timer", "420"\n\tExec "wlopm --on *"/' $ms_dir/sfwbar/config/sfwbar.config # ugly --- maybe lbcryon could make it native, or this should not be in multiseat
	fi

	
	if [[ "$1" == "-b" ]]
	then
		echo -e "$wb compiling $name ...."

		if [ -e Makefile  ]
		then
			make --always-make || exit 70
			make install || exit 80
		fi

		if [ -e meson.build ]
		then
			[ -e build/ ] && rm -R build/
			meson build || exit 70
			ninja -C build || exit 80
			ninja -C build install || exit 90
		fi
	fi
	chmod 755 -R .
	;;


    "-p")
	cd $ms_dir/wlroots || exit 50
	# git reset ? checkout ? 18.2 ?
	git remote add -f b "https://gitlab.freedesktop.org/garlett/wlroots-lease-multiseat.git"
	git remote update
	git diff master remotes/b/master > wlroots.patch
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
	drm=($( basename -a /sys/devices/pci*/*/{,*/}drm/card*/card* ) ) # find a non-pci path (and readlink -f ? )
	d=${#drm[@]}

	# this is not working for same reason as the drm lease, change to pulseaudio ?
	# find audio devices
	# 	for dev in /sys/devices/pci*/*/sound/card*/input* 
#	do
#		spkr[$((s++))]="spkr $(echo "$dev" | sed 's|/sys/[^ ]*sound/card||g')	#- $(cat $dev/name)"
#	done


	# find ps2 devices
	for dev in /sys/class/input/input*/capabilities/key;
	do
		key_cap=( $(cat $dev | rev) )
		dev=${dev/'/capabilities/key'/}

		[[ $(cat $dev/phys) =~ usb.* ]] && continue
		
		dev_p_d="$( basename $( dirname $(cat $dev/phys)))                                      "
		dev_p_d="${dev_p_d:0:29} #- $(cat $dev/name)"

		[[ ${key_cap[0]} == efffffffffffffff ]]  && keyboard[$((k++))]="ps2k $dev_p_d"

		[ "$(echo ${key_cap[4]} | rev)" \> "1" ] &&    mouse[$((m++))]="ps2m $dev_p_d"

		done

# config wizard (starts when: no cfg is found? shortcut or sleep button?)
#  use current preallocation
#  start a terminal asking the user to type a numeric code
#  rotate mouses until user close spawned terminal

	# find usb devices
	for dev in $( readlink -f /sys/bus/usb/devices/* ) # /sys/devices/pci0000:00/0000:00:1d.0/usb2/2-1/2-1.4/2-1.4.4
       	do
		port=${dev##*/}		# 2-1.4.4 or 2-1.4.4:0
		[[ $port =~ ':' ]] && continue

		dev_id=$( cat $dev/idVendor 2> /dev/null ):$( cat $dev/idProduct 2> /dev/null )
		name=$( lsusb | grep " $dev_id " | head -n 1 )
		name=${name:33}
		serial="$( [ -e $dev/serial ] && echo " - $( cat $dev/serial )" )"
		pci=${dev%/usb*}
		device="${pci##*/}-${port##*-}                                      "
		device="${device:0:29} #- $name$serial"

		[[ ${name,,} =~ .*keyboard.* ]] && keyboard[$((k++))]="usbk $device" && continue

		[[ ${name,,} =~ .*mouse.* ]]    && mouse[$((m++))]="usbm $device" && continue

		! [[ ${name,,} =~ .*hub.* ]] && usbd[$((u++))]="usbd $device" && continue
	done

	# load $conf
	cfgs=$( cat $conf 2> /dev/null )
	[[ "$cfgs" == ""  ]] && cfgs="# comp $default_compositor # open $guest_login_cmd"


	# reads global var $cfgs, updates or appends it with config from $1, then outputs on stdout
	function addc(){  # $1 new config
		arg=${1%%#- *} 					# remove comments from arg
		echo "$cfgs" | sed "s|$arg.*$|$1|"		# output updated $cfgs
		arg=${arg//'\n'/}				# remove newline from arg
		[[ "$cfgs" == *${arg:1}* ]] || echo "$1"	# if new cfg then append
	}

	p=0 # create/update config for devices
 	while [ $d -gt $p ] || [ $s -gt $p ] || [ $k -gt $p ] || [ $m -gt $p ] || [ $u -gt $p ]
	do
		[ $d -gt $p ] && cfgs=$(addc "\n$( ([ $p -ge $k ] && [ $p -ge $m ]) && echo '#')${drm[$p]}")
		[ $s -gt $p ] && cfgs=$(addc "	${spkr[$p]}" )
		[ $k -gt $p ] && cfgs=$(addc "	${keyboard[$p]}" )
		[ $m -gt $p ] && cfgs=$(addc "	${mouse[$p]}" )
		[ $u -gt $p ] && cfgs=$(addc "	${usbd[$p]}" )
		p=$((p+1))
	done

	#save $conf
	echo -e "$cfgs" > /tmp/multiseat_cfg.tmp
	[[ "$1" == "-C"  ]] && echo -e "$ms now you should edit $conf ..." || sleep 2s && vim /tmp/multiseat_cfg.tmp
	mv /tmp/multiseat_cfg.tmp $conf
	echo -e "$ms should we run -f before -c ?"
	;;


    "-f") # disable config
	echo -e "$ms Flushing seats ...."
	while [ $( loginctl list-seats | wc -l ) -gt 4 ]
	do
		loginctl flush-devices
	done
	echo -e "$ms Flushed."
	;;

    "-G") # function start_guard2(){
	echo -e "$ms Starting seat guard ($1) ... "
	
	while : ;
	do
		for card in $( get_conf2 card )
		do
			unset dev user usb
			seat_devs="$( loginctl seat-status seat-$card )" # avoid re-attach ( spare writes on /etc/udev/rules.d/* )
			for dev in /sys/devices/pci*/*/{,*/}drm/card*/$card $( get_conf2 devs $card )
			do
				[[ "$seat_devs" != *$dev* ]] && [[ $dev != *firmware* ]] && loginctl attach seat-$card $dev
			done #							^^ obsolete?


			# usb ownership ( qemu requires this )
			user=$( loginctl | grep user | grep $card | xargs | cut -d " " -f 3 )
			[[ "$user" == "" ]] && echo "$( date ) $card" >> /tmp/usb_user_fail.log && continue # user=${1,,}
			
			for usb in $( get_conf2 usbd $card )
			do
#				usbdev=$( echo /sys/devices/*/*/usb*/driver/$usb/uevent )
				usbdev=$( echo /sys/bus/usb/devices/$usb/uevent* )
				[[ "$usbdev" != "" ]] && usbdev=$( grep -h 'DEVNAME=.*$' $usbdev | head -n 1 )
				[[ "$usbdev" != "" ]] && chown $user /dev/${usbdev/'DEVNAME='/} # /dev/bus/usb/002/003
			done

		done

	# temp: avoid non-seat0 vt switch, because of recent loginctl/systemd versions
	# not working, freezing on hit shortcut
	#	s="$( loginctl | grep manager | grep -oE "^ +[0-9]" )"
 	#	[ "$s" =~ $isnumber ]] && loginctl terminate-session $s

		sleep 9s
#		grep -q speed /proc/mdstat 2> /dev/null && sli # raid keyboard status
	done
	;;


    "-d") # dlm transient service
	
	echo -e "$ms Starting drm-lease-manager services ... "	
	rm /var/local/run/drm-lease-manager/* 2> /dev/null

	wait_files "/dev/dri/" "$( grep "^card[0-9]" $conf -o )"  # wait configured cards
	
	for card in /dev/dri/card*
	do
		systemd-run $dlm_log --unit=dlm-$( basename $card ) drm-lease-manager $card
		# dlm only outputs when ran from terminal with no redirects
	done #--property=RestartSec=1s --property=Restart=always /usr/local/bin/

	wait_files "/var/local/run/drm-lease-manager/" "$( grep "^card*" $conf )" # wait configured crtcs 
	;;



    "-r") # read config and start_seat     $2 seat name or pos    $3 user name
	# set "master-of-seat" on input devices
        sed -i 's/SUBSYSTEM=="input", KERNEL=="input\*", TAG+="seat"$/&, TAG+="master-of-seat"/' \
	        /usr/lib/udev/rules.d/71-seat.rules || exit 110
	udevadm control --reload && udevadm trigger || exit 120

	for card in $( get_conf2 card $2 )
	do
		start_seat2 "$card" "$3"
		seats+="$! "
	done
	[[ "$seats" != "" ]] && wait $seats

	;;



    "-s" | "-S") # start services

	systemd-run $0 -G	# start guard service
	. $0 -d 		# start dlm-lease-manager services
	. $0 -r "" "guest" 	# start compositor seats services

	[[ "$1" == "-s" ]] && read -p " waiting to stop root session ..."
	O=$(loginctl | grep root) && loginctl kill-session ${O:0:7}
	systemctl stop getty*
	deallocvt
	;;



    "-q" | "-Q") # quit services
	echo -e "$ms Stopping ... "
	systemctl stop "multiseat-*" "dlm-*"
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
	journalctl -S -12h -t sh -t multiseat.sh -t systemd-run -t "(sh)" -t pcmanfm-qt
	;;

    "-a") # auto
	. $0 -b
	. $0 -c
	. $0 -s
	;;

    *)
	echo -e	"$ms github.com/garlett/multiseat \n    argument $1"
	cat <<- EOF
		 -b [ID]	[Git clone, link and] build
		 -c 		Create, review and enable config
		 -s 		Start drm-lease-manager and compositor services

		 -q 		Quit multiseat
		 -r [LEASE]  	Restart compositor seat service [with LEASE name or POS]
		 -d		Start drm-lease-manager
		 -g		Git clone repositories
		 -p		Create wlroots patch
		 -l		Create library links
		 -f 		Free/Flush/Disable config
		 -j 		Journal logs

		 Type 'systemctl enable multiseat' to run at boot and replace agetty
		 After system upgrades, you may need to run -b 1 and -c
		 After update multiseat.sh, its recommended to run -l
		 Before download again run:  rm -R $ms_dir
		 Kiosk app will fail: without connected drm output
		 Last error: echo \$?
		EOF
	;;
esac
