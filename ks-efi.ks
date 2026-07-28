# ks-efi.ks -- Rocky Linux Kickstart, UEFI installs only
# vim: set syntax=kickstart tabstop=4 shiftwidth=4 expandtab:

text
eula --agreed
reboot --eject

cdrom

lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone Etc/UTC --utc

network --bootproto=dhcp --device=link --activate --onboot=yes
network --hostname=rocky

selinux --enforcing
firewall --enabled --service=ssh
services --enabled=sshd,NetworkManager,chronyd

rootpw --lock
user --name=rocky --gecos="Rocky" --groups=wheel --iscrypted --password=$6$CWdqBdH5BBZ32YL/$eCHCMRvxR6KyQ9feYIsgNOCsCHfdWX2t3iYSgD.45N3B0ZGCCGf91Er6YL.ERons5bXdsgvgx7tR4VcTpaKgD/

%pre --erroronfail --log=/tmp/ks-pre.log

: > /tmp/disk-include

for dev in /sys/block/* ; do
    # An unmatched glob leaves the literal "/sys/block/*" in $dev, which falls
    # through every filter below and writes "ignoredisk --only-use=*".
    [ -d "$dev" ] || continue
    name=${dev##*/}
    case "$name" in
        loop*|sr*|fd*|ram*|zram*|dm-*|md*|nbd*) continue ;;
    esac
    [ "$(cat "$dev/removable" 2>/dev/null)" = "1" ] && continue
    lsblk -no LABEL "/dev/$name" 2>/dev/null | grep -qx OEMDRV && continue
    echo "ignoredisk --only-use=$name" > /tmp/disk-include
    break
done

if [ ! -s /tmp/disk-include ] ; then
    echo "ERROR: no install target found." >&2
    echo "Every disk was removable, or the only one attached is the OEMDRV seed." >&2
    echo "Attach a fixed disk, or pin one with 'ignoredisk --only-use=' in the kickstart." >&2
    exit 1
fi

exit 0
%end

%include /tmp/disk-include

clearpart --all --initlabel --disklabel=gpt

part /boot/efi --fstype=efi --size=1024 --fsoptions="umask=0077,shortname=winnt"

part /boot --fstype=xfs   --size=1024
part pv.01 --fstype=lvmpv --size=1 --grow

volgroup vg1 pv.01

logvol /              --vgname=vg1 --name=lv_root  --fstype=xfs  --size=6144
logvol swap           --vgname=vg1 --name=lv_swap  --fstype=swap --size=4096
logvol /tmp           --vgname=vg1 --name=lv_tmp   --fstype=xfs  --size=4096
logvol /home          --vgname=vg1 --name=lv_home  --fstype=xfs  --size=4096
logvol /var           --vgname=vg1 --name=lv_var   --fstype=xfs  --size=4096
logvol /var/log       --vgname=vg1 --name=lv_log   --fstype=xfs  --size=4096
logvol /var/log/audit --vgname=vg1 --name=lv_audit --fstype=xfs  --size=1024

bootloader --location=mbr --timeout=5

%packages
@^minimal-environment
openssh-server
sudo
chrony
tar
lvm2

gcc
gcc-c++
make
glibc-devel
kernel-devel

%end

%post --log=/root/ks-post.log
echo "rocky ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/rocky
chmod 440 /etc/sudoers.d/rocky

mkdir -p /etc/ssh/sshd_config.d
echo "PasswordAuthentication yes" > /etc/ssh/sshd_config.d/50-autoinstall.conf
chmod 600 /etc/ssh/sshd_config.d/50-autoinstall.conf

%end
