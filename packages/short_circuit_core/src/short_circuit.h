#pragma once
#if defined(_WIN32)
#define SC_API __declspec(dllexport)
#else
#define SC_API __attribute__((visibility("default"))) __attribute__((used))
#endif
#ifdef __cplusplus
extern "C" {
#endif
/* Caller releases every sc_request response using sc_free. */
SC_API char* sc_request(const char* request_utf8);
SC_API void sc_free(char* response);
#ifdef __cplusplus
}
#endif

