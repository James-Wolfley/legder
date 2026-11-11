/*
 * OS calls for Legder.File_Device that System.OS_Lib does not provide:
 * a sync that reaches stable storage, an exclusive lock, and a
 * directory sync so a newly created file survives power loss.
 *
 * Linux and other POSIX: fsync, flock, fsync on the directory.
 * macOS: F_FULLFSYNC, because plain fsync there only hands the data to
 *        the drive, whose cache may still lose it.
 * Windows: _commit and LockFileEx; directory entries need no sync.
 */

#include <errno.h>

#ifdef _WIN32
#include <io.h>
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>
#endif

/* 0 when every earlier write to fd is on stable storage. */
int legder_fd_sync(int fd)
{
#if defined(_WIN32)
    return _commit(fd) == 0 ? 0 : -1;
#else
    int r;
#if defined(__APPLE__) && defined(F_FULLFSYNC)
    if (fcntl(fd, F_FULLFSYNC) == 0)
        return 0;
    /* Some file systems (network, FAT) refuse F_FULLFSYNC: fall back. */
#endif
    do {
        r = fsync(fd);
    } while (r == -1 && errno == EINTR);
    return r == 0 ? 0 : -1;
#endif
}

/* 0 locked, 1 already locked elsewhere, -1 error. Never blocks. */
int legder_fd_lock(int fd)
{
#if defined(_WIN32)
    HANDLE h = (HANDLE)_get_osfhandle(fd);
    OVERLAPPED ov = {0};
    if (h == INVALID_HANDLE_VALUE)
        return -1;
    if (LockFileEx(h, LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY,
                   0, MAXDWORD, MAXDWORD, &ov))
        return 0;
    return GetLastError() == ERROR_LOCK_VIOLATION ? 1 : -1;
#else
    int r;
    do {
        r = flock(fd, LOCK_EX | LOCK_NB);
    } while (r == -1 && errno == EINTR);
    if (r == 0)
        return 0;
    return errno == EWOULDBLOCK ? 1 : -1;
#endif
}

/* 0 when the entries of directory path are durable. */
int legder_dir_sync(const char *path)
{
#if defined(_WIN32)
    (void)path;
    return 0;
#else
    int fd, r;
    fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    do {
        r = fsync(fd);
    } while (r == -1 && errno == EINTR);
    close(fd);
    /* Some file systems cannot fsync a directory; that is not a loss. */
    return (r == 0 || errno == EINVAL || errno == ENOTSUP) ? 0 : -1;
#endif
}
