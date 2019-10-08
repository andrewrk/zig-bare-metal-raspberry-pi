export fn kernelMain() noreturn {
    // set exception stacks
    asm volatile(
        \\ cps #0x17 // enter data abort mode
        \\ mov r0,#0x08000000
        \\ sub r0,0x10000
        \\ mov sp,r0
        \\
        \\ cps #0x1b // enter undefined instruction mode
        \\ mov r0,#0x08000000
        \\ sub r0,0x20000
        \\ mov sp,r0
        \\
        \\ cps #0x1f // back to system mode
    );
    arm.setVectorBaseAddressRegister(0x1000);
    arm.setBssToZero();

    serial.init();
    log("\n{} {} ...", name, release_tag);

    fb.init();
    log("drawing logo ...");
    var logo: Bitmap = undefined;
    var logo_bmp_file align(@alignOf(u32)) = @embedFile("../assets/zig-logo.bmp");
    logo.init(&fb, &logo_bmp_file);
    logo.drawRect(logo.width, logo.height, 0, 0, 0, 0);

    screen_activity.init(logo.width, logo.height);
    serial_activity.init();
    vchi_activity.init();

    while (true) {
        screen_activity.update();
        serial_activity.update();
        vchi_activity.update();
    }
}

const ScreenActivity = struct {
    width: u32,
    height: u32,
    color: Color,
    color32: u32,
    top: u32,
    x: u32,
    y: u32,

    fn init(self: *ScreenActivity, width: u32, height: u32) void {
        self.width = width;
        self.height = height;
        self.color = color_yellow;
        self.color32 = fb.color32(self.color);
        self.top = height + margin;
        self.x = 0;
        self.y = self.top;
    }

    fn update (self: *ScreenActivity) void {
        var batch: u32 = 0;
        while (batch < 20 and self.x < self.width) : (batch += 1) {
            fb.drawPixel32(self.x, self.y, self.color32);
            self.x += 1;
        }
        if (self.x == self.width) {
            self.x = 0;
            self.y += 1;
            if (self.y == self.top + self.height) {
                self.y = self.top;
            }
            const delta = 10;
            self.color.red = self.color.red +% delta;
            if (self.color.red < delta) {
                self.color.green = self.color.green +% delta;
                if (self.color.green < delta) {
                    self.color.blue = self.color.blue +% delta;
                }
            }
            self.color32 = fb.color32(self.color);
        }
    }
};

const SerialActivity = struct {
    fn init(self: *SerialActivity) void {
        log("now echoing input on uart1 ...");
    }

    fn update(self: *SerialActivity) void {
        if (!serial.isReadByteReady()) {
            return;
        }
        const byte = serial.readByte();
        switch (byte) {
            '!' => {
                var x = @intToPtr(*u32, 2).*;
                log("ok {x}", x);
            },
            '\r' => {
                serial.writeText("\n");
            },
            else => serial.writeByteBlocking(byte),
        }
    }
};

const VchiActivity = struct {
    vchi: Vchi,
    cursor_x: u32,
    cursor_y: u32,

    fn init(self: *VchiActivity) void {
        self.vchi.init();
        self.cursor_x = fb.physical_width / 2;
        self.cursor_y = fb.physical_height / 2;
        fb.moveCursor(self.cursor_x, self.cursor_y);
        self.vchi.cecOpenNotificationService();
    }

    fn update(self: *VchiActivity) void {
        while (self.vchi.wasButtonPressedReceived()) {
            const button_code = self.vchi.receiveButtonPressedBlocking();
            var dx: i32 = 0;
            var dy: i32 = 0;
            const delta = switch (button_code) {
                0x01 => {
                    dy = -1;
                },
                0x02 => {
                    dy = 1;
                },
                0x03 => {
                    dx = -1;
                },
                0x04 => {
                    dx = 1;
                },
                else => {
                },
            };
            const scale = 64;
            const x = @intCast(i32, self.cursor_x) + dx * scale;
            if (x > 0 and x < @intCast(i32, fb.physical_width) - 1) {
                self.cursor_x = @intCast(u32, x);
            }
            const y = @intCast(i32, self.cursor_y) + dy * scale;
            if (y > 0 and y < @intCast(i32, fb.physical_height) - 1) {
                self.cursor_y = @intCast(u32, y);
            }
            fb.moveCursor(self.cursor_x, self.cursor_y);
        }
    }
};

