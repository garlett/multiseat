#!/bin/bash

# tomlc, drm lease manager, wlroots and labwc builder on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution

# [[ "-S" == "$1" ]] && systemctl disable multiseat # comment this line when reboot is working

ms_dir="/home/multiseat"

wait_time=0.1s	# time between exist checks 

guest_login_cmd="xfce4-terminal --fullscreen --hide-menubar --hide-scrollbar --zoom=4 -e /home/login.sh"

#echo echo$((e++)) >&2


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

# config file name based on current hardware path configuration
conf=$( echo /sys/devices/pci*/*/{,*/}drm/card*/card* )
[[ "$conf" != "" ]] && conf=/etc/multiseat/_$( basename -a $conf | tr -cd "[:alnum:]" ).conf
conf=${conf//card/}

[[ "$conf" != "" ]] && ln -sf $conf /tmp/multiseat.conf
! [ -e "$conf" ] && [[ "-S" == "$1" ]] && ( echo -e "$ms Config '$conf' not found!"; systemctl start getty@tty1.service ; killall multiseat.sh )




function start_seat2(){  # $1 lease    $2 user
	
	old_user=$( loginctl | grep $1 | xargs | cut -d " " -f 3 )
	[[ "$2" == "" ]] && user=${1/card/u} || user=$2
	user=${user,,}
	if [ ! -d /home/$user/ ] && [[ "$user" != "guest" ]]
	then
		useradd $user
		mkdir -p /home/$user/{Desktop,.config}
		ln -s /etc/multiseat/labwc/ /home/$user/.config/
		chown $user: -R /home/$user
	fi
	wait_files /var/local/run/drm-lease-manager/ "$1 $1.lock"
	chown $user: /var/local/run/drm-lease-manager/$1{,.lock} || exit 20

	echo -e "$ms start_seat: lease '$1'  arg '$2' user '$user'"
	systemctl set-environment SEATD_VTBOUND=0
	systemctl set-environment XDG_SESSION_TYPE=wayland
	systemctl set-environment XKB_DEFAULT_LAYOUT=br
	systemctl set-environment XDG_SEAT=seat-$1
	systemctl set-environment DRM_LEASE=$1
	systemctl set-environment usbdvs="$( get_conf2 usbd $1 )"
	systemctl set-environment open="$( [[ $user != 'guest' ]] && get_conf2 open $1 || echo "$guest_login_cmd" )"
	[[ "$old_user" != "" ]] && [[ "$old_user" != "$user" ]] && \
		systemctl stop    multiseat-compositor@$old_user.service
		systemctl restart multiseat-compositor@$user.service
}




function get_conf2(){ #  $1 field    $2 card || seat pos ] || ""

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

		case ${cfg:0:4} in

			"ps2k" | "ps2m")
				[[ $1 == "devs" ]] && echo /sys/devices/platform/*/${cfg:5}/input/input*
				;;

			"usbm" | "usbk")
				[[ $1 == "devs" ]] && echo $( readlink -f /sys/devices/pci*/*/usb2/driver/*${cfg:9} | grep ${cfg:5:4} )/*/*/input/input*
				;; # path set to usb2, because udev create links in both buses

			"usbd") # usbX 1d.0-1.4.4
				[[ $1 == "usbd" ]] && basename -a $( readlink -f /sys/devices/pci*/*/usb2/driver/*${cfg:9} | grep ${cfg:5:4} )
				;;
			
			"open")
				[[ $1 == "open" ]] && echo ${cfg:5}
				;;
			
			"spkr")
				[[ $1 == "spkr" ]] && echo /sys/devices/pci*/*/sound/card${cfg:5}
				;;
				
			"card")
				[[ $1 == "card" ]] && echo $cfg
				;;
		esac
	done
	return 0
}


function start_guard2(){
	echo -e "$ms Starting seat guard ($1) ... "
	
	while : ;
	do
		for card in $( get_conf2 card )
		do
			unset attach
			seat_devs="$( loginctl seat-status seat-$card )" # avoid re-attach ( spare writes on /etc/udev/rules.d/* )
			for dev in /sys/devices/pci*/*/{,*/}drm/card*/$card $( get_conf2 devs $card )
			do
				[[ "$seat_devs" != *$dev* ]] && attach+=" $dev"
			done
			[[ "$attach" != "" ]] && loginctl attach seat-$card $attach
#			loginctl attach seat-$card /sys/devices/pci*/*/{,*/}drm/card*/$card $( get_conf2 devs $card )

