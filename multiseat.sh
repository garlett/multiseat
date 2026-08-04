#!/bin/bash

# tomlc, drm lease manager, wlroots and labwc builder on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution

# !!!!!!!!! IMPORTANT !!!!!!!!!!!!
# until reboot is working, uncomment the line bellow and enable the service before each boot test
[[ "-S" == "$1" ]] && systemctl disable multiseat 

wait_time=0.31s	# time between exist checks 
guest_login_cmd="alacritty --config-file /usr/local/etc/multiseat/login/alacritty.toml -e /usr/local/bin/login.sh"
default_compositor="labwc"

if [ "$EUID" -ne 0 ]
then 
	echo -e "$wb Please run this as root"
	exit 10
fi

red="\e[1;31m"
white="\e[0m"
yellow="\e[1;33m"
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
			[ $((count--)) -lt 0 ] && echo -e "$ms could not find: $1$file" && return 1
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
conf=$(find /sys/devices/pci* -type d -path "*/drm/card*/card*-*" -prune)
[[ "$conf" != "" ]] && conf=/usr/local/etc/multiseat/_$( basename -a $conf | tr -cd "[:alnum:]" ).conf
conf=${conf//card/}

[[ "$conf" != "" ]] && ln -sf $conf /tmp/multiseat.conf
! [ -e "$conf" ] && [[ "-S" == "$1" ]] && ( echo -e "$ms Config '$conf' not found!"; systemctl start getty@tty1.service ; killall multiseat.sh )




function start_seat2(){  # $1 lease    $2 user
	local compositor=( $default_compositor )
	
	# do not restart when running from inside seat
	[[ "$XDG_SEAT" == "seat-$1" ]] && exit
	
	echo -e "$ms start_seat: lease $1 user '$2'"
	
	systemctl stop multiseat-$1 2> /dev/null
	systemctl reset-failed


	IFS=\;

	# set default user 
	if [[ "$2" == "" ]] || [[ $2 == 'guest' ]]
	then
		if [[ $2 == 'guest' ]]
		then
			compositor=( /usr/local/bin/labwc -C /usr/local/etc/multiseat/login )
		fi
		user=${1/card/u}
		user=${user,,}
	else
		user=$2
	fi
	IFS=$oIFS
	
	#Obtener la ruta del home consultando directamente al sistema
	user_home=$(getent passwd "$user" | cut -d: -f6)

	#Si la variable está vacía, el usuario temporal no existe
	if [ -z "$user_home" ]; then
		user_home=/tmp/"$user"
		useradd --system --no-user-group --no-create-home --home-dir "$user_home" "$user" 2>/dev/null
	fi
	

	resta="--property=RestartSec=1s --property=Restart=always "
	param="$( [[ $default_compositor == "weston" ]] && echo --drm-lease=$1 ) "
 	user_id=$( id -u $user )
  	envs="--uid=$user_id --property=UMask=0006" # 666 - 006 -> 660
	
	wait_files /var/run/drm-lease-manager/ "$1 $1.lock" # || exit 19
	chown $user: /var/run/drm-lease-manager/$1{,.lock} || exit 20

	sys_layout=$(localectl status | awk '/X11 Layout/ {print $3}')
    	sys_layout=${sys_layout:-us}

	user_id=$( id -u $user )
	
	# compositor
	systemctl set-environment \
		SEATD_VTBOUND=0 \
		XDG_SESSION_TYPE=wayland \
		XKB_DEFAULT_LAYOUT="$sys_layout" \
		XDG_SEAT=seat-$1 \
		DRM_LEASE=$1 \
		usbdvs="$( get_conf2 usbd $1 )" \
		open=""
		
	#systemd-run $envs $resta --unit=multiseat-$1 --property=PAMName=login --property=ExecStartPre="/bin/sleep .1" "${compositor[@]}" $param #-dVVV
				# sleep: wlroots or systemd is not openning session on first try
	systemd-run $envs $resta --unit=multiseat-$1 --property=PAMName=login --property=ExecStartPre="/bin/sleep .1" setpriv --ambient-caps -all "${compositor[@]}" $param #-dVVV
	wait_files /run/user/$user_id/ wayland-0{,.lock} || exit 25
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
			
			"spkr")
                clean_id=$(echo "${cfg:5}")
                [[ $1 == "devs" ]] && echo -n "" $(readlink -f /sys/bus/pci/devices/$clean_id)/sound/card*
                ;;
				
			"ps2k" | "ps2m")
				[[ $1 == "devs" ]] && echo -n "" /sys/devices/platform/*/${cfg:5}/input/input*
				;;

			"usbm" | "usbk")
				unset dev
				[[ $1 == 'devs' ]] && dev=$( echo /sys/bus/usb/devices/*${cfg:17} )
				[[ $dev != '' ]] && echo -n "" $( readlink -f ${dev// /$'\n'/} | grep ${cfg:5:12} | sort -u )/*-*/*/input/input*
				;; 

			"usba")
				unset dev
				[[ $1 == 'devs' ]] && dev=$( echo /sys/bus/usb/devices/*${cfg:17} )
				[[ $dev != '' ]] && echo -n "" $( readlink -f ${dev// /$'\n'/} | grep ${cfg:5:12} | sort -u )/*/sound/card*
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


function login_server() {
    local pipe="/tmp/multiseat_login.fifo"
    [[ ! -p $pipe ]] && mkfifo $pipe
    chmod 666 $pipe # allow kiosks to write here

    echo -e "$ms Starting login server..."
    
    while true; do
        if read line < $pipe; then
			# The message will be "LEASE USER" (e.g., "card0-HDMI-A-1 jose")
            lease=$(echo "$line" | awk '{print $1}')
            usuario=$(echo "$line" | awk '{print $2}')
            
            echo -e "$ms Login request received: $usuario in $lease"
            
            start_seat2 "$lease" "$usuario" &
        fi
    done
}



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
	for file in include/{libdlmclient/dlmclient.h,toml.h} lib/pkgconfig/{libdlmclient.pc,libtoml.pc} lib/{libdlmclient.so.0,libtoml.so}
	do
		! [ -e $file ] && ( ln -s /usr/local/$file $( dirname $file ) || exit 30 )
	done
	# ? change this to ldconfig or PKGBUILD (pacman can handle dependencies)(needs noupdate on pacman.conf)
		
	echo -e "$wb creating build+cfg directories ..."
	mkdir -p /usr/local/src/multiseat
	mkdir -m 755 /usr/local/etc/multiseat
	chown -R :users /usr/local/etc/multiseat
	;;


    "-gp") # git clones
	echo -e "$wb installing required packages ...."

	pacman -S --noconfirm --needed git make meson ninja wget alacritty gcc cmake pkgconfig libdrm sudo \
		fakeroot wayland libxkbcommon libinput libunwind pixman cairo libjpeg-turbo libwebp mesa libegl \
		libgles pango lcms2 mtdev libva colord pipewire wayland-protocols patch usbutils \
		libxml2 glib2 hwdata libdisplay-info libliftoff xorg-xwayland libxcb xcb-util-renderutil xcb-util-wm \
		gtk-layer-shell pcmanfm-qt qt6-svg libnewt || exit 40 # swayidle 

	# redo this with requeriments for: wlroots, labwc, sfwbar, pcmanfm-qt  ## maybe pacman --somenthing_like__install_required
	# download sfwbar config to /usr/local/etc/multiseat/{sfwbar/,labwc/} and set config location as argument?
    ;;


