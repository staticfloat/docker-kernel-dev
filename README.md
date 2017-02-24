# Docker kernel dev env

Using the magic of virtualization, we will experiment with kernel features in `docker`.

* `make build` will download the linux kernel, (`v4.10` as of this writing), configure it for KVM/docker compatible features, use `debootstrap` to generate a minimal userspace, and build `bzImage` and `root.img` in the current directory.

* `make run` will launch `kvm`/`qemu-system-x86_64` on the generated files

This was designed so that I could try out kernel development for a bit, specifically for the use case of trying to fix `inotify` issues on `overlay2` filesystems.
