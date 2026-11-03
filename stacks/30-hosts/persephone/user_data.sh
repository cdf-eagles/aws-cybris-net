#!/bin/sh
# First boot of persephone, rendered by templatefile(). It waits for the two
# data volumes to attach, labels and formats a volume only when it is blank,
# mounts both by their partition labels, creates the login account, and
# installs what Ansible needs to connect and become root; Ansible configures
# the rest. Safe to run again: each step checks before it acts, and a volume
# that holds anything is never written.
set -u

# templatefile() fills in these values before the script reaches the host.
# shellcheck disable=SC2269
login_account_name="${login_account_name}"
# shellcheck disable=SC2269
login_account_uid="${login_account_uid}"
# shellcheck disable=SC2269
login_account_gid="${login_account_gid}"
# shellcheck disable=SC2269
home_volume_id="${home_volume_id}"
# shellcheck disable=SC2269
web_volume_id="${web_volume_id}"
attach_wait=300
log=/var/log/user_data.log
failures=0

echo "user_data: logging to $log"
exec >>"$log" 2>&1
echo "user_data start $(date -u +%Y-%m-%dT%H:%M:%SZ)"
export ASSUME_ALWAYS_YES=yes

fail() {
	echo "FAILED: $*"
	failures=$((failures + 1))
}

# True when a line of the file (or of standard input) starts with the device
# and, if given, the mount point.
listed() {
	awk -v d="$1" -v m="$2" '$1 == d && (m == "" || $2 == m) { found = 1 } END { exit !found }' "$3"
}

if pkg install -y python3 sudo; then
	printf 'ec2-user ALL=(ALL:ALL) NOPASSWD: ALL\n' >/usr/local/etc/sudoers.d/ec2-user.new
	chmod 0440 /usr/local/etc/sudoers.d/ec2-user.new
	if /usr/local/sbin/visudo -cf /usr/local/etc/sudoers.d/ec2-user.new; then
		mv /usr/local/etc/sudoers.d/ec2-user.new /usr/local/etc/sudoers.d/ec2-user
	else
		rm -f /usr/local/etc/sudoers.d/ec2-user.new
		fail "sudoers rule for ec2-user"
	fi
else
	fail "pkg install python3 sudo"
fi

# The image mounts an empty zroot/home on /home; it would hide the home volume
# or be hidden by it, depending on the mount order.
if zfs list -H -o name zroot/home >/dev/null 2>&1; then
	zfs set canmount=off zroot/home || fail "zfs set canmount=off zroot/home"
	if [ "$(zfs get -H -o value mounted zroot/home)" = yes ]; then
		zfs unmount zroot/home || fail "zfs unmount zroot/home"
	fi
fi

# 30-hosts attaches the data volumes only once the instance is running, so this
# script can start before they appear. Prints the disk whose serial number is
# the volume ID without its dash, which is how EBS presents a volume over
# NVMe, waiting up to attach_wait seconds for it to attach.
find_disk() {
	fd_serial=$(printf '%s' "$1" | tr -d -)
	fd_waited=0
	while :; do
		for fd_disk in $(sysctl -n kern.disks); do
			if [ "$(diskinfo -s "$fd_disk" 2>/dev/null)" = "$fd_serial" ]; then
				echo "$fd_disk"
				return 0
			fi
		done
		if [ "$fd_waited" -ge "$attach_wait" ]; then
			for fd_disk in $(sysctl -n kern.disks); do
				echo "seen: $fd_disk ident $(diskinfo -s "$fd_disk" 2>/dev/null)" >&2
			done
			return 1
		fi
		sleep 5
		fd_waited=$((fd_waited + 5))
	done
}

# True when the mebibyte at the given offset, in mebibytes, reads back in full
# and holds only zero bytes.
zero_mib() {
	zm_sample=$(mktemp) || return 1
	zm_blank=1
	if dd if="/dev/$1" of="$zm_sample" bs=1m count=1 skip="$2" 2>/dev/null &&
		[ "$(stat -f %z "$zm_sample")" = 1048576 ] &&
		[ -z "$(od -An -v -tx1 "$zm_sample" | tr -d ' 0\n')" ]; then
		zm_blank=0
	fi
	rm -f "$zm_sample"
	return "$zm_blank"
}

# True only for a disk that has never been written: no partition table, no
# file system that fstyp(8) knows, and zeros in its first two mebibytes and
# its last, where an MBR, both GPT headers, and the superblock of a UFS
# partition aligned at one mebibyte live. Prints why when it is not.
blank_disk() {
	if gpart show "$1" >/dev/null 2>&1; then
		echo "$1 has a partition table"
		return 1
	fi
	if fstyp "/dev/$1" >/dev/null 2>&1; then
		echo "$1 holds a $(fstyp "/dev/$1" 2>/dev/null) file system"
		return 1
	fi
	bd_size=$(diskinfo "$1" 2>/dev/null | awk '{ print $3 }')
	case $bd_size in
	'' | *[!0-9]*)
		echo "$1 size unreadable"
		return 1
		;;
	esac
	if zero_mib "$1" 0 && zero_mib "$1" 1 && zero_mib "$1" $((bd_size / 1048576 - 1)); then
		return 0
	fi
	echo "$1 has data in its first two mebibytes or its last"
	return 1
}

