# icecube
A Linux distro tailored for the Glacier protocol

**About icecube.**

Icecube is a Bash script that generates a bootable USB with a Debian based Linux distro tailored for the Glacier protocol. The operating system ships only what is required for a smooth execution of Glacier.

It was currently tested to work on Ubuntu 18.04.

**How to use it.**

Icecube is supposed to be run on a Ubuntu system on which you have root privileges, ideally a live USB session. 

Plug a USB key into your system, and run the bash script with the path to the usb device as a command line parameter. 

After (successful) execution you should have a bootable USB running a bare Debian Linux with bitcoin core and glacier installed on the system.

**Why use it?**

* Simplifies the creation of the quarantined USB
* Reduces the number of quarantined USBs needed from 2 per laptop to 1
* Enables RAM-only boot on the quarantined laptop, allowing the USB key to be removed after boot, preventing any malware from using the USB to exfiltrate data


**Should I use it?**

No. At this point icecube is a purely experimental project and should in no way be used for any serious purpose.


