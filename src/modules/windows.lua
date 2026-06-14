local M = ... or {}
local ffi = require("ffi")
local platform = require("platform")

ffi.cdef[[
typedef unsigned char BYTE;
typedef uint32_t UINT32;
typedef uint64_t UINT64;
typedef unsigned int UINT;
typedef unsigned long ULONG;
typedef long HRESULT;
typedef size_t SIZE_T;
typedef wchar_t WCHAR;
typedef WCHAR *LPWSTR;
typedef const WCHAR *LPCWSTR;
typedef char *LPSTR;
typedef const char *LPCSTR;
typedef void *LPVOID;
typedef const void *LPCVOID;
typedef int BOOL;
typedef unsigned long DWORD;
typedef void *HANDLE;
typedef HANDLE HMODULE;

typedef struct GUID {
   uint32_t Data1;
   uint16_t Data2;
   uint16_t Data3;
   uint8_t Data4[8];
} GUID;
typedef GUID CLSID;
typedef GUID IID;

typedef struct IUnknown IUnknown;
typedef struct IUnknownVtbl {
   HRESULT (*QueryInterface)(IUnknown *This, const IID *riid, void **ppvObject);
   ULONG (*AddRef)(IUnknown *This);
   ULONG (*Release)(IUnknown *This);
} IUnknownVtbl;
struct IUnknown {
   const IUnknownVtbl *lpVtbl;
};

typedef intptr_t (__stdcall *FARPROC)(void);

DWORD __stdcall GetLastError(void);
DWORD __stdcall FormatMessageA(
   DWORD dwFlags,
   LPCVOID lpSource,
   DWORD dwMessageId,
   DWORD dwLanguageId,
   LPSTR lpBuffer,
   DWORD nSize,
   void *Arguments
);
int __stdcall MultiByteToWideChar(
   UINT CodePage,
   DWORD dwFlags,
   LPCSTR lpMultiByteStr,
   int cbMultiByte,
   LPWSTR lpWideCharStr,
   int cchWideChar
);
HMODULE __stdcall GetModuleHandleW(LPCWSTR lpModuleName);
HMODULE __stdcall LoadLibraryW(LPCWSTR lpLibFileName);
FARPROC __stdcall GetProcAddress(HMODULE hModule, LPCSTR lpProcName);
BOOL __stdcall FreeLibrary(HMODULE hLibModule);
]]

M.CP_UTF8 = 65001
M.FORMAT_MESSAGE_IGNORE_INSERTS = 0x00000200
M.FORMAT_MESSAGE_FROM_SYSTEM = 0x00001000

if platform.is_windows() then
   local kernel32 = ffi.load("kernel32")

   M.GetLastError = kernel32.GetLastError
   M.FormatMessageA = kernel32.FormatMessageA
   M.MultiByteToWideChar = kernel32.MultiByteToWideChar
   M.GetModuleHandleW = kernel32.GetModuleHandleW
   M.LoadLibraryW = kernel32.LoadLibraryW
   M.GetProcAddress = kernel32.GetProcAddress
   M.FreeLibrary = kernel32.FreeLibrary
end

return M
