**Target:** https://github.com/Stefal/rtkbase/issues

**Title:** install_polkit_rules.sh: polkitd not installed when dpkg knows the package but it is not installed

### Description

`tools/install_polkit_rules.sh` decides whether to install `polkitd` with:

```bash
! dpkg-query -W --showformat='${Status}\n' polkitd >/dev/null 2>&1 && apt-get -y install polkitd
```

But `dpkg-query -W` returns exit code 0 for any package that has an entry in the dpkg database, including packages that are **not installed** (status `unknown ok not-installed`, or `deinstall ok config-files` after a removal). In that case, `polkitd` is not installed, and the next step fails because `/etc/polkit-1/rules.d/` does not exist:

```
cp: target '/etc/polkit-1/rules.d/': No such file or directory
```

### How to reproduce

On a Debian trixie (armhf) system where polkitd is not installed but known to dpkg:

```console
# dpkg-query -W --showformat='${Status}\n' polkitd; echo "rc=$?"
unknown ok not-installed
rc=0
# dpkg -l polkitd | tail -1
un  polkitd        <none>       <none>       (no description available)
```

Then `install.sh --user <user> --unit-files` (which calls `install_polkit_rules.sh`) does not install polkitd.

We hit this with RTKBase v2.7.0, when building a Raspberry Pi image from a Debian trixie base, and we currently work around it by installing `polkitd` before running `install.sh`.

### Note about the `dev` branch

On the `dev` branch, the `!` was removed:

```bash
dpkg-query -W --showformat='${Status}\n' polkitd >/dev/null 2>&1 && apt-get -y install polkitd
```

This installs polkitd in the case above, but no longer when dpkg does not know the package at all (`dpkg-query` then fails, so `apt-get` is not called).

### Suggested fix

Check the installation status itself, for example:

```bash
if [[ "$(dpkg-query -W --showformat='${db:Status-Status}' polkitd 2>/dev/null)" != "installed" ]]
then
  apt-get -y install polkitd
fi
```

(or simply always run `apt-get -y install polkitd`, which does nothing if the package is already installed.)
