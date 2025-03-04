#!/bin/sh
set -e

if [ "$(which mkimage)" = "" ]
then
    echo "Error: u-boot's mkimage tool is needed (cf. u-boot-tools package). ABORTED."
    exit
fi

if [ -z "$1" ]
then
    echo "Error: do not call this script directly, call generate-boot-files.sh instead. ABORTED."
    exit
fi

source_script="$1"
output_script="$2"
shift 2

# create the source script by concatenating scripts for each boot step 
while [ ! -z "$1" ]
do
	step_script="u-boot-scripts/$1.sh"
	echo
	echo "# $step_script"
	cat "$step_script"
	shift
done > $source_script

# generate a "u-boot script" from this source (add u-boot header)
mkimage -A arm -O linux -T script -C none -n "${output_script}.scr" \
	-d $source_script "${output_script}"
echo "${output_script} was generated in the current directory."
