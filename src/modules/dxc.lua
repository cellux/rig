local M = ... or {}
local ffi = require("ffi")
local schema = require("schema")

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
typedef void *LPVOID;
typedef const void *LPCVOID;
typedef const char *LPCSTR;
typedef int BOOL;

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

typedef struct IDxcBlob IDxcBlob;
typedef struct IDxcBlobVtbl {
   HRESULT (*QueryInterface)(IDxcBlob *This, const IID *riid, void **ppvObject);
   ULONG (*AddRef)(IDxcBlob *This);
   ULONG (*Release)(IDxcBlob *This);
   void *(*GetBufferPointer)(IDxcBlob *This);
   size_t (*GetBufferSize)(IDxcBlob *This);
} IDxcBlobVtbl;
struct IDxcBlob {
   const IDxcBlobVtbl *lpVtbl;
};

typedef struct IDxcBlobEncoding IDxcBlobEncoding;
typedef struct IDxcBlobEncodingVtbl {
   HRESULT (*QueryInterface)(IDxcBlobEncoding *This, const IID *riid, void **ppvObject);
   ULONG (*AddRef)(IDxcBlobEncoding *This);
   ULONG (*Release)(IDxcBlobEncoding *This);
   void *(*GetBufferPointer)(IDxcBlobEncoding *This);
   size_t (*GetBufferSize)(IDxcBlobEncoding *This);
   HRESULT (*GetEncoding)(IDxcBlobEncoding *This, BOOL *pKnown, UINT32 *pCodePage);
} IDxcBlobEncodingVtbl;
struct IDxcBlobEncoding {
   const IDxcBlobEncodingVtbl *lpVtbl;
};

typedef struct IDxcBlobUtf8 IDxcBlobUtf8;
typedef struct IDxcBlobUtf8Vtbl {
   HRESULT (*QueryInterface)(IDxcBlobUtf8 *This, const IID *riid, void **ppvObject);
   ULONG (*AddRef)(IDxcBlobUtf8 *This);
   ULONG (*Release)(IDxcBlobUtf8 *This);
   void *(*GetBufferPointer)(IDxcBlobUtf8 *This);
   size_t (*GetBufferSize)(IDxcBlobUtf8 *This);
   HRESULT (*GetEncoding)(IDxcBlobUtf8 *This, BOOL *pKnown, UINT32 *pCodePage);
   const char *(*GetStringPointer)(IDxcBlobUtf8 *This);
   size_t (*GetStringLength)(IDxcBlobUtf8 *This);
} IDxcBlobUtf8Vtbl;
struct IDxcBlobUtf8 {
   const IDxcBlobUtf8Vtbl *lpVtbl;
};

typedef struct DxcBuffer {
   const void *Ptr;
   size_t Size;
   UINT Encoding;
} DxcBuffer;

typedef enum DXC_OUT_KIND {
   DXC_OUT_NONE = 0,
   DXC_OUT_OBJECT = 1,
   DXC_OUT_ERRORS = 2,
   DXC_OUT_PDB = 3,
   DXC_OUT_SHADER_HASH = 4,
   DXC_OUT_DISASSEMBLY = 5,
   DXC_OUT_HLSL = 6,
   DXC_OUT_TEXT = 7,
   DXC_OUT_REFLECTION = 8,
   DXC_OUT_ROOT_SIGNATURE = 9,
   DXC_OUT_EXTRA_OUTPUTS = 10,
   DXC_OUT_REMARKS = 11,
   DXC_OUT_TIME_REPORT = 12,
   DXC_OUT_TIME_TRACE = 13
} DXC_OUT_KIND;

typedef struct IDxcOperationResult IDxcOperationResult;
typedef struct IDxcOperationResultVtbl {
   HRESULT (*QueryInterface)(IDxcOperationResult *This, const IID *riid, void **ppvObject);
   ULONG (*AddRef)(IDxcOperationResult *This);
   ULONG (*Release)(IDxcOperationResult *This);
   HRESULT (*GetStatus)(IDxcOperationResult *This, HRESULT *pStatus);
   HRESULT (*GetResult)(IDxcOperationResult *This, IDxcBlob **ppResult);
   HRESULT (*GetErrorBuffer)(IDxcOperationResult *This, IDxcBlobEncoding **ppErrors);
} IDxcOperationResultVtbl;
struct IDxcOperationResult {
   const IDxcOperationResultVtbl *lpVtbl;
};

