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
bb=$ramdisk/sbin/bb/busybox;

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
  file=`$bb basename "/tmp/anykernel/boot.img"`;
  cd $split_img;
  $bin/file -m $bin/magic $split_img/boot.img-ramdisk.gz | $bb cut -d: -f2 | $bb cut -d" " -f2 > "$file-ramdiskcomp";
  ramdiskcomp=`cat *-ramdiskcomp`;
  unpackcmd="$bb $ramdiskcomp -dc";
  compext=$ramdiskcomp;
  case $ramdiskcomp in
    gzip) compext=gz;;
    lzop) compext=lzo;;
    xz) ;;
    lzma) ;;
    bzip2) compext=bz2;;
    lz4) unpackcmd="$bin/lz4 -dq"; extra="stdout";;
    *) compext="";;
  esac;
  ui_print " "; ui_print "Ramdisk was compressed with $ramdiskcomp"; ui_print " ";
  if [ "$compext" ]; then
    compext=.$compext;
  fi;
  mv "$file-ramdisk.gz" "$file-ramdisk.cpio$compext";
  cd ..;

  echo '\nUnpacking ramdisk to "ramdisk/"...\n';
  cd ramdisk;
  echo "Compression used: $ramdiskcomp";
  if [ ! "$compext" ]; then
    abort;
    return 1;
  fi;
  $unpackcmd "../split_img/$file-ramdisk.cpio$compext" $extra | $bb cpio -i;
  if [ $? != "0" ]; then
    abort;
    return 1;
  fi;
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
  find . | cpio -H newc -o | gzip > /tmp/anykernel/ramdisk-new.cpio.gzip;
  $bin/mkbootimg --kernel /tmp/anykernel/zImage --ramdisk /tmp/anykernel/ramdisk-new.cpio.gzip $second --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff $secondoff --tags_offset $tagsoff $dtb --output /tmp/anykernel/boot-new.img;
  ui_print " "; ui_print "repacking the ramdisk with gzip algorithm";
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
getfs() { $ramdisk/sbin/bb/busybox blkid $1 | grep -Eo 'TYPE="(.+)"' | $ramdisk/sbin/bb/busybox cut -d\" -f2; }

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

# edit build.prop to make the device debuggable
replace_line default.prop "ro.adb.secure=0" "ro.adb.secure=1":

#gpu scripts supports
if [ -f /data/su.img ]; then
  mkdir /su;
  mount -t ext4 -o loop /data/su.img /su;
  replace_file /su/su.d/99khaon_gpu_script 775 99khaon_gpu_script;
fi;


# end ramdisk changes

write_boot;

## end install
