# Install and run
cd && wget https://raw.githubusercontent.com/garlett/multiseat/13.0.1/{multiseat.sh,LICENSE} && chmod 770 multiseat.sh && ./multiseat.sh -a

# multiseat
multiseat using single graphics card gpu, without nesting like xephr and others.

what it does:
- download and install pacman packages
- download, patch and compiles tomcl, drm-lease-manger and weston
- creates configuration for: keyboards, mouses and videos
- apply kmv config on the seats
- start weston service for each seat with non-root user
- start weston kiosk mode and the application (needs weston <= 10.0.93)

Currently using with 4 seats on nvdia gf7300 and amd R5 230

RHATibnLUKUM and arson, tested on a RX550 with GL acceleration working! 

***Need help on refering this repo on multi seat tutorials.***

![multiseat using single graphics card gpu](https://github.com/garlett/multiseat/raw/main/docs/not%20nested%20multiseat%20using%20single%20graphics%20card%20gpu.jpg?raw=true)



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
This cheap adapter https://www.aliexpress.com/item/32887231519.htm comes configured as 3x2, and at 10 meters of cat5 gives me a little of ghost in 1024x768.

![multiseat using single graphics card gpu](https://github.com/garlett/multiseat/raw/main/docs/vga_over_rj45.webp?raw=true)

There are some passive converters that have one balun( usualy a torroid transformer with some caps and resistors) per color at each side; https://pt.aliexpress.com/item/4001015046270.html

There is also powered converters.

# HDMI cable with VGA converter
Because power drop in the "9 metres of hmdi cable", the adapter only returns monitor edid data, and cannot convert to vga.

But if you have hdmi monitors, you could use only the cable, or "Laranja Pi Zero 3" could be another alternative ( headless weston with spice, then the SBC connects to the server ).




# USB over RJ45 extender

This https://www.aliexpress.com/item/1005002747560169.html extender, have an IC (cjs1037a) at each side that amplifies data lines. 

5v (2 wires) and ground (4 wires) are direct connected. 

The PCB have a place for an electrolytic capacitor, USB standard specifies a maximum of 10uF, but I am using 470uF_10v.

![multiseat using single graphics card gpu](https://github.com/garlett/multiseat/raw/main/docs/usb_over_rj45.webp?raw=true)

USB voltage range is 4.75V .. 5.25V, in my tests the voltage drop of each device, at 10 meters was:
- 10 mV for a cheap 4-port hub;
- 35 .. 70 mV for mouse;
- 14mV for keyboard;
- 14mV for each keyboard led;

On average the USB port drops once per day because AC interference. Sometimes it requires wire replug or driver rebind.

# Wireless Mouse and Keyboard
- Krab KBKTM10 combo U$ 7.50, working at 5 meters with obstacles.
- Satellite AK-726G combo U$ 11.00, working at 5 meters with obstacles, the mouse have a bug that lags after resume from idle and the keyborad eat characters.

