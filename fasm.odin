package fasm

import "core:c"
import "core:dynlib"
import "core:fmt"
import "core:strings"

import win "core:sys/windows"

API :: struct {
  lib:             dynlib.Library,
  committed:       rawptr,
  buf_size:        u32,
  fasm_GetVersion: proc() -> u32,
  fasm_Assemble:   proc(
    lpSource: cstring,
    lpMemory: rawptr,
    cbMemorySize: u32,
    nPassesLimit: u32,
    hDisplayPipe: rawptr,
  ) -> i16,
}

ApiResult :: union #no_nil {
  API,
  DllError,
}
DllError :: distinct string

@(private)
alloc_mem :: proc(buf_size: u32) -> rawptr {
  info: win.SYSTEM_INFO
  win.GetSystemInfo(&info)
  alloc := win.VirtualAlloc(info.lpMinimumApplicationAddress, uint(buf_size), win.MEM_RESERVE, win.PAGE_READWRITE)
  return win.VirtualAlloc(alloc, uint(buf_size), win.MEM_COMMIT, win.PAGE_READWRITE)
}

make :: proc(buf_size: u32 = 0x800000) -> ApiResult {
  api: API
  api.buf_size = buf_size
  _, api_ok := dynlib.initialize_symbols(&api, "./fasmx64.dll", "", "lib")
  if !api_ok {return (DllError)(dynlib.last_error())}
  api.committed = alloc_mem(buf_size)
  return api
}

resize_buffer :: proc(api: ^API, buf_size: u32) {
  if api.buf_size != buf_size {
    win.VirtualFree(api.committed, uint(api.buf_size), win.MEM_DECOMMIT)
    api.committed = alloc_mem(buf_size)
    api.buf_size = buf_size
  }
}

FasmResult :: union #no_nil {
  OkState,
  ErrState,
}
OkState :: distinct []byte
ErrState :: struct {
  err_code: ErrorCode,
  err_info: ErrInfo,
}
ErrInfo :: union #no_nil {
  SrcErr,
  MacroErr,
}
SrcErr :: struct {
  line: u32,
  src:  string,
}
MacroErr :: struct {
  calling_line: u32,
  calling_src:  string,
  src_line:     u32,
  macro_src:    string,
}

version :: proc(api: API) -> string {
  v := api.fasm_GetVersion()
  maj := v & 0xFF_FF
  min := v & 0xFF_FF_00_00 >> 16
  return fmt.tprintf("%v.%v", maj, min)
}

@(private)
FASM_STATE :: struct {
  cond:  u32,
  ol_ec: u32, // output length or error code
  od_el: u32, // output data or error line
}

@(private)
LINE_HEADER :: struct {
  file_path:   u32,
  line_number: u32,
  fo_mcl:      u32, // file offset or macro calling line
  ml:          u32, // macro line
}

run :: proc(api: API, input: cstring, passes: u32 = 100) -> FasmResult {
  api.fasm_Assemble(input, api.committed, api.buf_size, passes, nil)
  bytes := ([^]byte)(api.committed)[:api.buf_size]

  fs := (^FASM_STATE)(&bytes[0])
  base := u32(uintptr(api.committed))

  if (Condition)(fs.cond) == .FASM_OK {
    start := fs.od_el - base
    return (OkState)(bytes[start:start + fs.od_el])
  } else {
    header := fs.od_el & 0x7F_FF_FF_FF
    h1 := (^LINE_HEADER)(&bytes[header - base])
    src := strings.clone_from_cstring(input, allocator = context.temp_allocator)
    strs := strings.split(src, "\n", allocator = context.temp_allocator)
    ret := ErrState {
      err_code = (ErrorCode)(fs.ol_ec),
    }
    if fs.od_el & 0x80_00_00_00 == 0 {
      ret.err_info = SrcErr {
        line = h1.line_number,
        src  = strs[h1.line_number - 1],
      }
    } else {
      h2 := (^LINE_HEADER)(&bytes[h1.ml - base])
      ret.err_info = MacroErr {
        calling_line = h1.line_number,
        calling_src  = strs[h1.line_number - 1],
        src_line     = h2.line_number,
        macro_src    = strs[h2.line_number - 1],
      }
    }
    return ret
  }
}

