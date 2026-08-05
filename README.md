# Install and run
`sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Sturm0/multiseat/wlroots-0.20/install_and_run.sh)"`

# multiseat
multiseat using single graphics card gpu, without nesting like xephr and others.

what it does:
- download and install pacman packages
- download, patch and compiles: tomcl, drm-lease-manger, wlroots, labwc and sfwbar
- creates configuration for: keyboards, mouses and videos
- apply kmv config on the seats
- start compositor service for each seat with non-root user

Currently using with 4 seats on nvdia gf7300 and amd R5-230

# How to configure labwc on this multiseat setup

`install_and_run.sh` places a configuration file in `/etc/xdg/labwc`. This file is used by any user whose `~/.config` file does not contain a `labwc` folder.
If you want to customize autostart, `rc.xml`, environment, etc. at the user level, create a `labwc` directory in `~/.config`. For more information, see: https://labwc.github.io/labwc-config.5.html

***Need help on refering this repo on multi seat tutorials.***

![multiseat using single graphics card gpu](https://github.com/garlett/multiseat/raw/wlroots-0.19/docs/not%20nested%20multiseat%20using%20single%20graphics%20card%20gpu.jpg?raw=true)

# VGA adapters
The boards that I tested, can only work with two displays at the same time: gf6200 and gf7300: VGA, DVI-I ......... AMD R5 230: VGA, HDMI, DVI-D (it has the analog pins, but they are connected to the vga);

I guess that intermediary boards could accept 3 outputs and high end boards 4 or more.

[Sparkle Intel Arc A310 ELF](https://www.amazon.com/dp/B0CHN9R4P2?tag=pcpapi-20&linkCode=ogi&th=1) and [Asus GT710](https://pcpartpicker.com/product/P2CFf7/asus-geforce-gt-710-2-gb-video-card-gt710-4h-sl-2gd5) should take 4 displays. ? RX {570,580,590} ?

Did not tested usb3 to vga or hdmi (probably does not require drm lease)

Did not tested DisplayPort Multi-Stream Transport ([Daisy-chained monitors](https://www.displayninja.com/daisy-chain-monitor-list/) or DisplayPort MST splitter)

# VGA cables
AFIK, the wire nomenclature is CxD, where:
- C is the number of pairs( signal + ground, some cables shows this as coaxial shielded construction ) for colors, normaly 3; 
- D is non-color wires.
 
Commom cables:
- 3x2: RGB HV
- 3x5: RGB HV SCL SDA presence ? 
- 3x6: RGB HV SCL SDA presence 5V ? https://pt.aliexpress.com/item/1005005671127960.html https://pt.aliexpress.com/item/4000060507008.html
- 3x9: RGB HV this have all pins connected https://pt.aliexpress.com/item/1005002598233946.html
  
EDID requires SCL and SDA, its possible to provide EDID data manually https://wiki.archlinux.org/title/kernel_mode_setting;
```
echo 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 video=DVI-I-1:1600x900@60e video=DVI-I-2:1366x768@60e"' >> /etc/default/grub && grub-mkconfig -o /boot/grub/grub.cfg
```

# VGA over RJ45
 [This cheap adapter](https://pt.aliexpress.com/item/32813247399.html) comes configured as 3x2, and at 10 meters of cat5 gives me a little of ghost in 1024x768.

![multiseat using single graphics card gpu](https://github.com/garlett/multiseat/raw/wlroots-0.19/docs/vga_over_rj45.webp?raw=true)

There are some passive converters that have one balun( usualy a torroid transformer with some caps and resistors) per color at each side;

There is also powered converters.

# HDMI cable with VGA converter
Because power drop in the "9 metres of hmdi cable", the adapter only returns monitor edid data, and cannot convert to vga.

But if you have hdmi monitors, you could use only the cable, or "Laranja Pi Zero 3" could be another alternative ( headless weston with spice, then the SBC connects to the server ).


# USB 10 meter cable
The [cable](https://shopee.com.br/Cabo-Extensor-10-Metros-Usb-2.0-Ultra-Rapido-Ativo-Amplificado-Macho-F%C3%AAmea-Enivo-Rapido-i.296745639.23091334073) bellow works well with keyboard, mouse and smartcard reader

![USB 10 meter cable](https://github.com/garlett/multiseat/raw/wlroots-0.19/docs/usb-10meter-cable.webp?raw=true)



# USB over RJ45 extender (not recommended)

This https://www.aliexpress.com/item/1005002747560169.html extender, have an IC (cjs1037a) at each side that amplifies data lines. 

5v (2 wires) and ground (4 wires) are direct connected. 

The PCB have a place for an electrolytic capacitor, USB standard specifies a maximum of 10uF, but I am using 470uF_10v.

![multiseat using single graphics card gpu](https://github.com/garlett/multiseat/raw/wlroots-0.19/docs/usb_over_rj45.webp?raw=true)

USB voltage range is 4.75V .. 5.25V, in my tests the voltage drop of each device, at 10 meters was:
- 10 mV for a cheap 4-port hub;
- 35 .. 70 mV for mouse;
- 14mV for keyboard;
- 14mV for each keyboard led;

On average the USB port drops once per day because AC interference. Sometimes it requires wire replug or driver rebind.

Injecting 5v (from old smartphone power supply with A to A usb cable) does not improve stability, so, powered usb hub may yeld the same results.

# Wireless Mouse and Keyboard (not recommended)
- Krab KBKTM10 combo  U$ 7.50, working at 5 meters with obstacles (k=AAA m=AA).
- Mtek KM5239  combo U$ 13.00, working at 5 meters with obstacles (k=AA m=AAA+AAA).
- Satellite AK-726G combo U$ 11.00, working at 5 meters with obstacles, the mouse have a bug that lags after resume from idle and the keyborad eat characters (k=AA m=AA).
Those kits are recognize as "SHARKOON Technologies GmbH [Mediatrak Edge Mini keyboard]", because of this, sometimes they mispair with the dongle, maybe using only one would be recommended."