# TODO labwc reload devices, because it cant use newly attached devices

			user=$( loginctl | grep $card | xargs | cut -d " " -f 3 )
			[[ "$user" == "" ]] && echo "$card $usb" >> /tmp/usb_fail.log && continue # user=${1,,}
			
			for usb in $( get_conf2 usbd $card )
			do
				usbdev=$( grep -h "DEVNAME=.*$" /sys/devices/*/*/usb2/driver/$usb/uevent | head -n 1 )
				[[ "$usbdev" != "" ]] && chown $user /dev/${usbdev/"DEVNAME="/} # /dev/bus/usb/002/003
			done
		done

		# temp: avoid non-seat0 vt switch, because of recent loginctl/systemd versions
		s="$( loginctl | grep manager | grep -oE "^ +[0-9]" )"
 		[[ "$s" =~ $isnumber ]] && loginctl terminate-session $s

		# raid keyboard status
		[ $((x++)) -gt 0 ] && x=0;
		grep -q speed /proc/mdstat && \
			for led in /sys/class/leds/input*scrolllock/brightness ;
			do
				echo $x > $led ;
			done
		sleep $1
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

	cat <<- EOF > /etc/systemd/system/multiseat-dlm@.service
		[Unit]
		Description=Drm Lease Manager
		After=systemd-user-sessions.service

		[Service]
		#Type=forking notify Group=video UMask=0007
		ExecStart=/usr/local/bin/drm-lease-manager %I
		EOF

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

	cat <<- 'EOF' > /etc/systemd/system/multiseat-compositor@.service
		[Unit]
		Description=Multiseat Compositor Launcher
		After=systemd-user-sessions.service

		[Service]
		PAMName=login
		User=%i
		
		Type=simple
		#ExecStart=/bin/sh -c "( while [ -v open ] && ! [ -e ${XDG_RUNTIME_DIR}/wayland-0 ]; do sleep .2s; done; ${open} ) & :; /usr/bin/labwc"
		#ExecStart=/usr/local/bin/labwc
		ExecStart=/bin/sh -c "exec /usr/local/bin/labwc -s '${open}'"
		EOF
		
	systemctl daemon-reload

	echo -e "$wb soft linking library files from /usr/local/... to /usr/..."
	cd /usr/
	mkdir -p include/libdlmclient local/lib/pkgconfig 
	for file in include/{libdlmclient/dlmclient.h,toml.h} lib/pkgconfig/{libdlmclient.pc,libtoml.pc} lib/{libdlmclient.so.0,libtoml.so,libwlroots-0.18.so}
	do
		! [ -e $file ] && ( ln -s /usr/local/$file $( dirname $file ) || exit 30 )
	done
	# change this to ldconfig or PKGBUILD (pacman can handle dependencies)(needs noupdate on pacman.conf )
		
	echo -e "$wb creating guest and build+cfg directories ..."
	useradd guest
	#useradd ${ms_dir##*/}
	mkdir -p $ms_dir
	mkdir -m 2750 /etc/multiseat
	chown -R :users /etc/multiseat
	;;


    "-gp") # git clones
	echo -e "$wb installing required packages ...."
	pacman -Sy --noconfirm --needed git make meson ninja wget alacritty gcc cmake pkgconfig libdrm sudo \
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
		echo -e "$wb clonning/updating $name ...."

		if [[ "$name" != $( basename $( pwd ) ) ]]
		then
			git clone "https://${href[$2]}" || exit 60
			cd $name
		fi

		git reset --hard
		branch=( '0.18.2' )
		[[ "${branch[$2]}" != "" ]] && git checkout ${branch[$2]}
		git pull
		
	
		patch_href=( 'gitlab.freedesktop.org/garlett/wlroots-lease-multiseat' )
		if [[ "${patch_href[$2]}" != "" ]]
		then
			echo -e "$wb patching with $( basename ${patch_href[$2]} ) ...."
			git remote add -f b "https://${patch_href[$2]}.git"
			git remote update
			git diff master remotes/b/master > multiseat.patch
			patch -Np1 < multiseat.patch
			# host a patch file on github
		fi

		echo -e "$wb applying configs ...."

	       	[[ "$name" == "tomlc99" ]] && mv libtoml.pc{.sample,}
		[[ "$name" == "labwc" ]] && ln -s $ms_dir/wlroots $ms_dir/labwc/subprojects/ && \
		 	cat <<- 'EOF' > /etc/multiseat/labwc/autostart
				sfwbar > /dev/null 2>&1 &
				pcmanfm-qt --desktop > /dev/null 2>&1 &
			EOF
			#swayidle -w timeout 420 "wlopm --off \*" resume "wlopm --on \*" > /dev/null 2>&1 &
		[[ "$name" == "sfwbar" ]] && ! grep -q  timer_1 $ms_dir/sfwbar/config/sfwbar.config && sed -i 's/Function("SfwbarInit") {/Module("idle")\nTriggerAction "timer_1", Exec "wlopm --off *"\nTriggerAction "resumed", Exec "wlopm --on *"\nFunction("SfwbarInit") {\n\tIdleTimeout "timer_1", "420" /' $ms_dir/sfwbar/config/sfwbar.config # ugly
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
		dev_p_d="${dev_p_d:0:22} #- $(cat $dev/name)"

		[[ ${key_cap[0]} == efffffffffffffff ]]  && keyboard[$((k++))]="ps2k $dev_p_d"

		[ "$(echo ${key_cap[4]} | rev)" \> "1" ] &&    mouse[$((m++))]="ps2m $dev_p_d"

		done

