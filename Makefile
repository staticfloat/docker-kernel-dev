all: build


src/linux.tar.xz:
	@mkdir -p src
	@echo "Downloading kernel..."
	@curl -L 'https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.10.tar.xz' -o "$@"

src/linux/.unpacked: src/linux.tar.xz
	@mkdir -p src/linux
	echo "Extracting linux...."
	@tar Jxf "$<" -C src/linux --strip-components=1
	@touch "$@"

YES_OPTS = \
	CGROUP_DEVICE MEMCG MEMCG_SWAP MEMCG_SWAP_ENABLED \
	VETH BRIDGE BRIDGE_NETFILTER \
	NETFILTER_XT_MATCH_IPVS DEVPTS_MULTIPLE_INSTANCES \
	OVERLAY_FS MACVLAN DUMMY BRIDGE_IGMP_SNOOPING \
	DUMMY_IRQ MEMCG_SWAP OVERLAYFS_REDIRECT_DIR \
	OVERLAY_FS_REDIRECT_DIR \


NO_OPTS = \
	BRIDGE_NF_EBTABLES MACVTAP


src/linux/.config: src/linux/.unpacked
	# Grab the default config for this arch
	@cd src/linux; make defconfig; make kvmconfig
	# Set configuration options we need
	@for opt in $(YES_OPTS); do \
		grep -v -e "CONFIG_$$opt[^_]" "$@" >> "$@.edit"; \
		echo "CONFIG_$$opt=y" >> "$@.edit"; \
		mv "$@.edit" "$@"; \
	done

	# Set configuration options we don't want
	@for opt in $(NO_OPTS); do \
		grep -v "CONFIG_$$opt" "$@" >> "$@.edit"; \
		echo "CONFIG_$$opt=n" >> "$@.edit"; \
		mv "$@.edit" "$@"; \
	done

src/check-config.sh: 
	@curl -# -L 'https://raw.githubusercontent.com/docker/docker/master/contrib/check-config.sh' -o "$@"
	@chmod +x "$@"
check-config: src/check-config.sh src/linux/.config
	-./src/check-config.sh ./src/linux/.config

bzImage: src/linux/.config
	TOP=$$(pwd); cd src/linux; make -j3; sudo make INSTALL_MOD_PATH=$$TOP/src/debootstrap/ modules_install
	ln -sf src/linux/arch/x86/boot/bzImage bzImage


src/debootstrap/bin/bash:
	@sudo debootstrap --include openssh-server,curl jessie src/debootstrap || (echo "This often fails with download errors; try just running it again and again until all the downloads go through"; false)
debootstrap: src/debootstrap/bin/bash

src/debootstrap/.patched: src/debootstrap/bin/bash
	cd src/debootstrap && \
	sudo sed -i '/^root/ { s/:x:/::/ }' etc/passwd && \
	echo 'V0:23:respawn:/sbin/getty 115200 hvc0' | sudo tee -a etc/inittab && \
	printf '\nauto eth0\niface eth0 inet dhcp\n' | sudo tee -a etc/network/interfaces && \
	printf '\nauto eth0\niface eth0 inet dhcp\n' | sudo tee -a etc/network/interfaces && \
	sudo mkdir root/.ssh && \
	find ~/.ssh -name id_rsa.pub | xargs cat | sudo tee root/.ssh/authorized_keys && \
	echo "/dev/vda / ext4 defaults 1 1" | sudo tee -a etc/fstab && \
	sudo touch .patched


root.img: src/debootstrap/.patched
	dd if=/dev/zero of=$@ bs=1M seek=4095 count=1
	mkfs.ext4 -F $@
	sudo mkdir -p /mnt/debootstrap
	sudo mount -o loop $@ /mnt/debootstrap
	sudo cp -a src/debootstrap/. /mnt/debootstrap/.
	sudo umount /mnt/debootstrap
	
run: bzImage root.img
	sudo kvm \
		-kernel ./bzImage \
		-drive format=raw,file=root.img,if=virtio \
		-chardev stdio,id=stdio,mux=on,signal=off \
		-mon chardev=stdio -append 'root=/dev/vda console=hvc0' \
		-device virtio-serial-pci -device virtconsole,chardev=stdio \
		-display none \
		-net nic,model=virtio,macaddr=52:54:00:12:34:56 \
		-net user,hostfwd=tcp:127.0.0.1:4444-:22
 

kernel: bzImage
image: root.img
build: kernel image

clean-config:
	rm -f src/linux/.config
	@$(MAKE) src/linux/.config
clean:
	rm -rf src

