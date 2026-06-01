module Elm.Review.Testable.FsData exposing
    ( FsError(..), errorToString
    , Errno(..), errorFromCodeAndPath
    , FileStat
    , MatchKind(..)
    , Entry
    )

{-|

@docs FsError, errorToString
@docs Errno, errorFromCodeAndPath

@docs FileStat

@docs MatchKind

-}

import ElmReview.Path exposing (Path)


type FsError
    = FsError Errno Path


type Errno
    = EPERM
    | ENOENT
    | ESRCH
    | EINTR
    | EIO
    | ENXIO
    | E2BIG
    | ENOEXEC
    | EBADF
    | ECHILD
    | EDEADLK
    | ENOMEM
    | EACCES
    | EFAULT
    | ENOTBLK
    | EBUSY
    | EEXIST
    | EXDEV
    | ENODEV
    | ENOTDIR
    | EISDIR
    | EINVAL
    | ENFILE
    | EMFILE
    | ENOTTY
    | ETXTBSY
    | EFBIG
    | ENOSPC
    | ESPIPE
    | EROFS
    | EMLINK
    | EPIPE
    | EDOM
    | ERANGE
    | EAGAIN
    | EINPROGRESS
    | EALREADY
    | ENOTSOCK
    | EDESTADDRREQ
    | EMSGSIZE
    | EPROTOTYPE
    | ENOPROTOOPT
    | EPROTONOSUPPORT
    | ESOCKTNOSUPPORT
    | ENOTSUP
    | EPFNOSUPPORT
    | EAFNOSUPPORT
    | EADDRINUSE
    | EADDRNOTAVAIL
    | ENETDOWN
    | ENETUNREACH
    | ENETRESET
    | ECONNABORTED
    | ECONNRESET
    | ENOBUFS
    | EISCONN
    | ENOTCONN
    | ESHUTDOWN
    | ETOOMANYREFS
    | ETIMEDOUT
    | ECONNREFUSED
    | ELOOP
    | ENAMETOOLONG
    | EHOSTDOWN
    | EHOSTUNREACH
    | ENOTEMPTY
    | EPROCLIM
    | EUSERS
    | EDQUOT
    | ESTALE
    | EREMOTE
    | EBADRPC
    | ERPCMISMATCH
    | EPROGUNAVAIL
    | EPROGMISMATCH
    | EPROCUNAVAIL
    | ENOLCK
    | ENOSYS
    | EFTYPE
    | EAUTH
    | ENEEDAUTH
    | EPWROFF
    | EDEVERR
    | EOVERFLOW
    | EBADEXEC
    | EBADARCH
    | ESHLIBVERS
    | EBADMACHO
    | ECANCELED
    | EIDRM
    | ENOMSG
    | EILSEQ
    | ENOATTR
    | EBADMSG
    | EMULTIHOP
    | ENODATA
    | ENOLINK
    | ENOSR
    | ENOSTR
    | EPROTO
    | ETIME
    | EOPNOTSUPP
    | ENOPOLICY
    | ENOTRECOVERABLE
    | EOWNERDEAD
    | EQFULL
    | Unknown Int


errorFromCodeAndPath : Int -> Path -> FsError
errorFromCodeAndPath code path =
    FsError (fromInt code) path


