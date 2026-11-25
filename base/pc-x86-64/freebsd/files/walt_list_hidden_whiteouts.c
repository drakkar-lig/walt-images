/*
 * find_whiteouts.c - Recursively walk a directory tree and print, one per
 * line, the relative path of every unionfs/tmpfs whiteout (DT_WHT) entry
 * found. Intended to complement a normal `tar` archive of the same tree:
 * tar silently drops whiteout entries (bsdtar/libarchive has no support
 * for them at all), so `walt node save` needs a side-channel manifest of
 * deleted names in order to reproduce deletions when updating the base
 * image.
 *
 * Build:   cc -o find_whiteouts find_whiteouts.c
 * Usage:   ./find_whiteouts <directory>
 *
 * NOTE: plain opendir(3) hides DT_WHT entries (DTF_HIDEW flag baked into
 * opendir(3)); we must use __opendir2(path, DTF_NODUP) to see them.
 */

#include <sys/types.h>
#include <limits.h>
#include <dirent.h>
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void
walk(const char *dirpath, const char *relpath, char sep)
{
	DIR *dirp;
	struct dirent *ent;
	char childpath[PATH_MAX];
	char childrel[PATH_MAX];

	dirp = __opendir2(dirpath, DTF_NODUP);
	if (dirp == NULL) {
		warn("__opendir2: %s", dirpath);
		return;
	}

	while ((ent = readdir(dirp)) != NULL) {
		if (strcmp(ent->d_name, ".") == 0 ||
		    strcmp(ent->d_name, "..") == 0)
			continue;

		snprintf(childrel, sizeof(childrel), "%s%s%s",
		    relpath, relpath[0] != '\0' ? "/" : "", ent->d_name);

		if (ent->d_type == DT_WHT) {
			printf("%s%c", childrel, sep);
			continue;
		}

		if (ent->d_type == DT_DIR) {
			snprintf(childpath, sizeof(childpath), "%s/%s",
			    dirpath, ent->d_name);
			walk(childpath, childrel, sep);
		}
	}

	closedir(dirp);
}

int
main(int argc, char **argv)
{
    char *progname, *dirname, sep='\n';

    progname = argv[0];
    argv++; argc--;

    if ((argc > 0) && (strcmp(argv[0], "-0") == 0)) {
        sep='\0';
        argv++; argc--;
    }

	if (argc != 1) {
		fprintf(stderr, "usage: %s [-0] <directory>\n", progname);
		return 1;
	}

    dirname = argv[0];

	walk(dirname, "", sep);

	return 0;
}
