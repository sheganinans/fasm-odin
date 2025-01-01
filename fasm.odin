package fasm

import "core:c"
import "core:dynlib"
import "core:encoding/endian"
import "core:fmt"
import "core:strings"

import win "core:sys/windows"

Options :: struct {
  buf_size: u32,
  passes:   u32,
}

API :: struct {
  lib:             dynlib.Library,
  committed:       rawptr,
  opts:            Options,
  fasm_GetVersion: proc() -> u32,
  fasm_Assemble:   proc(
    lpSource: cstring,
    lpMemory: rawptr,
    cbMemorySize: u32,
    nPassesLimit: u32,
    hDisplayPipe: rawptr,
  ) -> i16,
}

ApiResult :: union {
  API,
  DllError,
}
DllError :: distinct string

make :: proc(opts: Options = {buf_size = 0x800000, passes = 100}) -> ApiResult {
  api: API
  api.opts = opts
  _, api_ok := dynlib.initialize_symbols(&api, "./fasmx64.dll", "", "lib")
  if !api_ok {return (DllError)(dynlib.last_error())}

  info: win.SYSTEM_INFO
  win.GetSystemInfo(&info)

  alloc := win.VirtualAlloc(info.lpMinimumApplicationAddress, uint(opts.buf_size), win.MEM_RESERVE, win.PAGE_READWRITE)
  api.committed = win.VirtualAlloc(alloc, uint(opts.buf_size), win.MEM_COMMIT, win.PAGE_READWRITE)
  return api
}

FasmResult :: union {
  OkState,
  ErrState,
}
OkState :: distinct []byte
ErrState :: struct {
  err_code: ErrorCode,
  err_info: ErrInfo,
}
ErrInfo :: union {
  SrcErr,
  MacroErr,
}
SrcErr :: struct {
  line: u32,
  src:  string,
}
MacroErr :: struct {
  calling_line: u32,
  src_line:     u32,
  calling_src:  string,
  macro_src:    string,
}

version :: proc(api: API) -> string {
  v := api.fasm_GetVersion()
  maj := v & 0xFF_FF
  min := v & 0xFF_FF_00_00 >> 16
  return fmt.tprintf("%v.%v", maj, min)
}

run :: proc(api: API, input: cstring, opts: Options = {buf_size = 0x800000, passes = 100}) -> FasmResult {
  api.fasm_Assemble(input, api.committed, opts.buf_size, opts.passes, nil)
  bytes := ([^]byte)(api.committed)[:opts.buf_size]

  cond, _ := endian.get_u32(bytes[0:4], .Little)
  a, _ := endian.get_u32(bytes[4:8], .Little)
  b, _ := endian.get_u32(bytes[8:12], .Little)
  base := u32(uintptr(api.committed))

  if (Condition)(cond) == .FASM_OK {
    start := b - base
    return (OkState)(bytes[start:start + b])
  } else {
    header := b & 0x7F_FF_FF_FF
    hb := header - base
    ln, _ := endian.get_u32(bytes[hb + 4:hb + 8], .Little)
    src := strings.clone_from_cstring(input, allocator = context.temp_allocator)
    strs := strings.split(src, "\n", allocator = context.temp_allocator)
    ret := ErrState {
      err_code = (ErrorCode)(a),
    }
    if b & 0x80_00_00_00 == 0 {
      ret.err_info = SrcErr {
        line = ln,
        src  = strs[ln - 1],
      }
      return ret
    } else {
      mcl, _ := endian.get_u32(bytes[hb + 12:hb + 16], .Little)
      mcl_h := mcl - base
      ln2, _ := endian.get_u32(bytes[mcl_h + 4:mcl_h + 8], .Little)
      ret.err_info = MacroErr {
        calling_line = ln,
        src_line     = ln2,
        calling_src  = strs[ln - 1],
        macro_src    = strs[ln2 - 1],
      }
      return ret
    }
  }
}

DestroyErr :: union {
  DllError,
}

destroy :: proc(api: API) -> (res: DestroyErr = nil) {
  win.VirtualFree(api.committed, uint(api.opts.buf_size), win.MEM_DECOMMIT)
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