# write auto-config procedure as: (start it when: no cfg is found? secret key?)
#  use current preallocation
#  start a terminal showing asking the user to: type a numeric code and series of clicks and scroll ?
#  for audio ?

# merge on cfg file ps2k + ps2m, usbm + usbk + usbd, then detect on get_conf2, include hub
#  inside this function is still needed to know the type for the preallocator
#  usb owner need only usbd ?
  
	# find usb devices
	for path_port in /sys/devices/*/*/usb2/driver/*.*
       	do
		port=$( readlink -f $path_port )	# /sys/devices/pci0000:00/0000:00:1d.0/usb2/2-1/2-1.4/2-1.4.4
		port=${port##*:}			# 1d.0/usb2/2-1/2-1.4/2-1.4.4
		port=${port:0:4}-${port##*-}		# 1d.0-1.4.4

		dev_id=$( cat $path_port/idVendor 2> /dev/null ):$( cat $path_port/idProduct 2> /dev/null )
		name=$( lsusb | grep " $dev_id " | head -n 1 )
		name=${name:33}
		serial="$( [ -e $path_port/serial ] && echo " - $( cat $path_port/serial )" )"
		dev_p_d="$port                                      "
		dev_p_d="${dev_p_d:0:22} #- $name$serial"
#		dev_p_d="$port	#- $name$serial"


		[[ ${name,,} =~ .*keyboard.* ]] && keyboard[$((k++))]="usbk $dev_p_d" && continue

		[[ ${name,,} =~ .*mouse.* ]]    && mouse[$((m++))]="usbm $dev_p_d" && continue

		! [[ ${name,,} =~ .*\ hub\ .* ]] && usbd[$((u++))]="usbd $dev_p_d" && continue
	done

	# update $conf  with discovered devices
	cfgs=$( cat $conf 2> /dev/null )
	[[ "$cfgs" == ""  ]] && cfgs="#	open $guest_login_cmd"

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


    "-d") # dlm service
	
	echo -e "$ms Starting drm-lease-manager services ... "	
	
	wait_files "/dev/dri/" "$( grep "^card[0-9]" $conf -o )"  # wait configured cards

	systemctl start `systemd-escape --template=multiseat-dlm@.service /dev/dri/card*` || exit 100 # udev ?

	wait_files "/var/local/run/drm-lease-manager/" "$( grep "^card*" $conf )" # wait configured crtcs 
	;;



    "-r") # read config and start_seat     $2 seat name or pos    $3 user name
	# set "master-of-seat" on input devices
        sed -i 's/SUBSYSTEM=="input", KERNEL=="input\*", TAG+="seat"$/&, TAG+="master-of-seat"/' \
	        /usr/lib/udev/rules.d/71-seat.rules || exit 110
	udevadm control --reload && udevadm trigger || exit 120

	for card in $( get_conf2 card $2 )
	do
		sleep 4s
		start_seat2 "$card" "$3" # & threads only working with libdrm <= 2.4.121-1  or lib-display-info < 2.0 ????
		seats+="$! "
	done
	[[ "$seats" != "" ]] && wait $seats

	;;



    "-s" | "-S") # start services

	[[ $2 == "" ]] && start_guard2 2.69s &
	. $0 -d 		# start dlm-lease-manager services
	. $0 -r #"" "guest" 	# start compositor seats services

	[[ "$1" == "-s" ]] && read -p " waiting to stop root session ..."
	O=$(loginctl | grep root) && loginctl kill-session ${O:0:7}
	systemctl stop getty*
	deallocvt
	;;



    "-q" | "-Q") # quit services
	echo -e "$ms Stopping ... "
	systemctl stop "multiseat-compositor*" "multiseat-dlm*"
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
		 -s 		Start drm-lease-manager and compositor services

		 -q 		Quit multiseat
		 -r [LEASE]  	Restart compositor seat service [with LEASE name or pos]
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
