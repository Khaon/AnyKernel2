# AnyKernel 2.0 Ramdisk Mod Script 
# osm0sis @ xda-developers

## AnyKernel setup
# EDIFY properties
kernel.string=Khaon kernel for nexus 10 device
do.devicecheck=1
do.initd=1
do.modules=0
do.cleanup=0
device.name1=manta
device.name2=
device.name3=
device.name4=
device.name5=

# shell variables
block=/dev/block/platform/dw_mmc.0/by-name/boot;

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
  if [ -f /tmp/anykernel/zImage ]; then
    kernel=/tmp/anykernel/zImage;
  else
    kernel=`ls *-zImage`;
    kernel=$split_img/$kernel;
  fi;
  if [ -f /tmp/anykernel/dtb ]; then
    dtb="--dt /tmp/anykernel/dtb";
  elif [ -f *-dtb ]; then
    dtb=`ls *-dtb`;
    dtb="--dt $split_img/$dtb";
  fi;
  cd $ramdisk;
  find . | cpio -H newc -o | gzip > /tmp/anykernel/ramdisk-new.cpio.gz;
  $bin/mkbootimg --kernel $kernel --ramdisk /tmp/anykernel/ramdisk-new.cpio.gz $second --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff $secondoff --tags_offset $tagsoff $dtb --output /tmp/anykernel/boot-new.img;
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

# check partition filesystem
getfs() { $ramdisk/sbin/bb/busybox blkid $1 | $ramdisk/sbin/bb/busybox cut -d\" -f4; }

# patch the fstab accordingly to the current partitions's file systems
patch_fstab() {
  bb=$ramdisk/sbin/bb/busybox;
  cache=/dev/block/platform/dw_mmc.0/by-name/cache;
  data=/dev/block/platform/dw_mmc.0/by-name/userdata;
  system=/dev/block/platform/dw_mmc.0/by-name/system;
  prefix=/dev/block/platform/dw_mmc.0/by-name;
  device=manta;

  # swap out entries for filesystems as detected
  for i in $system $cache $data; do
    fstype=`getfs $i`;
    fsentry=`$bb grep $i $ramdisk/fstab-$fstype.$device`;
    if [ "$fsentry" ]; then
      ui_print "${i#${prefix}}'s file system is $fstype";
      $bb sed -i "s|^$i.*|$fsentry|" $ramdisk/fstab.$device;
    fi;
  done;
  ui_print "fstab patching done.";
  ui_print " ";
  ui_print "If you migrate from ext4 to f2fs or vice versa.";
  ui_print "You will have to install this package again.";
  $bb rm -f $ramdisk/fstab-*;
}

## end methods


## AnyKernel permissions
# set permissions for included files
chmod -R 755 $ramdisk
chmod 644 $ramdisk/fstab-ext4.manta
chmod 644 $ramdisk/fstab-f2fs.manta


## AnyKernel install
dump_boot;

# begin ramdisk changes

# patch fstab
backup_file fstab.manta;
patch_fstab;

# init.manta.rc
append_file init.manta.rc "post-init" init.manta;
append_file init.manta.rc "fsprops" init.manta2;
append_file init.manta.rc "usbdisk" init.manta3;
if [ ! -f $ramdisk/init.cm.rc ]; then
	append_file init.manta.rc "run-parts" init.manta4;
fi;

# use khaon's power.manta.so
backup_file /system/lib/hw/power.manta.so;
replace_file /system/lib/hw/power.manta.so 644 power.manta.so;

# edit build.prop to make the device debuggable
replace_line default.prop "ro.adb.secure=0" "ro.adb.secure=1":

# USB OTG support
insert_line init.manta.rc "usbdisk" after "start watchdogd" "# USB OTG support\n\tmkdir /mnt/media_rw/usbdisk 0700 media_rw media_rw\n\tmkdir /storage/usbdisk 0700 root root\n\tsymlink /storage/usbdisk /mnt/usbdisk\n\tsymlink /mnt/usbdisk /usbdisk\n\tEXPORT SECONDARY_STORAGE /storage/usbdisk\n";
append_file fstab.manta "s5p-ehci" fstab.manta;

# D2W support
insert_line init.manta.rc "DT2W" before "smb347-regs" "    # permission for DT2W\n    chmod 0664 /sys/android_touch/suspended\n    chown system system /sys/android_touch/suspended\n\n";
insert_line init.manta.rc "D2W" after "smb347-regs" "    # permission for D2W\n    chmod 0664 /sys/devices/platform/s3c2440-i2c.3/i2c-3/3-004a/suspended\n    chown system system /sys/devices/platform/s3c2440-i2c.3/i2c-3/3-004a/suspended\n";

# GPU init.d script
replace_file /system/etc/init.d/99khaon_gpu_controls 775 99khaon_gpu_controls;

# end ramdisk changes

write_boot;

## end install