{-| Convert a raw errno integer to an `Errno` value.

    fromInt 2 == ENOENT

    fromInt 13 == EACCES

    fromInt 9999 == Unknown 9999

-}
fromInt : Int -> Errno
fromInt code =
    case code of
        1 ->
            EPERM

        2 ->
            ENOENT

        3 ->
            ESRCH

        4 ->
            EINTR

        5 ->
            EIO

        6 ->
            ENXIO

        7 ->
            E2BIG

        8 ->
            ENOEXEC

        9 ->
            EBADF

        10 ->
            ECHILD

        11 ->
            EDEADLK

        12 ->
            ENOMEM

        13 ->
            EACCES

        14 ->
            EFAULT

        15 ->
            ENOTBLK

        16 ->
            EBUSY

        17 ->
            EEXIST

        18 ->
            EXDEV

        19 ->
            ENODEV

        20 ->
            ENOTDIR

        21 ->
            EISDIR

        22 ->
            EINVAL

        23 ->
            ENFILE

        24 ->
            EMFILE

        25 ->
            ENOTTY

        26 ->
            ETXTBSY

        27 ->
            EFBIG

        28 ->
            ENOSPC

        29 ->
            ESPIPE

        30 ->
            EROFS

        31 ->
            EMLINK

        32 ->
            EPIPE

        33 ->
            EDOM

        34 ->
            ERANGE

        35 ->
            EAGAIN

        36 ->
            EINPROGRESS

        37 ->
            EALREADY

        38 ->
            ENOTSOCK

        39 ->
            EDESTADDRREQ

        40 ->
            EMSGSIZE

        41 ->
            EPROTOTYPE

        42 ->
            ENOPROTOOPT

        43 ->
            EPROTONOSUPPORT

        44 ->
            ESOCKTNOSUPPORT

        45 ->
            ENOTSUP

        46 ->
            EPFNOSUPPORT

        47 ->
            EAFNOSUPPORT

        48 ->
            EADDRINUSE

        49 ->
            EADDRNOTAVAIL

        50 ->
            ENETDOWN

        51 ->
            ENETUNREACH

        52 ->
            ENETRESET

        53 ->
            ECONNABORTED

        54 ->
            ECONNRESET

        55 ->
            ENOBUFS

        56 ->
            EISCONN

        57 ->
            ENOTCONN

        58 ->
            ESHUTDOWN

        59 ->
            ETOOMANYREFS

        60 ->
            ETIMEDOUT

        61 ->
            ECONNREFUSED

        62 ->
            ELOOP

        63 ->
            ENAMETOOLONG

        64 ->
            EHOSTDOWN

        65 ->
            EHOSTUNREACH

        66 ->
            ENOTEMPTY

        67 ->
            EPROCLIM

        68 ->
            EUSERS

        69 ->
            EDQUOT

        70 ->
            ESTALE

        71 ->
            EREMOTE

        72 ->
            EBADRPC

        73 ->
            ERPCMISMATCH

        74 ->
            EPROGUNAVAIL

        75 ->
            EPROGMISMATCH

        76 ->
            EPROCUNAVAIL

        77 ->
            ENOLCK

        78 ->
            ENOSYS

        79 ->
            EFTYPE

        80 ->
            EAUTH

        81 ->
            ENEEDAUTH

        82 ->
            EPWROFF

        83 ->
            EDEVERR

        84 ->
            EOVERFLOW

        85 ->
            EBADEXEC

        86 ->
            EBADARCH

        87 ->
            ESHLIBVERS

        88 ->
            EBADMACHO

        89 ->
            ECANCELED

        90 ->
            EIDRM

        91 ->
            ENOMSG

        92 ->
            EILSEQ

        93 ->
            ENOATTR

        94 ->
            EBADMSG

        95 ->
            EMULTIHOP

        96 ->
            ENODATA

        97 ->
            ENOLINK

        98 ->
            ENOSR

        99 ->
            ENOSTR

        100 ->
            EPROTO

        101 ->
            ETIME

        102 ->
            EOPNOTSUPP

        103 ->
            ENOPOLICY

        104 ->
            ENOTRECOVERABLE

        105 ->
            EOWNERDEAD

        106 ->
            EQFULL

        _ ->
            Unknown code


errorToString : FsError -> String
errorToString (FsError errno path) =
    toMessage errno ++ ": " ++ path


