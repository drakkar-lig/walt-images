**Target:** https://github.com/drakkar-lig/walt-python-packages/issues (server, walt-images, and FeniX hardware)

**Title:** Raspberry Pi 5 VPN nodes: protect the SSH private key stored in the EEPROM

### Context

The enrollment of a Raspberry Pi 5 VPN node (`walt-vpn-auto-enroll`) stores its VPN credentials (`WALT_VPN_CREDS`: SSH private key, certificate, known hosts) in clear text in the EEPROM config. With the Wi-Fi boot of #172, the Wi-Fi credentials will be stored there too. WalT users are not considered attackers, and in enforced mode the board only boots `boot.img` files signed by the WalT server. But these nodes are meant to be deployed in unattended places (e.g., rooftops, FeniX nodes), and someone with physical access can still get the key:
- **Reading the SPI flash directly.** The EEPROM is a SPI flash chip: a test clip and a flash programmer (or another board running `flashrom`) read it without booting the board.
- **USB boot mode (rpiboot).** On a Pi 5, holding the power button while connecting USB-C puts the ROM in USB device boot mode. Without the secure boot OTP fuses, Raspberry Pi's `usbboot` tool can start a Linux system on the board this way, which can read the EEPROM.
- **Booting another OS from a SD card.** The SD card recovery files overwrite the EEPROM, so the credentials are lost, but only after a possible SPI read.

With the key, an attacker can open a VPN tunnel as this node and enter the walt-net.

### Proposal

**1. Make stolen credentials worth little** (useful whatever the protection of the key)
- The server refuses a second tunnel using the same certificate while one is active, and logs it. A key used elsewhere while the real node is up then shows immediately.
- The server alerts when a VPN node stops connecting for a long time. A node whose EEPROM was overwritten never comes back. The admin can then revoke its certificate (`RevokedKeys` on the SSH entrypoint) and re-enroll the board on the walt-net later.
- Short-lived certificates (e.g., a few weeks), renewed by `walt-vpn-auto-enroll`. The private key stays the same, so the EEPROM is rewritten only at renewal. A key stolen from a removed node then expires by itself.
- FeniX: the control MCU senses the opening of the enclosure. Reporting this event to the server (or making the node report it at next boot) gives a tamper alert, and allows revoking the certificate.

**2. Encrypt the credentials with the OTP device private key**
- The Pi 5 has a 256-bit "device private key" in OTP, written once (`rpi-otp-private-key`), readable by any process with access to `/dev/vcio` (`vcmailbox`). Writing it does not change the boot chain, so it cannot brick the board.
- `walt-vpn-auto-enroll` writes a random key in OTP if it is empty, and stores `WALT_VPN_CREDS` encrypted with a key derived from it. The initramfs reads the OTP key through `vcmailbox` and decrypts (it already includes libcrypto, for `ssh`; it needs `vcmailbox` and `openssl` too).
- A SPI dump then only gives ciphertext. Without secure boot, an attacker can still run their own code on the board (rpiboot, or SD recovery after a SPI dump) and read the OTP key. With secure boot (section 4), only signed code can read it, and this becomes a strong protection.

**3. FeniX: a hardware key store**

FeniX nodes have their own carrier board, with I²C buses and a control MCU, so a secure element or TPM can be added:
- **Options:** a TPM 2.0 on SPI (e.g., Infineon SLB9672, supported by a Raspberry Pi kernel overlay), or a secure element on I²C (Microchip ATECC608, NXP SE050).
- **Principle:** the SSH key is generated inside the chip and never leaves it. `ssh` uses it through a PKCS#11 provider. An attacker can use the key only while holding the board, and cannot copy it.
- **Constraints to check:**
  - Key type: the current key is ECDSA P-384, but the ATECC608 supports P-256 only.
  - Initramfs size: `tpm2-pkcs11` pulls `tpm2-tss` and other libraries; `cryptoauthlib` is lighter.
  - `walt-vpn-client` adds the key and its certificate to an `ssh-agent`, and forwards the agent to reach the server through the entrypoint. Check that OpenSSH can add a PKCS#11 key together with its certificate to the agent (otherwise, adapt the connection, e.g., `PKCS11Provider` + `CertificateFile`).
