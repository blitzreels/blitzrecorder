#pragma once

// WinRT ABI headers declare GetCurrentTime / GetCurrentDirectory as methods.
// windows.h macros otherwise explode MSVC (C4002).
#ifdef GetCurrentTime
#undef GetCurrentTime
#endif
#ifdef GetCurrentDirectory
#undef GetCurrentDirectory
#endif
#ifdef GetEnvironmentVariable
#undef GetEnvironmentVariable
#endif
#ifdef SendMessage
#undef SendMessage
#endif
#ifdef GetObject
#undef GetObject
#endif