format_disk() {
	if ! gpart create -s gpt "$1"; then
		fail "gpart create on $1"
		return 1
	fi
	# The table was created just now on a blank disk, so removing it again
	# leaves the disk blank for the next run.
	if ! gpart add -t freebsd-ufs -a 1m -l "$2" "$1"; then
		fail "gpart add $2 on $1"
		gpart destroy -F "$1" || fail "gpart destroy $1; the disk needs a person"
		return 1
	fi
	fm_tries=0
	while [ ! -e "/dev/gpt/$2" ] && [ "$fm_tries" -lt 10 ]; do
		sleep 1
		fm_tries=$((fm_tries + 1))
	done
	if [ ! -e "/dev/gpt/$2" ]; then
		fail "/dev/gpt/$2 did not appear; format of $1 incomplete, left for a person"
		return 1
	fi
	if ! newfs -U "/dev/gpt/$2"; then
		fail "newfs /dev/gpt/$2"
		return 1
	fi
	echo "$1 labelled $2 and formatted"
}

# Finds the volume's disk and, only when that disk is blank, gives it the GPT
# label and a UFS file system. A label already present must sit on the
# volume's own disk; a disk that holds anything else is never written.
prepare_data_volume() {
	if ! pv_disk=$(find_disk "$1"); then
		if [ -e "/dev/gpt/$2" ]; then
			echo "volume $1 not found by serial number; mounting the existing gpt/$2, which is on:"
			glabel status -s | awk -v l="gpt/$2" '$1 == l'
			return 0
		fi
		fail "volume $1 did not attach within $attach_wait seconds"
		return 1
	fi
	echo "volume $1 is $pv_disk"
	# GEOM tastes a disk's partitions and labels a moment after the disk
	# itself appears, and a volume restored from a snapshot reads slowly at
	# first, so the label is looked for over a few seconds.
	pv_tries=0
	while :; do
		pv_where=$(glabel status -s | awk -v l="gpt/$2" '$1 == l { print $3 }')
		if [ -n "$pv_where" ] || [ "$pv_tries" -ge 15 ]; then
			break
		fi
		sleep 1
		pv_tries=$((pv_tries + 1))
	done
	if [ -n "$pv_where" ]; then
		case $pv_where in
		"$pv_disk"p*)
			echo "gpt/$2 is on $pv_where"
			if [ "$(fstyp "/dev/gpt/$2" 2>/dev/null)" != ufs ]; then
				fail "gpt/$2 holds no UFS file system; format incomplete, left for a person"
				return 1
			fi
			return 0
			;;
		esac
		fail "gpt/$2 is on $pv_where, not on $pv_disk"
		return 1
	fi
	if blank_disk "$pv_disk"; then
		echo "$pv_disk is blank; labelling it $2 and formatting it"
		format_disk "$pv_disk" "$2"
		return
	fi
	fail "$pv_disk has no gpt/$2 label and is not blank; left untouched"
	return 1
}

mount_data_volume() {
	label=$1
	dir=$2
	dev=/dev/gpt/$label
	if [ ! -e "$dev" ]; then
		fail "$dev is missing; nothing mounted on $dir"
		return
	fi
	listed "$dev" "" /etc/fstab || printf '%s\t%s\tufs\trw\t0\t2\n' "$dev" "$dir" >>/etc/fstab
	if mount -p | listed "$dev" "" -; then
		echo "$dev already mounted"
		return
	fi
	mkdir -p "$dir"
	# Preen only: a file system that needs more than a preen is left
	# unmounted for a person rather than repaired unattended.
	if ! fsck -t ufs -p "$dev"; then
		fail "fsck -p $dev needs a person; nothing mounted on $dir"
		return
	fi
	mount "$dir" || fail "mount $dev on $dir"
}

data_volume() {
	if prepare_data_volume "$1" "$2"; then
		mount_data_volume "$2" "$3"
	else
		fail "nothing mounted on $3"
	fi
}

data_volume "$home_volume_id" homedirs /home
data_volume "$web_volume_id" apachedirs /usr/local/www/apache24

