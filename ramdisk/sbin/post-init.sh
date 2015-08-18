#!/system/bin/sh
# portions from franciscofranco, ak, boype & osm0sis + Franco's Dev Team

# custom busybox installation shortcut
bb=/sbin/bb/busybox;

# create and set permissions for /system/etc/init.d if it doesn't already exist
$bb mount -o rw,remount /system;
if [ ! -e /system/etc/init.d ]; then
  mkdir /system/etc/init.d;
  chown -R root.root /system/etc/init.d;
  chmod -R 766 /system/etc/init.d;
fi;

# disable sysctl.conf to prevent ROM interference with tunables
$bb [ -e /system/etc/sysctl.conf ] && $bb mv -f /system/etc/sysctl.conf /system/etc/sysctl.conf.bak;

# interactive tweaking
echo "70 300000:70 400000:75 500000:80 800000:85 1000000:70 1100000:80 1200000:80 1400000:85 1500000:95" > /sys/devices/system/cpu/cpufreq/interactive/target_loads;


# more rational defaults for KSM and enable deffered timer
echo 256 > /sys/kernel/mm/ksm/pages_to_scan;
echo 1500 > /sys/kernel/mm/ksm/sleep_millisecs;
echo 1 > /sys/kernel/mm/ksm/deferred_timer;

# double the default minfree kb
echo 8192 > /proc/sys/vm/min_free_kbytes;

# disable swappiness and reducce cache vfs pressure
echo 0 > /proc/sys/vm/swappiness;
echo 50 > /proc/sys/vm/vfs_cache_pressure;

# general queue tweaks
for i in /sys/block/mmcblk*/queue; do
  echo 512 > $i/read_ahead_kb;
done;


 # adjust f2fs partition RAM threshold to favor userdata and tweak garbage collection for smaller media
if [ -e /sys/fs/f2fs/mmcblk0p9 ]; then
  echo 20 > /sys/fs/f2fs/mmcblk0p9/ram_thresh;
fi;
