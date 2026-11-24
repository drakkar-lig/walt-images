**Target:** https://github.com/drakkar-lig/walt-python-packages/issues (server, client and walt-images)

**Title:** Raspberry Pi 5 VPN nodes: boot over Wi-Fi when there is no ethernet link

### Context

Raspberry Pi 5 VPN nodes are meant to be deployed in hard-to-reach places, such as rooftops, for experiments with long-range IoT protocols (e.g., LoRa). Today they need a wired ethernet connection, because the RPi5 firmware supports HTTP boot over wired ethernet only. Many of these places have no ethernet plug, but have Wi-Fi.

Current procedure (see `doc/walt/doc/md/vpn-boot.md`):
- **Enrollment.** The node boots once on the walt-net, with the classical TFTP boot. Service `walt-vpn-auto-enroll` (rpi64-debian image) retrieves the SSH credentials, the entrypoints and the HTTP boot public key, and flashes them into the EEPROM, with a boot order that includes HTTP boot (`0xf7` in enforced mode, `0xf127` in permissive mode).
- **Next boots.** The firmware downloads `boot.img` + `boot.sig` from `http://<HTTP_HOST>/walt-vpn/per-ip/<ip>/`, checks the signature, and starts the kernel and initramfs of `boot.img`. The initramfs (`scripts/walt`, `scripts/walt-vpn-client`) then opens an SSH tunnel through the SSH entrypoint and mounts the root filesystem over this tunnel.

The tunnel runs over IP, and the node's network interface is never bridged into the walt-net. So Wi-Fi only has to replace ethernet as the link that carries the tunnel; the rest of the procedure stays the same. The missing piece is booting the kernel and initramfs without the firmware's HTTP boot: they can come from a copy of `boot.img` + `boot.sig` on a SD card.

### Proposal

**1. Configuration**
- New node config settings for the Wi-Fi credentials (at least SSID and passphrase/PSK), set with `walt node config`. Each site has its own network, so these are per-node settings.
- The server exposes them to the node itself only, at a new `node-conf` endpoint (like `node-conf/vpn-mac`, using the requester IP).
- Images supporting this feature get the label `walt.vpn.wifi=1`. `walt node boot` warns the user when a node with Wi-Fi credentials is directed to an image without this label.

**2. Enrollment** (`walt-vpn-auto-enroll`, during the wired boot on the walt-net)
- Also store the Wi-Fi credentials in the EEPROM config, and `SIGNED_BOOT=1`.
- Add SD card boot to the boot order, after HTTP boot (e.g., `0xf17` in enforced mode). With `SIGNED_BOOT=1`, the SD card boot only accepts a `boot.img` signed with the server key, so enforced mode still runs only server-signed code.
- Write `boot.img` + `boot.sig` (those the firmware would download over HTTP) to the FAT partition of the SD card. The user only has to insert a blank SD card with a FAT first partition.
- Include the Wi-Fi settings and the state of the SD card in the "already up-to-date" check of the service.

**3. Initramfs: network link**
- Add Wi-Fi support to the initramfs of `boot.img`: modules `brcmfmac`, `brcmutil`, `cfg80211`; the CYW43455 firmware files (firmware, `clm_blob`, nvram); `regulatory.db` and a country code; `wpa_supplicant` and its libraries. Also `vfat`, the codepage modules and the SD card driver, to update the SD card copy.
- Before `configure_networking`: check the carrier on `eth0`. If there is none and the EEPROM contains Wi-Fi credentials, start `wpa_supplicant` on `wlan0` and configure `wlan0` with DHCP instead. (Without this, `configure_networking` would wait a long time on `eth0`.)
- `wpa_supplicant` must keep running after the initramfs (WPA rekeying): put it in the `/run` mini-rootfs, like `ssh` in `walt-vpn-client`. If it stopped, the link would drop, then the tunnel, and the node would reboot. Also check:
  - how the DHCP lease on `wlan0` is renewed (and how the `eth0` lease is renewed today in the VPN case);
  - that nothing in the OS (NetworkManager, ifupdown...) takes over `wlan0`. `wlan0` is then reserved and not available for experiments: to be documented.

**4. Initramfs: keeping the SD card copy up to date**

The `boot.img` on the SD card belongs to the image the node booted last time. Since then, a user may have directed the node to another image with `walt node boot`. This outdated `boot.img` is still enough to connect to the network. Once the tunnel is up, and whenever a SD card is present (whatever the boot source):
- Download `boot.sig` from the same URL as the firmware, with a parameter: `http://<HTTP_HOST>/<HTTP_PATH>/boot.sig?wifi-mandatory=1` (busybox `wget`; with a custom `HTTP_HOST` the firmware uses plain HTTP too). The server returns an HTTP error (e.g., 409) if the image now assigned to the node does not have the label `walt.vpn.wifi=1`.
- Compare only the sha256 line of `boot.sig`, not the whole file: the `ts:` line changes each time the server signs `boot.img`, even if `boot.img` did not change.
- **Booted from the SD card, and its copy is outdated:** download `boot.img`, check its sha256 against `boot.sig` (a truncated download on a flaky long-range link would break the fallback), write both files to the SD card (temporary files, sync, then rename), and reboot. The node must not continue booting: the kernel and dtb of the old image may not match the userspace files of the new image. Boot loops are accepted, as in other WalT cases (e.g., server unreachable).
- **Booted over HTTP:** the running kernel comes from the `boot.img` the server currently serves, so copying it to the SD card is enough. If the sha256 in the downloaded `boot.sig` differs from that of the `boot.img` actually booted (a `walt node boot` between the firmware download and this check), download, write and reboot as above.
- **The server refuses (image without Wi-Fi support):** keep the SD card copy. Overwriting it would leave a node that can never reconnect, and someone would have to climb on the roof. Only the kernel and initramfs of the previous image are available, not its complete OS, so the initramfs loops: it sends a log line to the server, waits a few minutes and checks again. When the user directs the node to an image with Wi-Fi support, the check passes, the node downloads the new files and reboots. A way to send logs from the initramfs is needed (e.g., an HTTP POST to the server through the tunnel).
- Which source the firmware booted from should be readable in `/proc/device-tree/chosen/bootloader/boot-mode` (the boot order uses 1 for SD card, 7 for HTTP). To be checked on the board.

### Points to check first

- **`SIGNED_BOOT=1` and the other boot modes.** It probably applies to all boot modes, so in permissive mode (`0xf127`) the TFTP fallback would also need a signed `boot.img`. The boot directory of the image contains `boot.img` + `boot.sig`, so this may already work; to be tested.
- **Delay before the SD card fallback** when no ethernet cable is plugged in (`DHCP_REQ_TIMEOUT=500` is set, but `DHCP_TIMEOUT` defaults to 45 s).
- **EEPROM config size.** `WALT_VPN_CREDS` already takes room. An SSID and a PSK fit easily, but WPA-Enterprise credentials with certificates (common on campus networks) may not.
- **Size of `boot.img`** with the Wi-Fi files added (the firmware loads it as a ramdisk; the documented limit is 180 MB).

### Security notes

- As for the SSH credentials stored today, anyone with physical access can read the EEPROM's SPI flash. The SSH certificate of a node can be revoked server-side, but a Wi-Fi PSK is shared: a dedicated SSID or PSK for these nodes is preferable.
- Changing the Wi-Fi credentials of a remote node is risky: if the new ones are wrong, the node is lost. Supporting a second network entry (e.g., keeping the previous one) would help.
