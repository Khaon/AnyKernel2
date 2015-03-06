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

# use frandom as random numbers generators
#chmod 644 /dev/frandom
#mv /dev/random /dev/random.ori
#ln /dev/frandom /dev/random
#chmod 644 /dev/random

# interactive tweaking
echo "70 300000:70 400000:75 500000:80 800000:85 1000000:70 1100000:80 1200000:85 1300000:90 1400000:95 1500000:99" > /sys/devices/system/cpu/cpufreq/interactive/target_loads;
echo 17000 > /sys/devices/system/cpu/cpufreq/interactive/sync_freq;
echo 14000 > /sys/devices/system/cpu/cpufreq/interactive/up_threshold_any_cpu_freq;
echo 95 > /sys/devices/system/cpu/cpufreq/interactive/up_threshold_any_cpu_load;

# disable debugging
echo 0 > /sys/module/wakelock/parameters/debug_mask;
echo 0 > /sys/module/userwakelock/parameters/debug_mask;
echo 0 > /sys/module/earlysuspend/parameters/debug_mask;
echo 0 > /sys/module/alarm/parameters/debug_mask;
echo 0 > /sys/module/alarm_dev/parameters/debug_mask;
echo 0 > /sys/module/binder/parameters/debug_mask;
echo 0 > /sys/module/kernel/parameters/initcall_debug;
echo 0 > /sys/module/xt_qtaguid/parameters/debug_mask;

# suitable configuration to help reduce network latency
echo 2 > /proc/sys/net/ipv4/tcp_ecn;
echo 1 > /proc/sys/net/ipv4/tcp_sack;
echo 1 > /proc/sys/net/ipv4/tcp_dsack;
echo 1 > /proc/sys/net/ipv4/tcp_low_latency;
echo 1 > /proc/sys/net/ipv4/tcp_timestamps;
echo 1 > /proc/sys/net/ipv4/tcp_tw_recycle;
echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse;

# set up TCP delayed ACK
chown system:system /sys/kernel/ipv4/tcp_delack_seg /sys/kernel/ipv4/tcp_use_userconfig;

# reduce txqueuelen to 0 to switch from a packet queue to a byte one
for i in /sys/class/net/*; do
  echo 0 > $i/tx_queue_len;
done;

# tweak for slightly larger kernel entropy pool
echo 768 > /proc/sys/kernel/random/read_wakeup_threshold;
echo 256 > /proc/sys/kernel/random/write_wakeup_threshold;

# increase sched timings
echo 15000000 > /proc/sys/kernel/sched_latency_ns;
echo 2000000 > /proc/sys/kernel/sched_min_granularity_ns;
echo 2500000 > /proc/sys/kernel/sched_wakeup_granularity_ns;
echo 962500 > /proc/sys/kernel/sched_rt_runtime_us;

# adjust cgroup timings and decrease max realtime cpu runtime of background tasks
echo 962500 > /dev/cpuctl/cpu.rt_runtime_us;
echo 91 > /dev/cpuctl/apps/bg_non_interactive/cpu.shares;
echo 400000 > /dev/cpuctl/apps/bg_non_interactive/cpu.rt_runtime_us;

# more rational defaults for KSM and enable deffered timer
echo 256 > /sys/kernel/mm/ksm/pages_to_scan;
echo 1500 > /sys/kernel/mm/ksm/sleep_millisecs;
echo 1 > /sys/kernel/mm/ksm/deferred_timer;

# initialize cgroup timer_slack for background tasks
echo 50000000 > /dev/cpuctl/apps/bg_non_interactive/timer_slack.min_slack_ns;

# decrease fs lease time
echo 10 > /proc/sys/fs/lease-break-time;


# disabled ASLR to increase AEM-JIT cache hit rate
echo 0 > /proc/sys/kernel/randomize_va_space;

# double the default minfree kb
echo 8192 > /proc/sys/vm/min_free_kbytes;

# disable swappiness and reducce cache vfs pressure
echo 0 > /proc/sys/vm/swappiness;
echo 35 > /proc/sys/vm/vfs_cache_pressure;

#vm tweaks
echo 15 > /proc/sys/vm/dirty_ratio;
echo 5 > /proc/sys/vm/dirty_background_ratio;
echo 200 > /proc/sys/vm/dirty_expire_centisecs;
echo 1000 > /proc/sys/vm/dirty_writeback_centisecs;
echo 4 > /proc/sys/vm/min_free_order_shift;
echo 3 > /proc/sys/vm/page-cluster;

# general queue tweaks
for i in /sys/block/*/queue; do
  echo 512 > $i/nr_requests;
  echo 1024 > $i/read_ahead_kb;
  echo 2 > $i/rq_affinity;
  echo 0 > $i/nomerges;
  echo 0 > $i/add_random;
  echo 0 > $i/rotational;
done;

# adjust ext4 partition inode readahead
for part in /sys/fs/ext4/mmcblk0p*; do
  echo 64 > $part/inode_readahead_blks;
done;

 # adjust f2fs partition RAM threshold to favor userdata and tweak garbage collection for smaller media
if [ -e /sys/fs/f2fs/mmcblk0p9 ]; then
  echo 20 > /sys/fs/f2fs/mmcblk0p9/ram_thresh;
fi;
for part in /sys/fs/f2fs/mmcblk0p*; do
  echo 2048 > $part/max_victim_search;
done;

# wait for systemui, move it to parent task group, move ksmd to background task group, and adjust systemui+kswapd priorities
while sleep 1; do
  if [ "$($bb pidof com.android.systemui)" ]; then
    systemui=`$bb pidof com.android.systemui`;
    echo $systemui > /dev/cpuctl/tasks;
    echo `$bb pgrep ksmd` > /dev/cpuctl/apps/bg_non_interactive/tasks;
    echo -17 > /proc/$systemui/oom_adj;
    $bb renice -18 $systemui;
    $bb renice 5 `$bb pgrep kswapd`;
    exit;
  fi;
done&

# lmk whitelist for common launchers+systemui and increase launcher priority
list="com.android.launcher com.google.android.googlequicksearchbox org.adw.launcher org.adwfreak.launcher net.alamoapps.launcher com.anddoes.launcher com.android.lmt com.chrislacy.actionlauncher.pro com.cyanogenmod.trebuchet com.gau.go.launcherex com.gtp.nextlauncher com.miui.mihome2 com.mobint.hololauncher com.mobint.hololauncher.hd com.mycolorscreen.themer com.qihoo360.launcher com.teslacoilsw.launcher com.tsf.shell org.zeam";
while sleep 60; do
  for class in $list; do
    if [ "$($bb pgrep $class)" ]; then
      for launcher in `$bb pgrep $class`; do
        echo -17 > /proc/$launcher/oom_score_adj;
        $bb renice -18 $launcher;
      done;
    fi;
  done;
  exit;
done&

