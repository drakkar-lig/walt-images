
setenv dl_wget_cmd 'wget $dl_addr /boot/$dl_file'
setenv dl_tftp_cmd 'tftp $dl_addr $dl_file'

setenv dl_cmd 'if test x${has_wget} = x1 -a x${use_wget} = x1; then run dl_wget_cmd || run dl_tftp_cmd || reset; else run dl_tftp_cmd || reset; fi'
