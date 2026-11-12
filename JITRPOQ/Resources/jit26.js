// JIT RPOQ · iOS 26 JIT 桥接脚本
// 由 JIT RPOQ 内置。协议：debugserver + brk #0xf00d（JIT 页申请）。
// 可自由修改/替换，脚本里可用 log / send_command / prepare_memory_region / get_pid。

var pid = get_pid();
log("[RPOQ] attach pid=" + pid);

var attach = send_command("vAttach;" + pid.toString(16));
log("[RPOQ] attach => " + attach);

var finished = false;
var steps = 0;
var MAX_STEPS = 2000000;

function bytesOf(hex) {
  var out = [];
  if (!hex) return out;
  for (var i = 0; i + 1 < hex.length; i += 2) {
    out.push(parseInt(hex.substr(i, 2), 16));
  }
  return out;
}

function leNumber(hex) {
  var bytes = bytesOf(hex);
  var value = BigInt(0);
  for (var i = bytes.length - 1; i >= 0; i--) {
    value = (value << BigInt(8)) | BigInt(bytes[i] & 0xff);
  }
  return value;
}

function leHex(value) {
  var bytes = [];
  var rest = value;
  for (var i = 0; i < 8; i++) {
    bytes.push((rest & BigInt(0xff)).toString(16).padStart(2, "0"));
    rest = rest >> BigInt(8);
  }
  return bytes.join("");
}

function regOf(response, number) {
  var key = ";" + number.toString(16).padStart(2, "0") + ":";
  var at = response.indexOf(key);
  if (at < 0 && number < 16) {
    at = response.indexOf(";" + "0" + number.toString(16) + ":");
    key = ";" + "0" + number.toString(16) + ":";
  }
  if (at < 0) return null;
  var start = at + key.length;
  var end = response.indexOf(";", start);
  return response.substring(start, end < 0 ? response.length : end);
}

function resume(tid) {
  if (tid) send_command("vCont;c:" + tid);
  else send_command("c");
}

while (!finished && steps < MAX_STEPS) {
  steps++;
  var stop = send_command("c");
  if (!stop) { log("[RPOQ] no stop packet, end"); break; }
  if (stop.charAt(0) === "W" || stop.charAt(0) === "X") {
    log("[RPOQ] process exited: " + stop);
    break;
  }
  if (stop.charAt(0) !== "T") { log("[RPOQ] unexpected packet " + stop); break; }

  var tidHex = null;
  var tidMatch = /thread:([0-9a-fA-F]+)/.exec(stop);
  if (tidMatch) tidHex = tidMatch[1];

  var pc = regOf(stop, 0x20);
  if (!pc) { log("[RPOQ] no pc"); resume(tidHex); continue; }

  var instruction = send_command("m" + pc + ",4");
  var bytes = bytesOf(instruction);
  if (bytes.length < 4) { resume(tidHex); continue; }
  var opcode = (bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24)) >>> 0;
  var isBreakpoint = ((opcode & 0xffe0001f) >>> 0) === (0xd4200000 >>> 0);
  if (!isBreakpoint) { resume(tidHex); continue; }

  var immediate = (opcode >>> 5) & 0xffff;
  var nextPC = leHex(leNumber(pc) + BigInt(4));
  if (tidHex) send_command("P20=" + nextPC + ";thread:" + tidHex + ";");

  if (immediate !== 0xf00d) {
    resume(tidHex);
    continue;
  }

  var command = leNumber(regOf(stop, 0x10) || "00");
  log("[RPOQ] jit call " + command);

  if (command === BigInt(0)) {
    var detach = send_command("D");
    log("[RPOQ] detach => " + detach);
    finished = true;
    break;
  }

  if (command === BigInt(1)) {
    var address = leNumber(regOf(stop, 0x00) || "00");
    var size = leNumber(regOf(stop, 0x01) || "00");
    if (size !== BigInt(0)) {
      if (address === BigInt(0)) {
        var allocated = send_command("_M" + size.toString(16) + ",rx");
        if (allocated) address = BigInt("0x" + allocated);
      }
      if (address !== BigInt(0)) {
        prepare_memory_region(address, size);
        if (tidHex) send_command("P0=" + leHex(address) + ";thread:" + tidHex + ";");
      }
    }
    resume(tidHex);
    continue;
  }

  // 其它 brk 命令（0x68 注入脚本等）交回系统继续跑
  resume(tidHex);
}

if (!finished) {
  log("[RPOQ] loop ended without detach, sending D");
  send_command("D");
}
log("[RPOQ] done after " + steps + " stops");