if mount -p | listed /dev/gpt/homedirs /home -; then
	home=/home/$login_account_name
	if pw usershow -n "$login_account_name" >/dev/null 2>&1; then
		echo "login account exists with uid $(id -u "$login_account_name"); left as is"
	elif pw usershow -u "$login_account_uid" >/dev/null 2>&1; then
		fail "uid $login_account_uid is taken; login account not created"
	else
		if ! pw groupshow -n "$login_account_name" >/dev/null 2>&1; then
			if pw groupshow -g "$login_account_gid" >/dev/null 2>&1; then
				fail "gid $login_account_gid is taken; login account not created"
			else
				pw groupadd -n "$login_account_name" -g "$login_account_gid" || fail "groupadd"
			fi
		fi
		if pw groupshow -n "$login_account_name" >/dev/null 2>&1; then
			if pw useradd -n "$login_account_name" -u "$login_account_uid" -g "$login_account_name" \
				-d "$home" -s /bin/sh -w no; then
				echo "login account created with uid $login_account_uid"
			else
				fail "useradd"
			fi
		fi
	fi
	if [ ! -e "$home" ] && pw usershow -n "$login_account_name" >/dev/null 2>&1; then
		if install -d -m 0755 -o "$login_account_name" -g "$login_account_name" "$home"; then
			echo "created $home"
		else
			fail "create $home"
		fi
	fi
	# ec2-user has fixed IDs, 1000:1000: below the 1001 the image's own accounts
	# start from (the image's ssm-user takes 1001; it moves to 9002 below) and
	# never used by the ports tree. Its home on the volume is handed to it when
	# another ID owns it.
	ec2home=/home/ec2-user
	ec2id=1000
	if ! pw usershow -n ec2-user >/dev/null 2>&1; then
		if pw usershow -u "$ec2id" >/dev/null 2>&1 || pw groupshow -g "$ec2id" >/dev/null 2>&1; then
			fail "uid or gid $ec2id is taken; ec2-user not created"
		elif pw groupadd -n ec2-user -g "$ec2id" &&
			pw useradd -n ec2-user -u "$ec2id" -g ec2-user -G wheel -d "$ec2home" -s /bin/sh -w no; then
			echo "ec2-user created with uid $ec2id"
		else
			fail "create ec2-user"
		fi
	elif [ "$(id -u ec2-user)" != "$ec2id" ]; then
		fail "ec2-user exists with uid $(id -u ec2-user), not $ec2id"
	fi
	if pw usershow -n ec2-user >/dev/null 2>&1; then
		if [ ! -d "$ec2home" ]; then
			install -d -m 0755 -o ec2-user -g ec2-user "$ec2home" || fail "create $ec2home"
		elif [ "$(stat -f %u:%g "$ec2home")" != "$(id -u ec2-user):$(id -g ec2-user)" ]; then
			if chown -R ec2-user:ec2-user "$ec2home"; then
				echo "$ec2home handed to ec2-user (uid $(id -u ec2-user))"
			else
				fail "chown $ec2home"
			fi
		fi
	fi
	# ssm-user comes with the image at 1001:1001. persephone keeps it at
	# 9002:9002 (certbot holds 9001), the IDs that own its home on the volume
	# and the ones persephone.cybris.net's persephone_customizations role
	# checks. At first boot it owns only what the image made, so it is
	# renumbered here and those files re-owned; the data volumes are skipped,
	# since their files already carry 9002. Later, renumbering would be a job
	# for a person, which is why the role only checks.
	ssmid=9002
	ssmhome=/home/ssm-user
	if ! pw usershow -n ssm-user >/dev/null 2>&1; then
		fail "the image has no ssm-user; persephone_customizations will refuse the host"
	else
		ssmold=$(id -u ssm-user)
		ssmoldg=$(id -g ssm-user)
		if [ "$ssmold:$ssmoldg" = "$ssmid:$ssmid" ]; then
			echo "ssm-user is $ssmid:$ssmid; left as is"
		elif { [ "$ssmold" != "$ssmid" ] && pw usershow -u "$ssmid" >/dev/null 2>&1; } ||
			{ [ "$ssmoldg" != "$ssmid" ] && pw groupshow -g "$ssmid" >/dev/null 2>&1; }; then
			fail "uid or gid $ssmid is taken; ssm-user left at $ssmold:$ssmoldg"
		elif pw groupmod ssm-user -g "$ssmid" && pw usermod ssm-user -u "$ssmid" -g "$ssmid"; then
			if find / \( -path /dev -o -path /home -o -path /usr/local/www/apache24 \) -prune -o \
				-user "$ssmold" -exec chown -h "$ssmid" {} + &&
				find / \( -path /dev -o -path /home -o -path /usr/local/www/apache24 \) -prune -o \
					-group "$ssmoldg" -exec chgrp -h "$ssmid" {} +; then
				echo "ssm-user renumbered $ssmold:$ssmoldg -> $ssmid:$ssmid and its files re-owned"
			else
				fail "re-own ssm-user's files after renumbering"
			fi
		else
			fail "renumber ssm-user to $ssmid:$ssmid"
		fi
		if [ -d "$ssmhome" ] && [ "$(stat -f %u:%g "$ssmhome")" != "$(id -u ssm-user):$(id -g ssm-user)" ]; then
			if chown -R ssm-user:ssm-user "$ssmhome"; then
				echo "$ssmhome handed to ssm-user (uid $(id -u ssm-user))"
			else
				fail "chown $ssmhome"
			fi
		fi
	fi
	ls -lnd /home/*
else
	fail "/home is not the home volume; login account not created"
fi

echo "user_data end $(date -u +%Y-%m-%dT%H:%M:%SZ), $failures failure(s)"
exit "$failures"
