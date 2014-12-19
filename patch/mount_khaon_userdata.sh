#!/system/bin/sh
export PATH=/system/bin:/system/xbin:$PATH
BLOCK_DEVICE=$1
BLOCK_NODE="$(/sbin/bb/busybox readlink -f ${BLOCK_DEVICE})"
MOUNT_POINT=$2
TDB_PATH=/data_root/.truedualboot
LOG_FILE="/dev/null"
LOG_LOCATION="/data/.fsck_log/"
tdb_enabled= 

# storage log
if [ "${MOUNT_POINT}" == "/storage_int" ]; then
    mkdir ${LOG_LOCATION}
    busybox find /data/.fsck_log/ -type f -mtime +7  -exec rm {} \;
    TIMESTAMP=`date +%F_%H-%M-%S`
    LOG_FILE=${LOG_LOCATION}/storage_${TIMESTAMP}.log
fi

# get syspart-flag from cmdline
set -- $(cat /proc/cmdline)
for x in "$@"; do
    case "$x" in
        syspart=*)
        SYSPART=$(echo "${x#syspart=}")
        ;;
    esac
done

# check partition filesystem
getfs() { /sbin/bb/busybox blkid $1 | /sbin/bb/busybox cut -d\" -f4; }

# mount partition
if [ -e ${BLOCK_DEVICE} ]; then
	if [ `getfs ${BLOCK_NODE}` == "f2fs" ]; then  
      FS_TYPE=f2fs
      OPTS=rw,noatime,nosuid,nodev,discard,nodiratime,inline_xattr,inline_data,flush_merge
	else		 
      FS_TYPE=ext4
      OPTS=noatime,nosuid,nodev,barrier=1,noauto_da_alloc
	fi;
fi

# mount partition
if [ -e ${BLOCK_DEVICE} ]; then
    # userdata
    if [ "${BLOCK_DEVICE}" == "/dev/block/platform/msm_sdcc.1/by-name/userdata" ];then

        if [ "${SYSPART}" == "system" ];then
            BINDMOUNT_PATH="/data_root/system0"
        elif [ "${SYSPART}" == "system1" ];then
            BINDMOUNT_PATH="/data_root/system1"
        else
            reboot recovery
        fi;

        # mount /data_root
        mkdir -p /data_root
        chmod 0755 /data_root
        mount -t ${FS_TYPE} -o ${OPTS} ${BLOCK_DEVICE} /data_root

        if [ -e ${TDB_PATH} ]; then
          # bind mount
          mkdir -p ${BINDMOUNT_PATH}
          chmod 0755 ${BINDMOUNT_PATH}
          mount -o bind ${BINDMOUNT_PATH} ${MOUNT_POINT}
        else
          umount /data_root;
          mount -t ${FS_TYPE} -o ${OPTS} ${BLOCK_DEVICE} ${MOUNT_POINT}
        fi;
    # normal mount
    else
        mount -t ${FS_TYPE} -o ${OPTS} ${BLOCK_DEVICE} ${MOUNT_POINT}
    fi
fi

NO_HIDE="$(getprop ro.keep.recovery.partition)"
if [ "${NO_HIDE}" != "1" ]; then
    # hide recovery partition
    RECOVERY_NODE="$(busybox readlink -f /dev/block/platform/msm_sdcc.1/by-name/recovery)"
    busybox mv "${RECOVERY_NODE}" /dev/recovery_moved
    busybox mknod -m 0600 "${RECOVERY_NODE}" b 1 3
fi
