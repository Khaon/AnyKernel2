# AnyKernel 2.0 Ramdisk Mod Script 
# osm0sis @ xda-developers

## AnyKernel setup
# EDIFY properties
kernel.string='Khaon kernel for Mi2(s) devices'
do.devicecheck=1
do.initd=1
do.modules=0
do.cleanup=0
device.name1=aries
device.name2=
device.name3=
device.name4=
device.name5=

# shell variables
block=/dev/block/platform/msm_sdcc.1/by-name/boot;

## end setup


## AnyKernel methods (DO NOT CHANGE)
# set up extracted files and directories
ramdisk=/tmp/anykernel/ramdisk;
bin=/tmp/anykernel/tools;
split_img=/tmp/anykernel/split_img;
patch=/tmp/anykernel/patch;

chmod -R 755 $bin;
mkdir -p $ramdisk $split_img;
cd $ramdisk;

OUTFD=`ps | grep -v "grep" | grep -oE "update(.*)" | cut -d" " -f3`;
ui_print() { echo "ui_print $1" >&$OUTFD; echo "ui_print" >&$OUTFD; }

# dump boot and extract ramdisk
dump_boot() {
  dd if=$block of=/tmp/anykernel/boot.img;
  $bin/unpackbootimg -i /tmp/anykernel/boot.img -o $split_img;
  if [ $? != 0 ]; then
    ui_print " "; ui_print "Dumping/unpacking image failed. Aborting...";
    echo 1 > /tmp/anykernel/exitcode; exit;
  fi;
  gunzip -c $split_img/boot.img-ramdisk.gz | cpio -i;
}

# repack ramdisk then build and write image
write_boot() {
  cd $split_img;
  cmdline=`cat *-cmdline`;
  board=`cat *-board`;
  base=`cat *-base`;
  pagesize=`cat *-pagesize`;
  kerneloff=`cat *-kerneloff`;
  ramdiskoff=`cat *-ramdiskoff`;
  tagsoff=`cat *-tagsoff`;
  if [ -f *-second ]; then
    second=`ls *-second`;
    second="--second $split_img/$second";
    secondoff=`cat *-secondoff`;
    secondoff="--second_offset $secondoff";
  fi;
  if [ -f /tmp/anykernel/dtb ]; then
    dtb="--dt /tmp/anykernel/dtb";
  elif [ -f *-dtb ]; then
    dtb=`ls *-dtb`;
    dtb="--dt $split_img/$dtb";
  fi;
  cd $ramdisk;
  find . | cpio -H newc -o | gzip > /tmp/anykernel/ramdisk-new.cpio.gz;
  $bin/mkbootimg --kernel /tmp/anykernel/zImage --ramdisk /tmp/anykernel/ramdisk-new.cpio.gz $second --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff $secondoff --tags_offset $tagsoff $dtb --output /tmp/anykernel/boot-new.img;
  if [ $? != 0 -o `wc -c < /tmp/anykernel/boot-new.img` -gt `wc -c < /tmp/anykernel/boot.img` ]; then
    ui_print " "; ui_print "Repacking image failed. Aborting...";
    echo 1 > /tmp/anykernel/exitcode; exit;
  fi;
  dd if=/tmp/anykernel/boot-new.img of=$block;
}

# backup_file <file>
backup_file() { cp $1 $1~; }

# replace_string <file> <if search string> <original string> <replacement string>
replace_string() {
  if [ -z "$(grep "$2" $1)" ]; then
      sed -i "s;${3};${4};" $1;
  fi;
}

# insert_line <file> <if search string> <before/after> <line match string> <inserted line>
insert_line() {
  if [ -z "$(grep "$2" $1)" ]; then
    case $3 in
      before) offset=0;;
      after) offset=1;;
    esac;
    line=$((`grep -n "$4" $1 | cut -d: -f1` + offset));
    sed -i "${line}s;^;${5};" $1;
  fi;
}

# replace_line <file> <line replace string> <replacement line>
replace_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | cut -d: -f1`;
    sed -i "${line}s;.*;${3};" $1;
  fi;
}

# remove_line <file> <line match string>
remove_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | cut -d: -f1`;
    sed -i "${line}d" $1;
  fi;
}

#remove__all_lines <file> <line match string>
remove_all_lines() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    sed -i "/${2}/d" $1;
  fi;
}

# prepend_file <file> <if search string> <patch file>
prepend_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    echo "$(cat $patch/$3 $1)" > $1;
  fi;
}

# append_file <file> <if search string> <patch file>
append_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    echo -ne "\n" >> $1;
    cat $patch/$3 >> $1;
    echo -ne "\n" >> $1;
  fi;
}

# replace_file <file> <permissions> <patch file>
replace_file() {
  cp -fp $patch/$3 $1;
  chmod $2 $1;
}

## end methods


## AnyKernel permissions
# set permissions for included files
chmod -R 755 $ramdisk
chmod 644 $ramdisk/fstab-ext4.aries
chmod 644 $ramdisk/fstab-f2fs.aries

## AnyKernel install
dump_boot;

# begin ramdisk changes

# fstab.aries
backup_file init.aries.rc;
insert_line init.aries.rc "exec /fscheck" before "exec /sbin/dualboot_init ./fstab.aries" "\tchmod 766 /fscheck\n\texec /fscheck mkfstab\n";

# use my dualboot_init binary
replace_file $ramdisk/sbin/dualboot_init 755 dualboot_init;

# init.aries.rc
append_file init.aries.rc "fsprops" init.aries1;
append_file init.aries.rc "post-init" init.aries2;
remove_all_lines init.aries.rc "governor";
remove_all_lines init.aries.rc "scaling";
remove_all_lines init.aries.rc "msm_thermal";
remove_all_lines init.aries.rc "st.* mpdecision";
remove_all_lines init.aries.rc "st.* thermald";

# use Khaon's mount scripts and dual_boot_init
replace_file /system/bin/mount_ext4.sh 755 mount_khaon_userdata.sh
replace_file /system/bin/mount_khaon_userdata.sh 755 mount_khaon_userdata.sh

# end ramdisk changes

# add SELinux commandline only in KitKat and lollipop
android_ver=$(grep "^ro.build.version.release" /system/build.prop | cut -d= -f2;);
case $android_ver in
  4.4*) cmdtmp=`cat $split_img/*-cmdline`;
        case "$cmdtmp" in
          *selinux=permissive*) ;;
          *) echo "androidboot.selinux=permissive $cmdtmp" > $split_img/*-cmdline;;
        esac;;
  5.*) cmdtmp=`cat $split_img/*-cmdline`;
        case "$cmdtmp" in
          *selinux=permissive*) ;;
          *) echo "androidboot.selinux=permissive $cmdtmp" > $split_img/*-cmdline;;
        esac;;
esac;

#delete unwanted binaries and libraries
ui_print "";
ui_print "Deleting thermald, mpdecision binaries and powerHAL driver";

$ramdisk/sbin/bb/busybox rm -f /system/lib/hw/power.aries.so;
$ramdisk/sbin/bb/busybox rm -f /system/lib/hw/power.msm8960.so;
$ramdisk/sbin/bb/busybox rm -f /system/bin/mpdecision;
$ramdisk/sbin/bb/busybox rm -f /system/bin/thermald;

write_boot;
## end install