{-| Human-readable English description of an errno code.

    errorToString ENOENT == "No such file or directory"

    errorToString EACCES == "Permission denied"

    errorToString (Unknown 9999) == "Unknown error 9999"

-}
toMessage : Errno -> String
toMessage errno =
    case errno of
        EPERM ->
            "Operation not permitted"

        ENOENT ->
            "No such file or directory"

        ESRCH ->
            "No such process"

        EINTR ->
            "Interrupted system call"

        EIO ->
            "Input/output error"

        ENXIO ->
            "Device not configured"

        E2BIG ->
            "Argument list too long"

        ENOEXEC ->
            "Exec format error"

        EBADF ->
            "Bad file descriptor"

        ECHILD ->
            "No child processes"

        EDEADLK ->
            "Resource deadlock avoided"

        ENOMEM ->
            "Cannot allocate memory"

        EACCES ->
            "Permission denied"

        EFAULT ->
            "Bad address"

        ENOTBLK ->
            "Block device required"

        EBUSY ->
            "Resource busy"

        EEXIST ->
            "File exists"

        EXDEV ->
            "Cross-device link"

        ENODEV ->
            "Operation not supported by device"

        ENOTDIR ->
            "Not a directory"

        EISDIR ->
            "Is a directory"

        EINVAL ->
            "Invalid argument"

        ENFILE ->
            "Too many open files in system"

        EMFILE ->
            "Too many open files"

        ENOTTY ->
            "Inappropriate ioctl for device"

        ETXTBSY ->
            "Text file busy"

        EFBIG ->
            "File too large"

        ENOSPC ->
            "No space left on device"

        ESPIPE ->
            "Illegal seek"

        EROFS ->
            "Read-only file system"

        EMLINK ->
            "Too many links"

        EPIPE ->
            "Broken pipe"

        EDOM ->
            "Numerical argument out of domain"

        ERANGE ->
            "Result too large"

        EAGAIN ->
            "Resource temporarily unavailable"

        EINPROGRESS ->
            "Operation now in progress"

        EALREADY ->
            "Operation already in progress"

        ENOTSOCK ->
            "Socket operation on non-socket"

        EDESTADDRREQ ->
            "Destination address required"

        EMSGSIZE ->
            "Message too long"

        EPROTOTYPE ->
            "Protocol wrong type for socket"

        ENOPROTOOPT ->
            "Protocol not available"

        EPROTONOSUPPORT ->
            "Protocol not supported"

        ESOCKTNOSUPPORT ->
            "Socket type not supported"

        ENOTSUP ->
            "Operation not supported"

        EPFNOSUPPORT ->
            "Protocol family not supported"

        EAFNOSUPPORT ->
            "Address family not supported by protocol family"

        EADDRINUSE ->
            "Address already in use"

        EADDRNOTAVAIL ->
            "Can't assign requested address"

        ENETDOWN ->
            "Network is down"

        ENETUNREACH ->
            "Network is unreachable"

        ENETRESET ->
            "Network dropped connection on reset"

        ECONNABORTED ->
            "Software caused connection abort"

        ECONNRESET ->
            "Connection reset by peer"

        ENOBUFS ->
            "No buffer space available"

        EISCONN ->
            "Socket is already connected"

        ENOTCONN ->
            "Socket is not connected"

        ESHUTDOWN ->
            "Can't send after socket shutdown"

        ETOOMANYREFS ->
            "Too many references: can't splice"

        ETIMEDOUT ->
            "Operation timed out"

        ECONNREFUSED ->
            "Connection refused"

        ELOOP ->
            "Too many levels of symbolic links"

        ENAMETOOLONG ->
            "File name too long"

        EHOSTDOWN ->
            "Host is down"

        EHOSTUNREACH ->
            "No route to host"

        ENOTEMPTY ->
            "Directory not empty"

        EPROCLIM ->
            "Too many processes"

        EUSERS ->
            "Too many users"

        EDQUOT ->
            "Disc quota exceeded"

        ESTALE ->
            "Stale NFS file handle"

        EREMOTE ->
            "Too many levels of remote in path"

        EBADRPC ->
            "RPC struct is bad"

        ERPCMISMATCH ->
            "RPC version wrong"

        EPROGUNAVAIL ->
            "RPC prog. not avail"

        EPROGMISMATCH ->
            "Program version wrong"

        EPROCUNAVAIL ->
            "Bad procedure for program"

        ENOLCK ->
            "No locks available"

        ENOSYS ->
            "Function not implemented"

        EFTYPE ->
            "Inappropriate file type or format"

        EAUTH ->
            "Authentication error"

        ENEEDAUTH ->
            "Need authenticator"

        EPWROFF ->
            "Device power is off"

        EDEVERR ->
            "Device error"

        EOVERFLOW ->
            "Value too large to be stored in data type"

        EBADEXEC ->
            "Bad executable (or shared library)"

        EBADARCH ->
            "Bad CPU type in executable"

        ESHLIBVERS ->
            "Shared library version mismatch"

        EBADMACHO ->
            "Malformed Mach-o file"

        ECANCELED ->
            "Operation canceled"

        EIDRM ->
            "Identifier removed"

        ENOMSG ->
            "No message of desired type"

        EILSEQ ->
            "Illegal byte sequence"

        ENOATTR ->
            "Attribute not found"

        EBADMSG ->
            "Bad message"

        EMULTIHOP ->
            "Reserved (EMULTIHOP)"

        ENODATA ->
            "No message available on STREAM"

        ENOLINK ->
            "Reserved (ENOLINK)"

        ENOSR ->
            "No STREAM resources"

        ENOSTR ->
            "Not a STREAM"

        EPROTO ->
            "Protocol error"

        ETIME ->
            "STREAM ioctl timeout"

        EOPNOTSUPP ->
            "Operation not supported on socket"

        ENOPOLICY ->
            "Policy not found"

        ENOTRECOVERABLE ->
            "State not recoverable"

        EOWNERDEAD ->
            "Previous owner died"

        EQFULL ->
            "Interface output queue is full"

        Unknown code ->
            "Unknown error " ++ String.fromInt code


{-| File metadata returned by stat.
-}
type alias FileStat =
    { isFile : Bool
    , isDirectory : Bool
    , isSymlink : Bool
    , size : Int
    , modifiedTime : Int
    }


{-| A filesystem entry with full metadata.

Returned by `list` and `Fs.Walk` functions. Carries everything
the OS gives us in one shot — no separate `stat` call needed.

  - `relativePath` — relative to the walk root (e.g. `"src/Foo/Bar.elm"`)
  - `location` — typed file or directory location for follow-up I/O
  - `name` — basename only (e.g. `"Bar.elm"`)
  - `depth` — 0 = direct child of walk root

-}
type alias Entry =
    { relativePath : Path
    , name : String
    , path : Path
    , isDirectory : Bool
    , isFile : Bool
    , isSymlink : Bool
    , size : Int
    , modifiedTime : Int
    , depth : Int
    }


{-| The kind of file system entry to match during the tree traversal.
-}
type MatchKind
    = Any
    | File
    | Directory
