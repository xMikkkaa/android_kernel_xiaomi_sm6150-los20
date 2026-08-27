// SPDX-License-Identifier: GPL-2.0
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/utsname.h>

static int version_proc_show(struct seq_file *m, void *v)
{
	seq_printf(m, "Linux version 4.14.180-perf-gdacace7db6ff (builder@m1-xm-ota-bd217.bj.idc.xiaomi.com) (clang version 10.0.6 for Android NDK, GNU ld (binutils-2.27-bd24d23f) 2.27.0.20170315) #2 SMP PREEMPT Sat Sep 3 16:19:41 CST 2022\n");
	return 0;
}

static int version_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, version_proc_show, NULL);
}

static const struct file_operations version_proc_fops = {
	.open		= version_proc_open,
	.read		= seq_read,
	.llseek		= seq_lseek,
	.release	= single_release,
};

static int __init proc_version_init(void)
{
	proc_create("version", 0, NULL, &version_proc_fops);
	return 0;
}
fs_initcall(proc_version_init);
