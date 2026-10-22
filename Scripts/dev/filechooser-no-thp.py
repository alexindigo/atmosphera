#!/usr/bin/env python3
"""F11-validated process-only THP policy, inherited by the exec target."""
import ctypes
import os
import sys

PR_SET_THP_DISABLE = 41
PR_GET_THP_DISABLE = 42
control = ctypes.CDLL(None, use_errno=True).prctl
control.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong]
control.restype = ctypes.c_int
if control(PR_SET_THP_DISABLE, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_THP_DISABLE")
assert control(PR_GET_THP_DISABLE, 0, 0, 0, 0) == 1
os.execvp(sys.argv[1], sys.argv[1:])