comptime {
    asm(
        \\.section .text.boot // .text.boot to keep this in the first portion of the binary
        \\.globl _start
        \\_start:
    );

    if (build_options.subarch >= 7) {
        asm(
            \\ mrc p15, 0, r0, c0, c0, 5
            \\ and r0,#3
            \\ cmp r0,#0
            \\ beq core_0
            \\
            \\not_core_0:
            \\ wfe
            \\ b not_core_0
            \\
            \\core_0:
        );
    }

    asm(
        \\ cps #0x1f // enter system mode
        \\ mov sp,#0x08000000
        \\ bl kernelMain
        \\
        \\.section .text.exception_vector_table
        \\.balign 0x80
        \\exception_vector_table:
        \\ b exceptionEntry0x00
        \\ b exceptionEntry0x01
        \\ b exceptionEntry0x02
        \\ b exceptionEntry0x03
        \\ b exceptionEntry0x04
        \\ b exceptionEntry0x05
        \\ b exceptionEntry0x06
        \\ b exceptionEntry0x07
    );
}

export fn exceptionEntry0x00() noreturn {
    exceptionHandler(0x00);
}

export fn exceptionEntry0x01() noreturn {
    exceptionHandler(0x01);
}

export fn exceptionEntry0x02() noreturn {
    exceptionHandler(0x02);
}

export fn exceptionEntry0x03() noreturn {
    exceptionHandler(0x03);
}

export fn exceptionEntry0x04() noreturn {
    exceptionHandler(0x04);
}

export fn exceptionEntry0x05() noreturn {
    exceptionHandler(0x05);
}

export fn exceptionEntry0x06() noreturn {
    exceptionHandler(0x06);
}

export fn exceptionEntry0x07() noreturn {
    exceptionHandler(0x07);
}

fn exceptionHandler(entry: u32) noreturn {
    log("arm exception taken");
    log("entry {}", entry);
    log("spsr  0x{x}", arm.spsr());
    log("cpsr  0x{x}", arm.cpsr());
    log("sp    0x{x}", arm.sp());
    log("sctlr 0x{x}", arm.sctlr());
    arm.hang("execution is now stopped in arm exception handler");
}

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panicf("main.zig pub fn panic(): {}", message);
}

var fb: FrameBuffer = undefined;
var screen_activity: ScreenActivity = undefined;
var serial_activity: SerialActivity = undefined;
var vchi_activity: VchiActivity = undefined;

const margin = 10;

const color_red = Color{ .red = 255, .green = 0, .blue = 0, .alpha = 255 };
const color_green = Color{ .red = 0, .green = 255, .blue = 0, .alpha = 255 };
const color_blue = Color{ .red = 0, .green = 0, .blue = 255, .alpha = 255 };
const color_yellow = Color{ .red = 255, .green = 255, .blue = 0, .alpha = 255 };
const color_white = Color{ .red = 255, .green = 255, .blue = 255, .alpha = 255 };

const name = "zig-bare-metal-raspberry-pi";
const release_tag = "0.2";

const arm = @import("arm_assembly_code.zig");
const build_options = @import("build_options");
const builtin = @import("builtin");
const Bitmap = @import("video_core_frame_buffer.zig").Bitmap;
const Color = @import("video_core_frame_buffer.zig").Color;
const FrameBuffer = @import("video_core_frame_buffer.zig").FrameBuffer;
const log = serial.log;
const panicf = arm.panicf;
const serial = @import("serial.zig");
const std = @import("std");
const Vchi = @import("video_core_vchi.zig").Vchi;
