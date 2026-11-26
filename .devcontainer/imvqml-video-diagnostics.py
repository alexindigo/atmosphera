"""Instrument only the pinned, extracted ImvQml source for hosted diagnostics."""
from pathlib import Path
import sys

source = Path(sys.argv[1]) / 'src/video-decode.cpp'
text = source.read_text()


def insert(before, code):
    global text
    if text.count(before) != 1:
        raise ValueError(f'ImvQml diagnostic anchor changed: {before}')
    text = text.replace(before, code + before)


insert('#include <unistd.h>', '#include <cstdio>\n#include <cstring>\n#include <sys/resource.h>\n#include <sys/stat.h>\n')
insert('bool load(const MpvApi', '''QByteArray diagnosticPath(const char *suffix) {
    auto root = qgetenv("IMV_VIDEO_DIAGNOSTICS");
    if (root.isEmpty())
        return {};
    return root + "/helper-" + QByteArray::number(::getpid()) + suffix;
}

void diagnosticMemory(FILE *trace) {
    if (auto *status = std::fopen("/proc/self/status", "r")) {
        char line[256];
        while (std::fgets(line, sizeof(line), status)) {
            if (!std::strncmp(line, "VmPeak:", 7) || !std::strncmp(line, "VmSize:", 7) ||
                !std::strncmp(line, "VmRSS:", 6) || !std::strncmp(line, "Threads:", 8))
                std::fputs(line, trace);
        }
        std::fclose(status);
    }
}

''')
insert('    const auto fdName', '''    const auto path = diagnosticPath(".native.log");
    const auto closeTrace = [](FILE *file) { std::fclose(file); };
    const std::unique_ptr<FILE, decltype(closeTrace)> trace(
        path.isEmpty() ? nullptr : std::fopen(path.constData(), "a"), closeTrace);
    if (trace) {
        std::setvbuf(trace.get(), nullptr, _IOLBF, 0);
        struct stat info{};
        struct rlimit budget{};
        const int statResult = ::fstat(input, &info);
        const int limitResult = ::getrlimit(RLIMIT_AS, &budget);
        std::fprintf(trace.get(), "fd=%d stat=%d bytes=%lld blocks=%lld offset=%lld as=%d/%llu position=%g\\n",
                     input, statResult, (long long)info.st_size, (long long)info.st_blocks,
                     (long long)::lseek(input, 0, SEEK_CUR), limitResult,
                     (unsigned long long)budget.rlim_cur, fraction);
        diagnosticMemory(trace.get());
    }
''')
old = '        if (!events.accept(*api.wait_event(mpv, 0.01)))'
insert(old, '''        const auto &event = *api.wait_event(mpv, 0.01);
        if (trace && event.event_id != MPV_EVENT_NONE) {
            std::fprintf(trace.get(), "transaction=%llu event=%d reply=%llu error=%d\\n",
                         (unsigned long long)events.token, int(event.event_id),
                         (unsigned long long)event.reply_userdata, event.error);
            if (event.event_id == MPV_EVENT_END_FILE && event.data) {
                const auto &end = *static_cast<mpv_event_end_file *>(event.data);
                std::fprintf(trace.get(), "end reason=%d error=%d\\n", int(end.reason), end.error);
            }
            if (event.event_id == MPV_EVENT_END_FILE || event.event_id == MPV_EVENT_FILE_LOADED ||
                event.event_id == MPV_EVENT_PLAYBACK_RESTART)
                diagnosticMemory(trace.get());
        }
''')
text = text.replace(old, '        if (!events.accept(event))')
insert('    if (api.initialize(core.get()) < 0)', '''    const auto log = diagnosticPath(".libmpv.log");
    if (!log.isEmpty()) {
        api.set_option_string(core.get(), "log-file", log.constData());
        api.set_option_string(core.get(), "msg-level", "all=trace");
    }
''')
source.write_text(text)