"-g" | "-b") # $2 app index

	if [[ "$2" == "" ]]
	then 
		for i in {0..5} 
		do 
			$0 $1 $i && continue
			echo -e "$ms error $? as $1 $i"
			exit
		done 
		exit
	fi

	[ -d /usr/local/src/multiseat ] || ( $0 -l ; $0 -gp ) # links and pacman

	cd /usr/local/src/multiseat || exit 50

	href=( 'github.com/cktan/tomlc99' 'gerrit.automotivelinux.org/gerrit/src/drm-lease-manager' \
        'gitlab.freedesktop.org/wlroots/wlroots' 'github.com/labwc/labwc' \
        'github.com/LBCrion/sfwbar' 'git.sr.ht/~leon_plickat/wlopm' \
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
		branch=( [2]='0.20' )
		[[ "${branch[$2]}" != "" ]] && git checkout ${branch[$2]}
		git pull
		
		patch_href=( [2]='raw.githubusercontent.com/garlett/multiseat/refs/heads/wlroots-0.18/multiseat' ) # /wlroots
		if [[ "${patch_href[$2]}" != "" ]]
		then
			echo -e "$wb patching with $( basename ${patch_href[$2]} ) ...."
			wget "https://${patch_href[$2]}.patch" --output-document=p$2.patch
			patch -Np1 < p$2.patch
		fi

		echo -e "$wb applying configs ...."

	       	[[ "$name" == "tomlc99" ]] && mv libtoml.pc{.sample,}
		[[ "$name" == "labwc" ]] && ln -s /usr/local/src/multiseat/wlroots /usr/local/src/multiseat/labwc/subprojects/

		[[ "$name" == "sfwbar" ]] && ! grep -q idle_timer /usr/local/src/multiseat/sfwbar/config/sfwbar.config && sed -i 's/Function("SfwbarInit") {/Module("idle")\nTriggerAction "idle_timer", Exec "wlopm --off *"\nTriggerAction "idle_resume", Exec "wlopm --on *"\nFunction("SfwbarInit") {\n\tIdleTimeout "idle_timer", "420"\n\tExec "wlopm --on *"/' /usr/local/src/multiseat/sfwbar/config/sfwbar.config	# ugly --- maybe lbcryon could make it native, or this should not be in multiseat

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
			meson setup build --force-fallback-for=wlroots --localstatedir=/var || exit 70
			ninja -C build || exit 80
			ninja -C build install || exit 90
		fi
	fi
	chmod 755 -R .
;;

    "-p")
	cd /usr/local/src/multiseat/wlroots || exit 50
	# git reset ? checkout ? 18.2 ?
	git remote add -f b "https://gitlab.freedesktop.org/garlett/wlroots-lease-multiseat.git"
	git remote update
	git diff master remotes/b/master > wlroots.patch
	;;


    "-c" | "-C" ) # update config file
	unset drm mouse keyboard usba usbd spkr 
        d=0
        m=0
	k=0
	u=0
	a=0
	s=0

    read -p "Please connect all monitors and peripherals you plan to use in the multiseat system. When you have finished connecting them, press ENTER."
	# find leaseable crtcs
    drm=($(find /sys/devices/pci* -type d -path "*/drm/card*/card*-*" -prune -exec grep -q "^connected$" {}/status \; -exec basename {} \; 2>/dev/null))
	d=${#drm[@]}    

	# find audio devices
    for card in /sys/class/sound/card*; do
        # Avoid USB; this is already covered in a section below.
        real_path=$(readlink -f "$card")
        if [[ "$real_path" == *"usb"* ]]; then continue; fi
        pci_id=$(basename $(readlink -f "$card/device"))
        
        name=$(cat "$card/id" 2>/dev/null || echo "Unknown")
        pci_id="$pci_id                                    "
        spkr[$((s++))]="spkr ${pci_id:0:29} #- $name"
    done


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
        
        #According to https://www.usb.org/sites/default/files/documents/hid1_11.pdf 03 is HID and bInterfaceProtocol 1 is keyboard.
        #In section 5.1 "Device Descriptor Structure" of the same document it says:
        #"Class type is not defined at the Device descriptor level. The class type for a HID class device is defined by the Interface descriptor"
        if grep -q "03" $dev/*/bInterfaceClass 2>/dev/null && grep -q "01" $dev/*/bInterfaceProtocol 2>/dev/null; then
            keyboard[$((k++))]="usbk $device"
            continue
        fi

        #Class 3 is HID and interface protocol 2 is mouse. 
        if grep -q "03" $dev/*/bInterfaceClass 2>/dev/null && grep -q "02" $dev/*/bInterfaceProtocol 2>/dev/null; then
            mouse[$((m++))]="usbm $device"
            continue
        fi
        
        # Class 01 is Audio
        if grep -q "01" $dev/*/bInterfaceClass 2>/dev/null; then
            usba[$((a++))]="usba $device"
            continue
        fi
        
        ! [[ ${name,,} =~ .*hub.* ]] && usbd[$((u++))]="usbd $device" && continue
        
	done

	# load $conf
	cfgs=$( cat $conf 2> /dev/null )
	
	# 1. Armar el "pool" de dispositivos disponibles
	available_devs=()
	for dev in "${spkr[@]}" "${keyboard[@]}" "${mouse[@]}" "${usba[@]}"; do
		available_devs+=("$dev")
	done

	cfgs=""

	# 3. Iterar por cada asiento (monitor) detectado
	for seat in "${drm[@]}"; do
		cfgs+="\n${seat}\n"
		
		# Si ya no quedan dispositivos para asignar, salteamos el menú
		if [ ${#available_devs[@]} -eq 0 ]; then
			continue
		fi
		
		# Armar los argumentos para el checklist de whiptail
		checklist_args=()
		for i in "${!available_devs[@]}"; do
			full_line="${available_devs[$i]}"
			
			# Separar el TAG (ej: "spkr 0000:00...") de la descripción (ej: "#- Generic")
			tag="${full_line%%#-*}"
			desc="#-${full_line#*#-}"
			
			# Limpiar espacios en blanco al final del tag para evitar problemas
			tag=$(echo "$tag" | sed 's/ *$//')
			
			checklist_args+=("$tag" "$desc" "OFF")
		done
		
		# Mostrar el menú de whiptail
		# Usamos 3>&1 1>&2 2>&3 para capturar el stderr (donde whiptail imprime el resultado)
		selected_tags=$(whiptail --title "----- Asiento $seat ----" \
			--checklist "Marque los dispositivos que vaya a usar en este asiento. Para moverse por el menú use las flechas direccionales (↑,↓) y la barra espaceadora para seleccionar una opción .\nCuando termine, presione ENTER para pasar al próximo." \
			22 150 12 "${checklist_args[@]}" 3>&1 1>&2 2>&3)
		
		# Si el usuario presiona "Cancelar" o la tecla ESC
		if [ $? -ne 0 ]; then
			echo -e "$ms Configuración cancelada por el usuario."
			exit 1
		fi
		
		# 4. Procesar las selecciones y actualizar el pool
		# whiptail devuelve los tags entre comillas: "spkr 0000" "usbk 0000"
		eval "selected_array=($selected_tags)"
		
		new_available_devs=()
		for dev in "${available_devs[@]}"; do
			dev_tag=$(echo "${dev%%#-*}" | sed 's/ *$//')
			is_selected=0
			
			for sel in "${selected_array[@]}"; do
				if [[ "$dev_tag" == "$sel" ]]; then
					is_selected=1
					# Agregar al string de configuración con la indentación original
					cfgs+="	${dev}\n"
					break
				fi
			done
			
			# Si NO fue seleccionado, lo guardamos para el menú del próximo asiento
			if [ $is_selected -eq 0 ]; then
				new_available_devs+=("$dev")
			fi
		done
		
		# Actualizar el pool de dispositivos para la próxima iteración
		available_devs=("${new_available_devs[@]}")
	done

	# Guardar en el archivo final
	echo -e "$cfgs" > /tmp/multiseat_cfg.tmp
	mv /tmp/multiseat_cfg.tmp $conf
    echo -e "$ms Configuración finalizada y guardada en $conf"

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
            card_path=$( find /sys/devices/pci* -type d -path "*/drm/card*/$card" -prune )
			for dev in $card_path $( get_conf2 devs $card )
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

	wait_files "/dev/dri/" "$( grep "^card[0-9]" $conf -o )"  # wait configured cards
	
	for card in /dev/dri/card*
	do
		echo -e "$ms Starting drm-lease-manager services at $card ... "	
		systemd-run $dlm_log --property=RuntimeDirectory=drm-lease-manager --unit=dlm-$( basename $card ) drm-lease-manager $card
		# dlm only outputs when ran from terminal with no redirects
	done #--property=RestartSec=1s --property=Restart=always /usr/local/bin/

	wait_files "/var/run/drm-lease-manager/" "$( grep "^card*" $conf )" # wait configured crtcs 

    if ! wait_files "/var/run/drm-lease-manager/" "$( grep "^card*" $conf )"; then
		echo "<3>CRITICAL ERROR: DRM leases could not be created! The video card or driver does not support it." >&2
		exit 1
	fi    

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
	systemd-run --unit=multiseat-login-server $0 -login_server
	. $0 -r "" "guest" 	# start compositor seats services

	[[ "$1" == "-s" ]] && read -p " waiting to stop root session ..."
	O=$(loginctl | grep root) && loginctl kill-session ${O:0:7}
	systemctl stop getty*
	deallocvt
	;;



    "-q" | "-Q") # quit services
	echo -e "$ms Stopping ... "
	systemctl stop "multiseat-*" "dlm-*"
	
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
	#journalctl --no-hostname -S -12h -u "multiseat*"
	#journalctl --no-hostname -S -12h -t sh -t multiseat.sh -t systemd-run -t "(sh)" -t pcmanfm-qt
	journalctl --no-hostname -b $2 | grep -e multiseat -e labwc -e seat | less
	;;

    "-a") # auto
	$0 -b
	$0 -c
	$0 --enable

	;;
	"--enable")
	if [[ "$(systemctl get-default)" == "graphical.target" ]]; then 
		echo -e "$yellow WARNING: $white Your system is configured to use \"graphical.target\", which most likely interferes with the multiseat system."
		echo "It is highly recommended that you change it with the following command: 'sudo systemctl set-default multi-user.target'."
		echo "Do you want me to run that command right now?"

		read -p "[y/N]: " confirm
        
        if [[ $confirm == [yY] ]]; then
            sudo systemctl set-default multi-user.target
            echo "Change completed"
			echo "In principle, if you restart your computer now, the multiseat should work :)"
		fi
	fi 
	sudo systemctl enable multiseat
	;;
	
	"--disable") # Restart your computer and return to your default graphics session.
	systemctl disable multiseat
    systemctl set-default graphical.target
	loginctl flush-devices
	reboot
	;;
	"-login_server")
		login_server
	;;

    *)
	echo -e	"$ms github.com/garlett/multiseat \n    argument $1"
	cat <<- EOF
		 -b [ID]	[Git clone, link and] build
		 -c 		Create, review and enable config
		 -s 		Start drm-lease-manager and compositor services
		
		--enable    Configure things so that the multiseat is up and running on your next reboot
		 --disable  Restart your computer and return to your default graphics session (without multiseat).
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
	     Before download again run:  rm -R /usr/local/src/multiseat
		 Kiosk app will fail: without connected drm output
		 Last error: echo \$?
		EOF
	;;
esac
