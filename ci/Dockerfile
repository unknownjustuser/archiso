# Use the Arch Linux base image with development tools
FROM archlinux:base-devel

RUN pacman-key --init && pacman-key --recv-key 3056513887B78AEB  --keyserver keyserver.ubuntu.com && pacman-key --lsign-key 3056513887B78AEB  && pacman --noconfirm -U 'https://geo-mirror.chaotic.cx/chaotic-aur/chaotic-'{keyring,mirrorlist}'.pkg.tar.zst' && echo "[multilib]" >>/etc/pacman.conf && echo "Include = /etc/pacman.d/mirrorlist" >>/etc/pacman.conf && echo -e "\\n[chaotic-aur]\\nInclude = /etc/pacman.d/chaotic-mirrorlist" >>/etc/pacman.conf && echo "" >>/etc/pacman.conf && pacman -Syu --noconfirm python-apprise reflector rsync curl wget git-lfs openssh base-devel devtools sudo git lib32-readline lib32-zlib namcap fakeroot audit grep diffutils parallel archiso btrfs-progs lsb-release wget cronie && pacman -Scc --noconfirm

RUN sh <(wget -qO- https://blackarch.org/strap.sh) --noconfirm && pacman -Syyu --noconfirm

RUN sed -i "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g" /etc/locale.gen && \
  locale-gen && \
  echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
  echo 'KEYMAP=us' > /etc/vconsole.conf

# Add builder User
RUN useradd -m -d /home/builder -s /bin/bash -G wheel builder && \
  sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers && \
  echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
  echo "root ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER builder
WORKDIR /home/builder

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/core_perl"

# install yay
RUN \
  cd /home/builder && \
  curl -O -s https://aur.archlinux.org/cgit/aur.git/snapshot/yay-bin.tar.gz && \
  tar xf yay-bin.tar.gz && \
  cd yay-bin && makepkg -is --skippgpcheck --noconfirm --noprogressbar && cd - && \
  rm -rf yay-bin* && \
  yay -S paru powerpill rate-mirrors-bin --noconfirm --needed --noprogressbar

RUN paru -Scc --noconfirm && yay -Scc --noconfirm && \
  paru -Syy

USER root

WORKDIR /tmp
