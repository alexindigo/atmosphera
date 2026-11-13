#pragma once
#include <cstddef>

// Single GUI producer. Sink0=dispatcher,1=optional scopes,2=optional diagnostics.
// All file operations and final conservation receipts belong to the worker.
void settingsGuiLogAppend(int sink, const char *data, size_t bytes);