typedef struct IDxcResult IDxcResult;
typedef struct IDxcResultVtbl {
   HRESULT (*QueryInterface)(IDxcResult *This, const IID *riid, void **ppvObject);
   ULONG (*AddRef)(IDxcResult *This);
   ULONG (*Release)(IDxcResult *This);
   HRESULT (*GetStatus)(IDxcResult *This, HRESULT *pStatus);
   HRESULT (*GetResult)(IDxcResult *This, IDxcBlob **ppResult);
   HRESULT (*GetErrorBuffer)(IDxcResult *This, IDxcBlobEncoding **ppErrors);
   BOOL (*HasOutput)(IDxcResult *This, DXC_OUT_KIND dxcOutKind);
   HRESULT (*GetOutput)(
      IDxcResult *This,
      DXC_OUT_KIND dxcOutKind,
      const IID *iid,
      void **ppvObject,
      void **ppOutputName
   );
   UINT32 (*GetNumOutputs)(IDxcResult *This);
   DXC_OUT_KIND (*GetOutputByIndex)(IDxcResult *This, UINT32 Index);
   DXC_OUT_KIND (*PrimaryOutput)(IDxcResult *This);
} IDxcResultVtbl;
struct IDxcResult {
   const IDxcResultVtbl *lpVtbl;
};

typedef struct IDxcCompiler3 IDxcCompiler3;
typedef struct IDxcCompiler3Vtbl {
   HRESULT (*QueryInterface)(IDxcCompiler3 *This, const IID *riid, void **ppvObject);
   ULONG (*AddRef)(IDxcCompiler3 *This);
   ULONG (*Release)(IDxcCompiler3 *This);
   HRESULT (*Compile)(
      IDxcCompiler3 *This,
      const DxcBuffer *pSource,
      const wchar_t **pArguments,
      UINT32 argCount,
      void *pIncludeHandler,
      const IID *riid,
      void **ppResult
   );
   HRESULT (*Disassemble)(
      IDxcCompiler3 *This,
      const DxcBuffer *pObject,
      const IID *riid,
      void **ppResult
   );
} IDxcCompiler3Vtbl;
struct IDxcCompiler3 {
   const IDxcCompiler3Vtbl *lpVtbl;
};

HRESULT DxcCreateInstance(const CLSID *rclsid, const IID *riid, void **ppv);
]]

local DXC_CP_UTF8 = 65001
local DXC_OUT_OBJECT = 1
local DXC_OUT_ERRORS = 2

M.SHADERSTAGE_VERTEX = "vertex"
M.SHADERSTAGE_FRAGMENT = "fragment"
M.SHADERSTAGE_COMPUTE = "compute"

local dxc_compile_options_schema = schema.record({
   source = schema.string(),
   stage = schema.enum({
      M.SHADERSTAGE_VERTEX,
      M.SHADERSTAGE_FRAGMENT,
      M.SHADERSTAGE_COMPUTE,
   }):optional(M.SHADERSTAGE_VERTEX),
   entrypoint = schema.string():optional(),
   source_name = schema.string():optional(),
   extra_args = schema.array(schema.string()):optional(),
   preserve_bindings = schema.boolean():optional(),
   preserve_interface = schema.boolean():optional(),
})

local dxc_state = {
   library = nil,
   error = nil,
}

local IID_IDxcCompiler3 = ffi.new("IID", {
   0x228B4687,
   0x5A6A,
   0x4730,
   { 0x90, 0x0C, 0x97, 0x02, 0xB2, 0x20, 0x3F, 0x54 },
})

local IID_IDxcResult = ffi.new("IID", {
   0x58346CDA,
   0xDDE7,
   0x4497,
   { 0x94, 0x61, 0x6F, 0x87, 0xAF, 0x5E, 0x06, 0x59 },
})

