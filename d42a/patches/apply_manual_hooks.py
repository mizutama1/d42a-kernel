#!/usr/bin/env python3
"""KernelSU-Next manual hook をカーネルソースへ挿入する。

4.14 では kprobe hook が使えない（KernelSU-Next の Kconfig で 5.10 未満非推奨）ため、
CONFIG_KSU_MANUAL_HOOK 用の呼び出しを 5 ファイルに挿入する。

使い方: python3 apply_manual_hooks.py <kernel_dir>
  kernel_dir は Makefile / fs / kernel があるディレクトリ
"""
import sys
import os

PATCHES = [
    # (file, marker, old, new)
    (
        "fs/exec.c",
        "ksu_handle_execveat",
        """int do_execve(struct filename *filename,
	const char __user *const __user *__argv,
	const char __user *const __user *__envp)
{
	struct user_arg_ptr argv = { .ptr.native = __argv };
	struct user_arg_ptr envp = { .ptr.native = __envp };
	return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);
}""",
        """#ifdef CONFIG_KSU
__attribute__((hot))
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,
				void *argv, void *envp, int *flags);
#endif

int do_execve(struct filename *filename,
	const char __user *const __user *__argv,
	const char __user *const __user *__envp)
{
	struct user_arg_ptr argv = { .ptr.native = __argv };
	struct user_arg_ptr envp = { .ptr.native = __envp };
#ifdef CONFIG_KSU
	ksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);
#endif
	return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);
}""",
    ),
    (
        "fs/exec.c",
        "32-bit compat execve",  # 同じファイル内の 2 箇所目（マーカーは下で個別判定）
        """	struct user_arg_ptr envp = {
		.is_compat = true,
		.ptr.compat = __envp,
	};
	return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);""",
        """	struct user_arg_ptr envp = {
		.is_compat = true,
		.ptr.compat = __envp,
	};
#ifdef CONFIG_KSU
	ksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);
#endif
	return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);""",
    ),
    (
        "fs/open.c",
        "ksu_handle_faccessat",
        """SYSCALL_DEFINE3(faccessat, int, dfd, const char __user *, filename, int, mode)
{
	const struct cred *old_cred;
	struct cred *override_cred;
	struct path path;
	struct inode *inode;
	struct vfsmount *mnt;
	int res;
	unsigned int lookup_flags = LOOKUP_FOLLOW;

	if (mode & ~S_IRWXO)	/* where's F_OK, X_OK, W_OK, R_OK? */""",
        """#ifdef CONFIG_KSU
__attribute__((hot))
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,
				int *mode, int *flags);
#endif

SYSCALL_DEFINE3(faccessat, int, dfd, const char __user *, filename, int, mode)
{
	const struct cred *old_cred;
	struct cred *override_cred;
	struct path path;
	struct inode *inode;
	struct vfsmount *mnt;
	int res;
	unsigned int lookup_flags = LOOKUP_FOLLOW;

#ifdef CONFIG_KSU
	ksu_handle_faccessat(&dfd, &filename, &mode, NULL);
#endif

	if (mode & ~S_IRWXO)	/* where's F_OK, X_OK, W_OK, R_OK? */""",
    ),
    (
        "fs/read_write.c",
        "ksu_handle_sys_read",
        """SYSCALL_DEFINE3(read, unsigned int, fd, char __user *, buf, size_t, count)
{
	struct fd f = fdget_pos(fd);
	ssize_t ret = -EBADF;

	if (f.file) {""",
        """#ifdef CONFIG_KSU
extern void ksu_handle_sys_read(unsigned int fd);
#endif

SYSCALL_DEFINE3(read, unsigned int, fd, char __user *, buf, size_t, count)
{
	struct fd f = fdget_pos(fd);
	ssize_t ret = -EBADF;

#ifdef CONFIG_KSU
	ksu_handle_sys_read(fd);
#endif

	if (f.file) {""",
    ),
    (
        "fs/stat.c",
        "ksu_handle_stat",
        """#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)
SYSCALL_DEFINE4(newfstatat, int, dfd, const char __user *, filename,
		struct stat __user *, statbuf, int, flag)
{
	struct kstat stat;
	int error;

	error = vfs_fstatat(dfd, filename, &stat, flag);""",
        """#ifdef CONFIG_KSU
__attribute__((hot))
extern int ksu_handle_stat(int *dfd, const char __user **filename_user,
				int *flags);
#endif

#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)
SYSCALL_DEFINE4(newfstatat, int, dfd, const char __user *, filename,
		struct stat __user *, statbuf, int, flag)
{
	struct kstat stat;
	int error;

#ifdef CONFIG_KSU
	ksu_handle_stat(&dfd, &filename, &flag);
#endif

	error = vfs_fstatat(dfd, filename, &stat, flag);""",
    ),
    (
        "kernel/reboot.c",
        "ksu_handle_sys_reboot",
        """SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,
		void __user *, arg)
{
	struct pid_namespace *pid_ns = task_active_pid_ns(current);
	char buffer[256];
	int ret = 0;

	/* We only trust the superuser with rebooting the system. */""",
        """#ifdef CONFIG_KSU
extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd,
				 void __user **arg);
#endif

SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,
		void __user *, arg)
{
	struct pid_namespace *pid_ns = task_active_pid_ns(current);
	char buffer[256];
	int ret = 0;

#ifdef CONFIG_KSU
	ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);
#endif

	/* We only trust the superuser with rebooting the system. */""",
    ),
]


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    kdir = sys.argv[1]
    if not os.path.isfile(os.path.join(kdir, "Makefile")):
        print(f"ERROR: {kdir}/Makefile がありません")
        return 2

    for rel, marker, old, new in PATCHES:
        path = os.path.join(kdir, rel)
        if not os.path.isfile(path):
            print(f"ERROR: {rel} が見つかりません")
            return 1
        with open(path, "r", encoding="utf-8", errors="surrogateescape") as f:
            src = f.read()
        if new in src:
            print(f"[skip] {rel}: 既に適用済み")
            continue
        if marker in src and old not in src:
            # 呼び出しだけ入っている等の半端な状態
            print(f"[skip] {rel}: '{marker}' が既に存在（手動確認してください）")
            continue
        cnt = src.count(old)
        if cnt != 1:
            print(f"ERROR: {rel}: アンカーが {cnt} 箇所（1 箇所である必要があります）")
            return 1
        with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
            f.write(src.replace(old, new, 1))
        print(f"[ok] {rel}")

    print("manual hooks の挿入が完了しました")
    return 0


if __name__ == "__main__":
    sys.exit(main())