- **Remaining risk without secure boot:** anyone holding the board can boot their own code (rpiboot) and use the key through the chip. Section 1 still applies (revocation when the node disappears or the enclosure is opened).

**4. Optionally, secure boot**

Secure boot writes the hash of a customer public key in the OTP fuses of the BCM2712. Afterwards the ROM only runs code signed with this key: EEPROM bootloader, `boot.img`, and code loaded by rpiboot. It cannot be disabled, and the key cannot be changed.

Steps for a WalT platform:
1. **Choose the key.** The board will check `boot.img` with the fused key, so it must be the HTTP boot key of the WalT server (`/var/lib/walt/http-boot/private.pem`), or the server must sign with the fused key. Back it up offline. A fused board is bound to this key forever: it cannot move to another WalT platform with another key.
2. **Sign the EEPROM images on the server.** After fusing, the EEPROM image must be counter-signed with the private key (`update-pieeprom.sh -f -k <key>`, `rpi-eeprom-digest`). Today, `walt-vpn-auto-enroll` builds the EEPROM image on the node, which does not have the private key. The server must build and sign it, from the parameters it already knows and the credentials blob sent by the node (encrypted, see section 2). This is needed both at enrollment and at each VPN configuration update.
3. **Test without fusing.** Boot the target images with `SIGNED_BOOT=1` from every source of the boot order (HTTP, SD card for #172, TFTP fallback in permissive mode), and check that the counter-signed EEPROM images and the configuration updates work.
4. **Fuse, with the board connected to a host over USB-C** (from the `usbboot` repository, `secure-boot-recovery5/`):
   - in its `config.txt`, set `program_pubkey=1` (irreversible), and optionally `program_jtag_lock=1` (irreversible, disables VideoCore JTAG);
   - sign the bootloader: `../tools/update-pieeprom.sh -f -k <key>`;
   - power off, hold the power button while connecting USB-C, then `mkdir -p metadata && ../rpiboot -d . -j metadata`.
   The documentation only describes fusing through rpiboot, so this would be done on a bench when preparing the board, not remotely.
5. **Recovery afterwards:** SD card recovery files are no longer accepted (`recovery.bin` from SD is not loaded). The bootloader can only be updated by rpiboot with a counter-signed `recovery.bin` (`update-pieeprom.sh -fr`), or by its self-update.

Remaining risks with secure boot:
- **Losing the private key** makes every fused board unable to boot any new image or new EEPROM config: in practice, the boards are lost. The key must be backed up, and moving a WalT server must keep it. The signing tools support an HSM wrapper (`-H`) if needed.
- **Bricking by writing the SPI flash.** `walt-vpn-auto-enroll` (or any root process on the node: an experiment, `rpi-eeprom-update`, `flashrom`) writes the SPI flash directly, without any check. An unsigned or broken EEPROM image then prevents the board from booting, and without SD recovery the only fix is rpiboot on site. Our Debian images already disable the `rpi-eeprom-update` service, but WalT should check the EEPROM image before flashing, and never flash an unsigned one on a fused board. Section 2 of this list (the EEPROM image signed by the server) is the only flashing path to keep.
- **The server signs the `boot.img` of every image**, including images built by any WalT user. Secure boot guarantees that a node runs a WalT image, not a hardened one. For example, our Debian images allow root login without password on the serial console, unless the image is VPN-capable; another image might allow it on a VPN node, and anyone at the console would then read the EEPROM and the OTP key. Option: the server signs `boot.img` only for images with a label stating that they are VPN-safe (consistent with `walt.vpn.wifi=1` in #172).
- **Physical attacks on the running board** (probing DRAM, SPI bus sniffing at boot when the EEPROM config is read) are not covered. With section 2, the credentials read from the SPI flash are encrypted, and the OTP key is only readable by signed code.
- **Rollback and key revocation** are not documented: an old signed `boot.img` with a known weakness may still boot, and there is a single customer key, which cannot be replaced.

### Suggested order

Section 1 first (cheap, server-side). Then section 2, which is useful alone and becomes strong with secure boot. Section 3 for the FeniX hardware. Section 4 last, after testing steps 2 and 3 on a spare board, since fusing is irreversible.