local IID_IDxcBlob = ffi.new("IID", {
   0x8BA5FB08,
   0x5195,
   0x40E2,
   { 0xAC, 0x58, 0x0D, 0x98, 0x9C, 0x3A, 0x01, 0x02 },
})

local IID_IDxcBlobUtf8 = ffi.new("IID", {
   0x3DA636C9,
   0xBA71,
   0x4024,
   { 0xA3, 0x01, 0x30, 0xCB, 0xF1, 0x25, 0x30, 0x5B },
})

local CLSID_DxcCompiler = ffi.new("CLSID", {
   0x73E22D93,
   0xE6CE,
   0x47F3,
   { 0xB5, 0xBF, 0xF0, 0x66, 0x4F, 0x39, 0xC1, 0xB0 },
})

local function failed(hr)
   return tonumber(hr) < 0
end

local function hresult_hex(hr)
   local value = tonumber(ffi.cast("uint32_t", hr))
   return string.format("0x%08X", value)
end

local function release_com(obj)
   if obj ~= nil and obj ~= ffi.NULL then
      obj.lpVtbl.Release(obj)
   end
end

local function load_dxc_library()
   if dxc_state.library ~= nil then
      return dxc_state.library
   end
   if dxc_state.error ~= nil then
      error(dxc_state.error)
   end

   local candidates = {
      "dxcompiler",
      "libdxcompiler.so",
      "libdxcompiler.dylib",
      "dxcompiler.dll",
   }
   local failures = {}

   for _, name in ipairs(candidates) do
      local ok, lib = pcall(ffi.load, name)
      if ok then
         dxc_state.library = lib
         return lib
      end
      table.insert(failures, tostring(lib))
   end

   dxc_state.error = "failed to load dxcompiler library: "
      .. table.concat(failures, "; ")
   error(dxc_state.error)
end

local function ascii_wide(text, field_name)
   if type(text) ~= "string" then
      error(field_name .. " must be a string")
   end

   local length = #text
   local wide = ffi.new("wchar_t[?]", length + 1)
   for i = 1, length do
      local byte = text:byte(i)
      if byte > 0x7F then
         error(field_name .. " must currently be ASCII-only")
      end
      wide[i - 1] = byte
   end
   wide[length] = 0
   return wide
end

local function build_stage_target(stage)
   if stage == "vertex" then
      return "vs_6_0"
   elseif stage == "fragment" or stage == "pixel" then
      return "ps_6_0"
   elseif stage == "compute" then
      return "cs_6_0"
   end
   error("stage must be 'vertex', 'fragment', or 'compute'")
end

local function collect_messages(result)
   if result == nil or result == ffi.NULL then
      return nil
   end

   local error_blob_out = ffi.new("void *[1]")
   local hr = result.lpVtbl.GetOutput(
      result,
      DXC_OUT_ERRORS,
      IID_IDxcBlobUtf8,
      error_blob_out,
      nil
   )

   if failed(hr) or error_blob_out[0] == nil then
      return nil
   end

   local error_blob = ffi.cast("IDxcBlobUtf8 *", error_blob_out[0])
   local text = nil
   local ptr = error_blob.lpVtbl.GetStringPointer(error_blob)
   local len = tonumber(error_blob.lpVtbl.GetStringLength(error_blob))
   if ptr ~= nil and len ~= nil and len > 0 then
      text = ffi.string(ptr, len)
   end
   release_com(error_blob)
   return text
end

local function blob_to_string(blob)
   local ptr = blob.lpVtbl.GetBufferPointer(blob)
   local len = tonumber(blob.lpVtbl.GetBufferSize(blob))
   if ptr == nil or len == nil then
      return ""
   end
   return ffi.string(ptr, len)
end

local function has_error_message(messages)
   return type(messages) == "string"
      and messages:find("error:", 1, true) ~= nil
end

