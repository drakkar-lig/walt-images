**Target:** https://github.com/Stefal/rtkbase/issues

**Title:** install_polkit_rules.sh: polkitd is not installed when dpkg knows the package but it is not installed

---

**Describe the bug**
`tools/install_polkit_rules.sh` decides whether to install `polkitd` with:

```bash
! dpkg-query -W --showformat='${Status}\n' polkitd >/dev/null 2>&1 && apt-get -y install polkitd
```

But `dpkg-query -W` returns exit code 0 for any package that has an entry in the dpkg database, including packages that are **not installed** (status `unknown ok not-installed`, or `deinstall ok config-files` after a removal). In that case `polkitd` is not installed, and copying the rules then fails because `/etc/polkit-1/rules.d/` does not exist.

Note: on the `dev` branch, the `!` was removed (`dpkg-query ... && apt-get -y install polkitd`). This fixes the case above, but breaks the opposite one: when dpkg does not know the package at all, `dpkg-query` fails and polkitd is not installed.

**To Reproduce**
Steps to reproduce the behavior:
1. Start from a Debian trixie (armhf) system where polkitd is not installed but known to dpkg:
   ```console
   # dpkg-query -W --showformat='${Status}\n' polkitd; echo "rc=$?"
   unknown ok not-installed
   rc=0
   # dpkg -l polkitd | tail -1
   un  polkitd        <none>       <none>       (no description available)
   ```
2. Run the installation steps (`install.sh --user <user> --dependencies`, `--rtkbase-release`, then `--unit-files`, which calls `install_polkit_rules.sh`).
3. polkitd is not installed, and the polkit rules copy fails:
   ```
   cp: target '/etc/polkit-1/rules.d/': No such file or directory
   ```

**Expected behavior**
`install_polkit_rules.sh` installs polkitd whenever it is not installed, then installs the rules. For example:

```bash
if [[ "$(dpkg-query -W --showformat='${db:Status-Status}' polkitd 2>/dev/null)" != "installed" ]]
then
  apt-get -y install polkitd
fi
```

(or simply always run `apt-get -y install polkitd`, which does nothing if the package is already installed.)

**Software/Hardware (please complete the following information):**
 - RTKBase release number 2.7.0 (the code is the same on master)
 - OS: Raspbian / Debian 13 (trixie), armhf
 - SBC: Raspberry Pi (2B/3B/3B+/4B); the installation runs while building an OS image (Dockerfile), not on the board itself
 - GNSS Device: not relevant (installation issue)
 - Connection type: not relevant

**Screenshots**
N/A

**Additional context**
We build an OS image with RTKBase preinstalled for the WalT testbed (https://github.com/drakkar-lig/walt-images, image `rpi32-rtk-base`). We currently work around this issue by installing `polkitd` before running `install.sh`.