DestroyErr :: union {
  DllError,
}

destroy :: proc(api: API) -> (res: DestroyErr = nil) {
  win.VirtualFree(api.committed, uint(api.buf_size), win.MEM_DECOMMIT)
  if !dynlib.unload_library(api.lib) {
    res = (DllError)(dynlib.last_error())
  }
  return
}

Condition :: enum c.int {
  FASM_OK                          = 0,
  FASM_WORKING                     = 1,
  FASM_ERROR                       = 2,
  FASM_INVALID_PARAMETER           = -1,
  FASM_OUT_OF_MEMORY               = -2,
  FASM_STACK_OVERFLOW              = -3,
  FASM_SOURCE_NOT_FOUND            = -4,
  FASM_UNEXPECTED_END_OF_SOURCE    = -5,
  FASM_CANNOT_GENERATE_CODE        = -6,
  FASM_FORMAT_LIMITATIONS_EXCEDDED = -7,
  FASM_WRITE_FAILED                = -8,
  FASM_INVALID_DEFINITION          = -9,
}

ErrorCode :: enum c.int {
  FASMERR_FILE_NOT_FOUND                      = -101,
  FASMERR_ERROR_READING_FILE                  = -102,
  FASMERR_INVALID_FILE_FORMAT                 = -103,
  FASMERR_INVALID_MACRO_ARGUMENTS             = -104,
  FASMERR_INCOMPLETE_MACRO                    = -105,
  FASMERR_UNEXPECTED_CHARACTERS               = -106,
  FASMERR_INVALID_ARGUMENT                    = -107,
  FASMERR_ILLEGAL_INSTRUCTION                 = -108,
  FASMERR_INVALID_OPERAND                     = -109,
  FASMERR_INVALID_OPERAND_SIZE                = -110,
  FASMERR_OPERAND_SIZE_NOT_SPECIFIED          = -111,
  FASMERR_OPERAND_SIZES_DO_NOT_MATCH          = -112,
  FASMERR_INVALID_ADDRESS_SIZE                = -113,
  FASMERR_ADDRESS_SIZES_DO_NOT_AGREE          = -114,
  FASMERR_DISALLOWED_COMBINATION_OF_REGISTERS = -115,
  FASMERR_LONG_IMMEDIATE_NOT_ENCODABLE        = -116,
  FASMERR_RELATIVE_JUMP_OUT_OF_RANGE          = -117,
  FASMERR_INVALID_EXPRESSION                  = -118,
  FASMERR_INVALID_ADDRESS                     = -119,
  FASMERR_INVALID_VALUE                       = -120,
  FASMERR_VALUE_OUT_OF_RANGE                  = -121,
  FASMERR_UNDEFINED_SYMBOL                    = -122,
  FASMERR_INVALID_USE_OF_SYMBOL               = -123,
  FASMERR_NAME_TOO_LONG                       = -124,
  FASMERR_INVALID_NAME                        = -125,
  FASMERR_RESERVED_WORD_USED_AS_SYMBOL        = -126,
  FASMERR_SYMBOL_ALREADY_DEFINED              = -127,
  FASMERR_MISSING_END_QUOTE                   = -128,
  FASMERR_MISSING_END_DIRECTIVE               = -129,
  FASMERR_UNEXPECTED_INSTRUCTION              = -130,
  FASMERR_EXTRA_CHARACTERS_ON_LINE            = -131,
  FASMERR_SECTION_NOT_ALIGNED_ENOUGH          = -132,
  FASMERR_SETTING_ALREADY_SPECIFIED           = -133,
  FASMERR_DATA_ALREADY_DEFINED                = -134,
  FASMERR_TOO_MANY_REPEATS                    = -135,
  FASMERR_SYMBOL_OUT_OF_SCOPE                 = -136,
  FASMERR_USER_ERROR                          = -140,
  FASMERR_ASSERTION_FAILED                    = -141,
}