function M.compile_spirv(options)
   local normalized = schema.assert(
      dxc_compile_options_schema,
      options,
      "dxc.compile_spirv options"
   )

   local lib = load_dxc_library()
   local compiler_out = ffi.new("void *[1]")
   local hr = lib.DxcCreateInstance(CLSID_DxcCompiler, IID_IDxcCompiler3, compiler_out)
   if failed(hr) or compiler_out[0] == nil then
      return nil, ("DxcCreateInstance(IDxcCompiler3) failed: %s"):format(
         hresult_hex(hr)
      )
   end

   local compiler = ffi.cast("IDxcCompiler3 *", compiler_out[0])
   local stage = normalized.stage
   local entrypoint = normalized.entrypoint or "main"
   local target = build_stage_target(stage)

   local source_name = normalized.source_name or "shader.hlsl"
   local wide_args = {
      ascii_wide(source_name, "source_name"),
      ascii_wide("-spirv", "internal argument"),
      ascii_wide("-E", "internal argument"),
      ascii_wide(entrypoint, "entrypoint"),
      ascii_wide("-T", "internal argument"),
      ascii_wide(target, "target profile"),
   }

   if normalized.preserve_bindings ~= false then
      table.insert(wide_args, ascii_wide("-fspv-preserve-bindings", "internal argument"))
   end
   if normalized.preserve_interface ~= false then
      table.insert(wide_args, ascii_wide("-fspv-preserve-interface", "internal argument"))
   end

   if type(normalized.extra_args) == "table" then
      for i, arg in ipairs(normalized.extra_args) do
         table.insert(wide_args, ascii_wide(arg, ("extra_args[%d]"):format(i)))
      end
   end

   local arg_array = ffi.new("const wchar_t *[?]", #wide_args)
   for i, arg in ipairs(wide_args) do
      arg_array[i - 1] = arg
   end

   local source_buffer = ffi.new("char[?]", #normalized.source + 1)
   ffi.copy(source_buffer, normalized.source, #normalized.source)
   source_buffer[#normalized.source] = 0

   local source = ffi.new("DxcBuffer[1]")
   source[0].Ptr = source_buffer
   source[0].Size = #normalized.source
   source[0].Encoding = DXC_CP_UTF8

   local result_out = ffi.new("void *[1]")
   hr = compiler.lpVtbl.Compile(
      compiler,
      source,
      arg_array,
      #wide_args,
      nil,
      IID_IDxcResult,
      result_out
   )

   if failed(hr) or result_out[0] == nil then
      release_com(compiler)
      return nil, ("IDxcCompiler3::Compile failed: %s"):format(hresult_hex(hr))
   end

   local result = ffi.cast("IDxcResult *", result_out[0])
   local status_out = ffi.new("HRESULT[1]")
   hr = result.lpVtbl.GetStatus(result, status_out)
   local messages = collect_messages(result)

   if failed(hr) or failed(status_out[0]) then
      local err = messages
      if err == nil or err == "" then
         err = ("DXC compilation failed: %s"):format(hresult_hex(status_out[0]))
      end
      release_com(result)
      release_com(compiler)
      return nil, err
   end

   local object_out = ffi.new("void *[1]")
   hr = result.lpVtbl.GetOutput(
      result,
      DXC_OUT_OBJECT,
      IID_IDxcBlob,
      object_out,
      nil
   )
   if failed(hr) or object_out[0] == nil then
      local err = messages
      if err == nil or err == "" then
         err = ("failed to retrieve DXC output blob: %s"):format(hresult_hex(hr))
      end
      release_com(result)
      release_com(compiler)
      return nil, err
   end

   local object_blob = ffi.cast("IDxcBlob *", object_out[0])
   local bytecode = blob_to_string(object_blob)

   release_com(object_blob)
   release_com(result)
   release_com(compiler)

   if #bytecode == 0 then
      if has_error_message(messages) then
         return nil, messages
      end
      return nil, "DXC compilation produced an empty output blob"
   end

   return {
      bytecode = bytecode,
      entrypoint = entrypoint,
      stage = stage,
      target_profile = target,
      messages = messages,
   }
end

return M
