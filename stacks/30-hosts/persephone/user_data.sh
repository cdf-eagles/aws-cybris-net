#!/bin/sh
# First boot of persephone, rendered by templatefile(). It mounts the two data
# volumes by their partition labels, creates the login account, and installs
# what Ansible needs to connect and become root; Ansible configures the rest.
# Safe to run again: each step checks before it acts, and no volume is ever
# formatted.
set -u

# templatefile() fills in these three values before the script reaches the host.
# shellcheck disable=SC2269
login_account_name="${login_account_name}"
# shellcheck disable=SC2269
login_account_uid="${login_account_uid}"
# shellcheck disable=SC2269
login_account_gid="${login_account_gid}"
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
	fsck -t ufs -y "$dev" || fail "fsck $dev"
	mount "$dir" || fail "mount $dev on $dir"
}

mount_data_volume homedirs /home
mount_data_volume apachedirs /usr/local/www/apache24

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
	# ec2-user's home on the volume keeps the owner it had on the old host;
	# sshd refuses a home owned by another user, so ec2-user takes that owner's
	# IDs when it does not exist yet, or the home is handed to it otherwise.
	ec2home=/home/ec2-user
	if [ -d "$ec2home" ]; then
		ec2uid=$(stat -f %u "$ec2home")
		ec2gid=$(stat -f %g "$ec2home")
		if ! pw usershow -n ec2-user >/dev/null 2>&1; then
			if pw usershow -u "$ec2uid" >/dev/null 2>&1 || pw groupshow -g "$ec2gid" >/dev/null 2>&1; then
				fail "uid $ec2uid or gid $ec2gid is taken; ec2-user not created"
			elif pw groupadd -n ec2-user -g "$ec2gid" &&
				pw useradd -n ec2-user -u "$ec2uid" -g ec2-user -G wheel -d "$ec2home" -s /bin/sh -w no; then
				echo "ec2-user created with uid $ec2uid to match $ec2home"
			else
				fail "create ec2-user"
			fi
		elif [ "$(id -u ec2-user)" != "$ec2uid" ]; then
			if chown -R ec2-user:ec2-user "$ec2home"; then
				echo "$ec2home handed to ec2-user (uid $(id -u ec2-user))"
			else
				fail "chown $ec2home"
			fi
		fi
	fi
	ls -lnd /home/*
else
	fail "/home is not the home volume; login account not created"
fi

echo "user_data end $(date -u +%Y-%m-%dT%H:%M:%SZ), $failures failure(s)"
exit "$failures"
